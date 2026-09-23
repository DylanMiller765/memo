import StoreKit
import SwiftUI
import RevenueCat

@MainActor
private enum RevenueCatBootstrap {
    private static var isConfigured = false

    static func configureIfNeeded() {
        guard !isConfigured else { return }
        Purchases.logLevel = .info
        Purchases.configure(
            with: Configuration.Builder(withAPIKey: "appl_NUUkNGthSiwlZSAtrDjAfxUGOPC")
                .with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2)
                .build()
        )
        isConfigured = true
    }
}

@MainActor
@Observable
final class StoreService {
    var isProUser = false
    /// Legacy alias — prefer `isProUser`. Kept temporarily so call sites compile during the
    /// tier-collapse refactor. Both legacy Pro and new Pro (formerly Ultra) subscribers get
    /// full features now.
    var isUltraUser: Bool {
        get { isProUser }
        set { isProUser = newValue }
    }
    var products: [Product] = []
    var purchaseError: String?
    var isLoading = false

    /// Intro offer on the canonical annual SKU, and whether *this* account can
    /// still use it. Resolved from StoreKit rather than assumed — a returning
    /// subscriber who already burned the trial is not eligible, and the paywall
    /// must not promise them "$0.00" and then present a full-price sheet.
    var annualIntroOffer: Product.SubscriptionOffer?
    var isEligibleForAnnualIntroOffer = false

    /// e.g. "7 days". Nil whenever no usable free trial exists — the single
    /// switch every "free trial" claim on the paywall should read.
    var annualFreeTrialLabel: String? {
        guard isEligibleForAnnualIntroOffer,
              let offer = annualIntroOffer,
              offer.paymentMode == .freeTrial else { return nil }
        return offer.period.trialLengthLabel
    }

    /// Real trial length in days, for scheduling the pre-billing reminder.
    /// Nil when there's no usable trial, so no reminder gets scheduled for a
    /// full-price purchase.
    var annualFreeTrialDays: Int? {
        guard isEligibleForAnnualIntroOffer,
              let offer = annualIntroOffer,
              offer.paymentMode == .freeTrial else { return nil }
        return offer.period.approximateDays
    }

    func refreshAnnualIntroOffer() async {
        guard let annual = products.first(where: { $0.id == Self.annualUltraProductID }),
              let subscription = annual.subscription else {
            annualIntroOffer = nil
            isEligibleForAnnualIntroOffer = false
            return
        }
        let offer = subscription.introductoryOffer
        let eligible = await subscription.isEligibleForIntroOffer
        annualIntroOffer = offer
        isEligibleForAnnualIntroOffer = eligible && offer != nil
    }

    // MARK: Product IDs
    //
    // Two SKU families exist due to the v2.0 single-tier pivot:
    //   • `com.memori.pro.*`   — LEGACY ($3.99 / $19.99). Grandfathered for old subscribers.
    //                            DO NOT use these for new purchases.
    //   • `com.memori.ultra.*` — CANONICAL weekly + annual plans. All
    //                            new paywalls must charge these. They are kept under the
    //                            "ultra" name in App Store Connect even though Ultra-as-tier
    //                            no longer exists in the app — both families now grant the
    //                            same Pro entitlement (see updateSubscriptionStatus below).
    //
    // Renaming the App Store Connect SKUs would invalidate active subscriptions, so the
    // "ultra" suffix is permanent. Any callsite reading these constants is correct in
    // semantics — only the name is misleading.
    nonisolated static let weeklyProductID = "com.memori.pro.weekly"
    nonisolated static let monthlyProductID = "com.memori.pro.monthly"
    nonisolated static let annualProductID = "com.memori.pro.annual"

    nonisolated static let weeklyUltraProductID = "com.memori.ultra.weekly"
    nonisolated static let monthlyUltraProductID = "com.memori.ultra.monthly"
    nonisolated static let annualUltraProductID = "com.memori.ultra.annual"
    // Founder annual SKU: pay today and renew at the founder price while the subscription
    // remains active. Kept under the existing product ID because the SKU is already approved.
    nonisolated static let annualUltraExitOfferProductID = "com.memori.ultra.annual.firstyear"

    private var updateListenerTask: Task<Void, Error>?
    private var productLoadTask: Task<Void, Never>?
    private var delayedPrefetchTask: Task<Void, Never>?
    private var hasStarted = false

    /// Kept for preview/test call-site compatibility. Initialization is deliberately
    /// side-effect free; `startIfNeeded()` owns listeners and entitlement syncing.
    init(loadProductsOnInit _: Bool = false) {}

    func startIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true

        if UserDefaults.standard.object(forKey: "installDate") == nil {
            UserDefaults.standard.set(Date.now, forKey: "installDate")
        }

        RevenueCatBootstrap.configureIfNeeded()
        updateListenerTask = listenForTransactions()
        await updateSubscriptionStatus(source: "storekit_initial_sync")
    }

    /// Starts a single delayed product request after startup. A paywall can call
    /// `loadProducts()` at any time and will reuse or supersede this work.
    func scheduleProductPrefetch() {
        guard delayedPrefetchTask == nil, products.isEmpty else { return }
        delayedPrefetchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self else { return }
            await self.loadProducts()
        }
    }

    func loadProducts() async {
        if !products.isEmpty { return }
        if let productLoadTask {
            await productLoadTask.value
            return
        }

        delayedPrefetchTask?.cancel()
        delayedPrefetchTask = nil
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performProductLoad()
        }
        productLoadTask = task
        await task.value
        productLoadTask = nil
    }

    private func performProductLoad() async {
        isLoading = true
        defer { isLoading = false }

        // One flaky request at launch used to leave the paywall permanently
        // dead ("offer is not ready yet" on every plan). Retry with backoff;
        // only surface an error if all attempts come back empty.
        let requestIDs: Set<String> = [
            Self.weeklyProductID,
            Self.annualProductID,
            Self.weeklyUltraProductID,
            Self.monthlyUltraProductID,
            Self.annualUltraProductID,
            Self.annualUltraExitOfferProductID
        ]

        var lastError: Error?
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_200_000_000)
            }
            do {
                let loaded = try await Product.products(for: requestIDs)
                if !loaded.isEmpty {
                    products = loaded.sorted { $0.price < $1.price }
                    await refreshAnnualIntroOffer()
                    return
                }
            } catch {
                lastError = error
            }
        }

        if products.isEmpty {
            purchaseError = lastError != nil
                ? "Can't reach the App Store. Check your connection and try again."
                : "Plans are still loading. Try again in a moment."
        }
    }

    @discardableResult
    func purchase(_ product: Product) async -> StorePurchaseOutcome {
        await startIfNeeded()
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await recordRevenueCatPurchase(result, productID: transaction.productID)
                await transaction.finish()
                await updateSubscriptionStatus(source: "storekit_purchase_success")
                return .success(productID: transaction.productID)
            case .userCancelled:
                return .userCancelled
            case .pending:
                purchaseError = "Purchase is pending approval."
                return .pending
            @unknown default:
                return .failed(reason: "Unknown purchase result.")
            }
        } catch {
            let reason = error.localizedDescription
            purchaseError = "Purchase failed: \(reason)"
            return .failed(reason: reason)
        }
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        await startIfNeeded()
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
        await updateSubscriptionStatus(source: "storekit_restore")
        return isProUser
    }

    func updateSubscriptionStatus(source: String = "storekit_current_entitlements") async {
        var hasActiveProEntitlement = false
        var hasActiveUltraEntitlement = false
        var activeProductIDs: [String] = []
        let previousStatus = isProUser

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                if transaction.productID == Self.weeklyProductID ||
                   transaction.productID == Self.monthlyProductID ||
                   transaction.productID == Self.annualProductID {
                    hasActiveProEntitlement = true
                    activeProductIDs.append(transaction.productID)
                } else if transaction.productID == Self.weeklyUltraProductID ||
                          transaction.productID == Self.monthlyUltraProductID ||
                          transaction.productID == Self.annualUltraProductID ||
                          transaction.productID == Self.annualUltraExitOfferProductID {
                    hasActiveUltraEntitlement = true
                    activeProductIDs.append(transaction.productID)
                }
            }
        }

        // Single tier: any active sub (legacy Pro OR new Pro/formerly-Ultra) grants full Pro.
        isProUser = hasActiveProEntitlement || hasActiveUltraEntitlement
        Analytics.subscriptionStatusSynced(
            source: source,
            isMember: isProUser,
            activeProductIDs: activeProductIDs.sorted(),
            didChange: previousStatus != isProUser
        )
    }

    /// The verified expiration of the current subscription period. During an
    /// introductory free trial this is the trial end, not a guessed start + N days.
    func currentEntitlementExpirationDate(for productID: String) async -> Date? {
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result),
               transaction.productID == productID {
                return transaction.expirationDate
            }
        }
        return nil
    }

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if let transaction = try? await self.checkVerified(result) {
                    await transaction.finish()
                    await self.updateSubscriptionStatus(source: "storekit_transaction_update")
                }
            }
        }
    }

    private func recordRevenueCatPurchase(_ result: Product.PurchaseResult, productID: String) async {
        RevenueCatBootstrap.configureIfNeeded()
        do {
            _ = try await Purchases.shared.recordPurchase(result)
            Analytics.revenueCatPurchaseRecorded(productID: productID)
        } catch {
            Analytics.revenueCatPurchaseRecordFailed(productID: productID, reason: error.localizedDescription)
        }
    }

    private func checkVerified<T>(_ result: StoreKit.VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreServiceError.failedVerification
        case .verified(let item):
            return item
        }
    }

    var weeklyProduct: Product? {
        products.first { $0.id == Self.weeklyProductID }
    }

    var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyProductID }
    }

    var annualProduct: Product? {
        products.first { $0.id == Self.annualProductID }
    }

    var weeklyUltraProduct: Product? { products.first { $0.id == Self.weeklyUltraProductID } }
    var monthlyUltraProduct: Product? { products.first { $0.id == Self.monthlyUltraProductID } }
    var annualUltraProduct: Product? { products.first { $0.id == Self.annualUltraProductID } }
}

extension Product.SubscriptionPeriod {
    /// Human trial length. A one-week period reads as "7 days" because that's
    /// how the rest of the funnel says it.
    var trialLengthLabel: String {
        switch unit {
        case .day: return value == 1 ? "1 day" : "\(value) days"
        case .week: return value == 1 ? "7 days" : "\(value) weeks"
        case .month: return value == 1 ? "1 month" : "\(value) months"
        case .year: return value == 1 ? "1 year" : "\(value) years"
        @unknown default: return "\(value)"
        }
    }

    var approximateDays: Int {
        switch unit {
        case .day: return value
        case .week: return value * 7
        case .month: return value * 30
        case .year: return value * 365
        @unknown default: return value
        }
    }
}

enum StoreServiceError: Error {
    case failedVerification
}

enum StorePurchaseOutcome: Equatable {
    case success(productID: String)
    case userCancelled
    case pending
    case failed(reason: String)
}
