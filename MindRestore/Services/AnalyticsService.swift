import Foundation
import PostHog

enum Analytics {
    static let apiKey = "phc_mAu7DCNXJbqro9iG6KzYbxhTqa4s442BAmS3tCt7vPJu"
    static let host = "https://us.i.posthog.com"
    static let onboardingStepNames = [
        "welcome",
        "name",
        "goals",
        "age",
        "screenTimeAccess",
        "lifetimeShock",
        "lifeSquaresReceipt",
        "protectTarget",
        "feedWinMoment",
        "personalizationBeat",
        "memoPlan",
        "trialTrustBridge",
        "trialReminderBridge",
        "planPersonalizing",
        "focusMode",
        "notificationPriming",
        "targetSelection",
        "unlockLoopDemo"
    ]

    static func configure() {
        let config = PostHogConfig(projectToken: apiKey, host: host)
        config.captureApplicationLifecycleEvents = true
        // Replay never starts on its own: only onboarding and its paywall are
        // recorded (see startOnboardingReplay). Screenshot mode, because
        // wireframes draw the hill and stickers as grey boxes.
        config.sessionReplay = false
        config.sessionReplayConfig.screenshotMode = true
        // This flag masks every label, not just fields. Onboarding and its
        // paywall have no text entry (passwords are always masked), and the
        // copy is what we need to read in a replay.
        config.sessionReplayConfig.maskAllTextInputs = false
        config.sessionReplayConfig.maskAllImages = false
        config.sessionReplayConfig.captureNetworkTelemetry = false
        #if DEBUG
        config.debug = true
        #endif
        PostHogSDK.shared.setup(config)
        InternalDevice.tagIfNeeded()
    }

    // MARK: - Session replay

    @MainActor private static var onboardingReplayTask: Task<Void, Never>?

    /// Records onboarding and its paywall. On a first launch PostHog's remote
    /// settings can land a few seconds after onboarding appears, and recording
    /// can't start before them, so keep trying briefly.
    @MainActor static func startOnboardingReplay() {
        onboardingReplayTask?.cancel()
        onboardingReplayTask = Task { @MainActor in
            for _ in 0..<20 {
                PostHogSDK.shared.startSessionRecording()
                if PostHogSDK.shared.isSessionReplayActive() || Task.isCancelled { return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @MainActor static func stopOnboardingReplay() {
        onboardingReplayTask?.cancel()
        onboardingReplayTask = nil
        PostHogSDK.shared.stopSessionRecording()
    }

    // MARK: - User Identification

    /// Identify the current user and set their properties for segmentation
    static func identify(userId: String, isProUser: Bool, brainAge: Int?, streak: Int, gamesPlayed: Int) {
        var properties: [String: Any] = [
            "is_pro_user": isProUser,
            "streak": streak,
            "games_played": gamesPlayed
        ]
        if let brainAge {
            properties["brain_age"] = brainAge
        }
        PostHogSDK.shared.identify(userId, userProperties: properties)
    }

    /// Update user properties without re-identifying (call after subscription changes, brain score updates, etc.)
    static func updateUserProperties(isProUser: Bool? = nil, brainAge: Int? = nil, streak: Int? = nil) {
        var properties: [String: Any] = [:]
        if let isProUser {
            properties["is_pro_user"] = isProUser
            properties["is_member"] = isProUser
        }
        if let brainAge { properties["brain_age"] = brainAge }
        if let streak { properties["streak"] = streak }
        guard !properties.isEmpty else { return }
        PostHogSDK.shared.capture("$set", userProperties: properties)
    }

    // MARK: - Subscription State

    static func subscriptionStarted(
        plan: String,
        productID: String,
        conversionKind: String,
        trigger: String,
        isHighIntent: Bool,
        isExitOffer: Bool,
        hasTrial: Bool,
        price: Double?
    ) {
        var properties = paywallPurchaseProperties(
            productID: productID,
            plan: paywallPlanName(for: productID, fallback: plan),
            trigger: trigger,
            isHighIntent: isHighIntent,
            isExitOffer: isExitOffer,
            price: price
        )
        properties["conversion_kind"] = conversionKind
        properties["has_trial"] = hasTrial

        PostHogSDK.shared.capture("subscription.started", properties: properties)

        if conversionKind == "annual_trial" {
            PostHogSDK.shared.capture("subscription.trial_started", properties: properties)
        } else if conversionKind == "founder_forever" {
            PostHogSDK.shared.capture("subscription.founder_purchased", properties: properties)
        }

        PostHogSDK.shared.capture("$set", userProperties: [
            "is_member": true,
            "is_pro_user": true,
            "subscription_conversion_kind": conversionKind,
            "subscription_product_id": productID
        ])
    }

    static func subscriptionStatusSynced(
        source: String,
        isMember: Bool,
        activeProductIDs: [String],
        didChange: Bool
    ) {
        PostHogSDK.shared.capture("subscription.status_synced", properties: [
            "source": source,
            "is_member": isMember,
            "is_pro_user": isMember,
            "active_product_ids": activeProductIDs.joined(separator: ","),
            "active_product_count": activeProductIDs.count,
            "did_change": didChange
        ])
        updateUserProperties(isProUser: isMember)
    }

    static func revenueCatPurchaseRecorded(productID: String) {
        PostHogSDK.shared.capture("revenuecat.purchase_recorded", properties: [
            "product_id": productID
        ])
    }

    static func revenueCatPurchaseRecordFailed(productID: String, reason: String) {
        PostHogSDK.shared.capture("revenuecat.purchase_record_failed", properties: [
            "product_id": productID,
            "error_reason": reason
        ])
    }

    // MARK: - Session Tracking

    static func appOpened(daysSinceLastOpen: Int, currentStreak: Int, isProUser: Bool) {
        PostHogSDK.shared.capture("app.opened", properties: [
            "days_since_last_open": daysSinceLastOpen,
            "current_streak": currentStreak,
            "is_pro_user": isProUser
        ])
    }

    static func appOpenedFromNotification(notificationType: String) {
        PostHogSDK.shared.capture("app.opened_from_notification", properties: [
            "notification_type": notificationType
        ])
    }

    // MARK: - Onboarding

    static func onboardingStepName(for index: Int) -> String {
        guard onboardingStepNames.indices.contains(index) else { return "unknown" }
        return onboardingStepNames[index]
    }

    static func onboardingStepProperties(
        step: String,
        stepIndex: Int? = nil,
        totalSteps: Int = onboardingStepNames.count,
        secondsSinceStart: TimeInterval? = nil,
        secondsOnStep: TimeInterval? = nil,
        goals: [String] = [],
        selectedAge: Int? = nil,
        screenTimeHours: Double? = nil,
        screenTimeIsEstimate: Bool? = nil,
        brainAge: Int? = nil,
        brainScore: Int? = nil,
        receiptCount: Int? = nil,
        extraProperties: [String: Any] = [:],
        variant: String? = nil
    ) -> [String: Any] {
        var properties: [String: Any] = [
            "step": step,
            "total_steps": totalSteps
        ]

        if let stepIndex {
            properties["step_index"] = stepIndex
            let progress = Double(stepIndex + 1) / Double(max(totalSteps, 1)) * 100
            properties["progress_percent"] = Int(progress.rounded())
        }
        if let secondsSinceStart {
            properties["seconds_since_onboarding_start"] = Int(secondsSinceStart.rounded())
        }
        if let secondsOnStep {
            properties["seconds_on_step"] = Int(secondsOnStep.rounded())
        }
        if !goals.isEmpty {
            properties["goal_count"] = goals.count
            properties["goals"] = goals.joined(separator: ",")
        }
        if let selectedAge {
            properties["selected_age"] = selectedAge
        }
        if let screenTimeHours {
            properties["screen_time_hours"] = screenTimeHours
        }
        if let screenTimeIsEstimate {
            properties["screen_time_is_estimate"] = screenTimeIsEstimate
        }
        if let brainAge {
            properties["brain_age"] = brainAge
        }
        if let brainScore {
            properties["brain_score"] = brainScore
        }
        if let selectedAge, let brainAge {
            properties["brain_age_delta"] = brainAge - selectedAge
        }
        if let receiptCount {
            properties["receipt_count"] = receiptCount
        }
        if let variant {
            properties["onboarding_variant"] = variant
        }
        extraProperties.forEach { properties[$0.key] = $0.value }
        return properties
    }

    static func onboardingStarted(
        source: String = "first_launch",
        totalSteps: Int = onboardingStepNames.count,
        variant: String? = nil
    ) {
        var properties: [String: Any] = [
            "source": source,
            "total_steps": totalSteps
        ]
        if let variant { properties["onboarding_variant"] = variant }
        PostHogSDK.shared.capture("onboarding.started", properties: properties)
    }

    static func onboardingStepViewed(
        step: String,
        stepIndex: Int,
        totalSteps: Int = onboardingStepNames.count,
        secondsSinceStart: TimeInterval? = nil,
        previousStep: String? = nil,
        secondsOnPreviousStep: TimeInterval? = nil,
        variant: String? = nil
    ) {
        var properties = onboardingStepProperties(
            step: step,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            secondsSinceStart: secondsSinceStart,
            variant: variant
        )
        if let previousStep {
            properties["previous_step"] = previousStep
        }
        if let secondsOnPreviousStep {
            properties["seconds_on_previous_step"] = Int(secondsOnPreviousStep.rounded())
        }
        PostHogSDK.shared.capture("onboarding.step_viewed", properties: properties)
    }

    static func attributionSelectedProperties(source: AcquisitionSource?) -> [String: Any] {
        ["source": source?.rawValue ?? "skipped"]
    }

    // MARK: Onboarding demo beats
    // The demo is four beats inside one onboarding step; these show which beat loses people.

    static func demoStageViewedProperties(stage: String, secondsSinceDemoStart: Double, run: Int) -> [String: Any] {
        ["stage": stage, "seconds_since_demo_start": Int(secondsSinceDemoStart.rounded()), "run": run]
    }

    static func demoGameEndedProperties(levelsCleared: Int, secondsInGame: Double, run: Int) -> [String: Any] {
        [
            "levels_cleared": levelsCleared,
            "seconds_in_game": Int(secondsInGame.rounded()),
            "ended_by": OnboardingDemoRun.reachedCap(levelsCleared) ? "cap" : "miss",
            "run": run
        ]
    }

    /// stage: slot, game, unlock or rank.
    static func onboardingDemoStageViewed(stage: String, secondsSinceDemoStart: Double, run: Int) {
        PostHogSDK.shared.capture(
            "onboarding.demo_stage_viewed",
            properties: demoStageViewedProperties(stage: stage, secondsSinceDemoStart: secondsSinceDemoStart, run: run)
        )
    }

    static func onboardingDemoSlotLanded(secondsSinceDemoStart: Double) {
        PostHogSDK.shared.capture(
            "onboarding.demo_slot_landed",
            properties: ["seconds_since_demo_start": Int(secondsSinceDemoStart.rounded())]
        )
    }

    static func onboardingDemoGameEnded(levelsCleared: Int, secondsInGame: Double, run: Int) {
        PostHogSDK.shared.capture(
            "onboarding.demo_game_ended",
            properties: demoGameEndedProperties(levelsCleared: levelsCleared, secondsInGame: secondsInGame, run: run)
        )
    }

    static func onboardingDemoPlayAgain(run: Int) {
        PostHogSDK.shared.capture("onboarding.demo_play_again", properties: ["run": run])
    }

    /// "Where did you find Memo?" A skip is logged but never stored on the person.
    static func onboardingAttributionSelected(source: AcquisitionSource?) {
        PostHogSDK.shared.capture(
            "onboarding.attribution_selected",
            properties: attributionSelectedProperties(source: source)
        )
        guard let source else { return }
        PostHogSDK.shared.capture("$set", userProperties: ["acquisition_source": source.rawValue])
    }

    static func onboardingDroppedOff(
        lastStep: String,
        totalSteps: Int,
        stepIndex: Int? = nil,
        secondsSinceStart: TimeInterval? = nil,
        secondsOnStep: TimeInterval? = nil,
        goals: [String] = [],
        selectedAge: Int? = nil,
        screenTimeHours: Double? = nil,
        screenTimeIsEstimate: Bool? = nil,
        brainAge: Int? = nil,
        brainScore: Int? = nil,
        receiptCount: Int? = nil,
        variant: String? = nil
    ) {
        var properties = onboardingStepProperties(
            step: lastStep,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            secondsSinceStart: secondsSinceStart,
            secondsOnStep: secondsOnStep,
            goals: goals,
            selectedAge: selectedAge,
            screenTimeHours: screenTimeHours,
            screenTimeIsEstimate: screenTimeIsEstimate,
            brainAge: brainAge,
            brainScore: brainScore,
            receiptCount: receiptCount,
            variant: variant
        )
        properties["last_step"] = lastStep
        properties["steps_completed"] = (stepIndex ?? -1) + 1
        PostHogSDK.shared.capture("onboarding.dropped_off", properties: properties)
    }

    static func onboardingCompleted(
        goals: [String],
        selectedAge: Int? = nil,
        screenTimeHours: Double? = nil,
        screenTimeIsEstimate: Bool? = nil,
        brainAge: Int? = nil,
        brainScore: Int? = nil,
        receiptCount: Int? = nil,
        focusModeWasSetUp: Bool? = nil,
        notificationsEnabled: Bool? = nil,
        secondsSinceStart: TimeInterval? = nil,
        totalSteps: Int = onboardingStepNames.count,
        variant: String? = nil
    ) {
        var properties = onboardingStepProperties(
            step: "completed",
            stepIndex: totalSteps - 1,
            totalSteps: totalSteps,
            secondsSinceStart: secondsSinceStart,
            goals: goals,
            selectedAge: selectedAge,
            screenTimeHours: screenTimeHours,
            screenTimeIsEstimate: screenTimeIsEstimate,
            brainAge: brainAge,
            brainScore: brainScore,
            receiptCount: receiptCount,
            variant: variant
        )
        properties["goalCount"] = goals.count
        if let focusModeWasSetUp { properties["focus_mode_was_set_up"] = focusModeWasSetUp }
        if let notificationsEnabled { properties["notifications_enabled"] = notificationsEnabled }
        PostHogSDK.shared.capture("onboarding.completed", properties: properties)

        var userProperties: [String: Any] = [
            "onboarding_completed": true,
            "onboarding_goal_count": goals.count
        ]
        if let variant { userProperties["onboarding_variant"] = variant }
        if let selectedAge { userProperties["selected_age"] = selectedAge }
        if let screenTimeHours { userProperties["onboarding_screen_time_hours"] = screenTimeHours }
        if let screenTimeIsEstimate { userProperties["onboarding_screen_time_is_estimate"] = screenTimeIsEstimate }
        if let brainAge { userProperties["brain_age"] = brainAge }
        if let brainScore { userProperties["brain_score"] = brainScore }
        if let focusModeWasSetUp { userProperties["focus_mode_was_set_up"] = focusModeWasSetUp }
        if let notificationsEnabled { userProperties["notifications_enabled"] = notificationsEnabled }
        PostHogSDK.shared.capture("$set", userProperties: userProperties)
    }

    static func onboardingStep(
        step: String,
        stepIndex: Int? = nil,
        totalSteps: Int = onboardingStepNames.count,
        secondsSinceStart: TimeInterval? = nil,
        secondsOnStep: TimeInterval? = nil,
        goals: [String] = [],
        selectedAge: Int? = nil,
        screenTimeHours: Double? = nil,
        screenTimeIsEstimate: Bool? = nil,
        brainAge: Int? = nil,
        brainScore: Int? = nil,
        receiptCount: Int? = nil,
        extraProperties: [String: Any] = [:],
        variant: String? = nil
    ) {
        let properties = onboardingStepProperties(
            step: step,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            secondsSinceStart: secondsSinceStart,
            secondsOnStep: secondsOnStep,
            goals: goals,
            selectedAge: selectedAge,
            screenTimeHours: screenTimeHours,
            screenTimeIsEstimate: screenTimeIsEstimate,
            brainAge: brainAge,
            brainScore: brainScore,
            receiptCount: receiptCount,
            extraProperties: extraProperties,
            variant: variant
        )
        PostHogSDK.shared.capture("onboarding.step", properties: properties)
        PostHogSDK.shared.capture("onboarding.step_completed", properties: properties)
    }

    // MARK: - Navigation

    static func tabViewed(tab: String) {
        PostHogSDK.shared.capture("tab.viewed", properties: [
            "tab": tab
        ])
    }

    // MARK: - Exercises

    static func exerciseStarted(game: String) {
        PostHogSDK.shared.capture("exercise.started", properties: [
            "game": game
        ])
    }

    static func exerciseCompleted(game: String, score: Double, difficulty: Int) {
        PostHogSDK.shared.capture("exercise.completed", properties: [
            "game": game,
            "score": score,
            "difficulty": difficulty
        ])
    }

    static func personalBest(game: String, score: Int) {
        PostHogSDK.shared.capture("exercise.personalBest", properties: [
            "game": game,
            "score": score
        ])
    }

    static func exerciseAbandoned(game: String, roundReached: Int) {
        PostHogSDK.shared.capture("exercise.abandoned", properties: [
            "game": game,
            "round_reached": roundReached
        ])
    }

    // MARK: - Brain Score

    static func brainScoreCompleted(score: Int, brainAge: Int) {
        PostHogSDK.shared.capture("brainScore.completed", properties: [
            "score": score,
            "brainAge": brainAge
        ])
        // Also update the user property so we always have their latest brain age
        updateUserProperties(brainAge: brainAge)
    }

    // MARK: - Paywall

    static func paywallPurchaseProperties(
        productID: String,
        plan: String,
        trigger: String,
        isHighIntent: Bool,
        isExitOffer: Bool,
        price: Double? = nil,
        errorReason: String? = nil
    ) -> [String: Any] {
        var properties: [String: Any] = [
            "product_id": productID,
            "plan": plan,
            "trigger": trigger,
            "is_high_intent": isHighIntent,
            "is_exit_offer": isExitOffer
        ]
        if let price { properties["$revenue"] = price }
        if let errorReason { properties["error_reason"] = errorReason }
        return properties
    }

    static func paywallShown(trigger: String = "unknown", isHighIntent: Bool? = nil, selectedPlan: String? = nil) {
        var properties: [String: Any] = ["trigger": trigger]
        if let isHighIntent { properties["is_high_intent"] = isHighIntent }
        if let selectedPlan { properties["selected_plan"] = selectedPlan }
        PostHogSDK.shared.capture("paywall.shown", properties: properties)
    }

    static func paywallPlanSelected(plan: String, productID: String, trigger: String, isHighIntent: Bool) {
        PostHogSDK.shared.capture("paywall.plan_selected", properties: [
            "plan": plan,
            "product_id": productID,
            "trigger": trigger,
            "is_high_intent": isHighIntent
        ])
    }

    static func paywallCTATapped(plan: String, productID: String, trigger: String, isHighIntent: Bool, isExitOffer: Bool) {
        PostHogSDK.shared.capture("paywall.cta_tapped", properties: paywallPurchaseProperties(
            productID: productID,
            plan: plan,
            trigger: trigger,
            isHighIntent: isHighIntent,
            isExitOffer: isExitOffer
        ))
    }

    static func paywallPurchaseStarted(plan: String, productID: String, trigger: String, isHighIntent: Bool, isExitOffer: Bool) {
        PostHogSDK.shared.capture("paywall.purchase_started", properties: paywallPurchaseProperties(
            productID: productID,
            plan: plan,
            trigger: trigger,
            isHighIntent: isHighIntent,
            isExitOffer: isExitOffer
        ))
    }

    static func paywallPurchaseCancelled(plan: String, productID: String, trigger: String, isHighIntent: Bool, isExitOffer: Bool) {
        PostHogSDK.shared.capture("paywall.purchase_cancelled", properties: paywallPurchaseProperties(
            productID: productID,
            plan: plan,
            trigger: trigger,
            isHighIntent: isHighIntent,
            isExitOffer: isExitOffer
        ))
    }

    static func paywallPurchasePending(plan: String, productID: String, trigger: String, isHighIntent: Bool, isExitOffer: Bool) {
        PostHogSDK.shared.capture("paywall.purchase_pending", properties: paywallPurchaseProperties(
            productID: productID,
            plan: plan,
            trigger: trigger,
            isHighIntent: isHighIntent,
            isExitOffer: isExitOffer
        ))
    }

    static func paywallPurchaseFailed(
        plan: String,
        productID: String,
        trigger: String,
        isHighIntent: Bool,
        isExitOffer: Bool,
        reason: String
    ) {
        PostHogSDK.shared.capture("paywall.purchase_failed", properties: paywallPurchaseProperties(
            productID: productID,
            plan: plan,
            trigger: trigger,
            isHighIntent: isHighIntent,
            isExitOffer: isExitOffer,
            errorReason: reason
        ))
    }

    static func paywallProductUnavailable(productID: String, trigger: String, isHighIntent: Bool, isExitOffer: Bool) {
        let plan = paywallPlanName(for: productID)
        PostHogSDK.shared.capture("paywall.product_unavailable", properties: paywallPurchaseProperties(
            productID: productID,
            plan: plan,
            trigger: trigger,
            isHighIntent: isHighIntent,
            isExitOffer: isExitOffer,
            errorReason: "product_not_loaded"
        ))
    }

    static func paywallRestoreTapped(trigger: String, isHighIntent: Bool) {
        PostHogSDK.shared.capture("paywall.restore_tapped", properties: [
            "trigger": trigger,
            "is_high_intent": isHighIntent
        ])
    }

    /// Offer/promo code sheet opened from the paywall (e.g. codes shared in
    /// social posts).
    static func paywallPromoCodeTapped(trigger: String, isHighIntent: Bool) {
        PostHogSDK.shared.capture("paywall.promo_code_tapped", properties: [
            "trigger": trigger,
            "is_high_intent": isHighIntent
        ])
    }

    /// A code redeemed through Apple's offer-code sheet granted Memo Pro.
    static func paywallPromoCodeRedeemed(trigger: String, isHighIntent: Bool) {
        PostHogSDK.shared.capture("paywall.promo_code_redeemed", properties: [
            "trigger": trigger,
            "is_high_intent": isHighIntent
        ])
    }

    static func paywallRestoreCompleted(trigger: String, isHighIntent: Bool, isProUser: Bool) {
        PostHogSDK.shared.capture("paywall.restore_completed", properties: [
            "trigger": trigger,
            "is_high_intent": isHighIntent,
            "is_pro_user": isProUser
        ])
        if isProUser {
            updateUserProperties(isProUser: true)
        }
    }

    static func paywallExitOfferProperties(
        trigger: String,
        selectedPlan: String,
        offerProductID: String,
        displayedPrice: Double,
        regularPrice: Double,
        discountLabel: String,
        displayedPriceText: String,
        regularPriceText: String
    ) -> [String: Any] {
        [
            "trigger": trigger,
            "selected_plan": selectedPlan,
            "offer_product_id": offerProductID,
            "displayed_price": displayedPrice,
            "regular_price": regularPrice,
            "discount_label": discountLabel,
            "displayed_price_text": displayedPriceText,
            "regular_price_text": regularPriceText,
            "is_exit_offer": true
        ]
    }

    static func paywallExitOfferShown(
        trigger: String,
        selectedPlan: String,
        offerProductID: String,
        displayedPrice: Double,
        regularPrice: Double,
        discountLabel: String,
        displayedPriceText: String,
        regularPriceText: String,
        reason: String? = nil
    ) {
        var props = paywallExitOfferProperties(
            trigger: trigger,
            selectedPlan: selectedPlan,
            offerProductID: offerProductID,
            displayedPrice: displayedPrice,
            regularPrice: regularPrice,
            discountLabel: discountLabel,
            displayedPriceText: displayedPriceText,
            regularPriceText: regularPriceText
        )
        // close_tapped or purchase_cancelled: which moment showed the one-time offer.
        if let reason { props["offer_reason"] = reason }
        PostHogSDK.shared.capture("paywall.exit_offer_shown", properties: props)
    }

    /// Someone should have seen the one-time offer and didn't (product not loaded, or no discount).
    static func paywallExitOfferUnavailable(trigger: String, reason: String, blocker: String, storefront: String?) {
        PostHogSDK.shared.capture("paywall.exit_offer_unavailable", properties: [
            "trigger": trigger,
            "offer_reason": reason,
            "blocker": blocker,
            "storefront": storefront ?? "unknown"
        ])
    }

    static func paywallExitOfferDeclined(trigger: String, isHighIntent: Bool) {
        PostHogSDK.shared.capture("paywall.exit_offer_declined", properties: ["trigger": trigger, "is_high_intent": isHighIntent])
    }

    static func paywallConverted(
        plan: String,
        price: Double? = nil,
        trigger: String = "unknown",
        productID: String? = nil,
        isHighIntent: Bool? = nil,
        isExitOffer: Bool = false
    ) {
        let resolvedProductID = productID ?? plan
        let properties = paywallPurchaseProperties(
            productID: resolvedProductID,
            plan: paywallPlanName(for: resolvedProductID, fallback: plan),
            trigger: trigger,
            isHighIntent: isHighIntent ?? false,
            isExitOffer: isExitOffer,
            price: price
        )
        PostHogSDK.shared.capture("paywall.converted", properties: properties)
        // Update pro status
        updateUserProperties(isProUser: true)
    }

    static func paywallDismissed(trigger: String = "unknown", selectedPlan: String? = nil, isHighIntent: Bool? = nil) {
        var properties: [String: Any] = ["trigger": trigger]
        if let selectedPlan { properties["selected_plan"] = selectedPlan }
        if let isHighIntent { properties["is_high_intent"] = isHighIntent }
        PostHogSDK.shared.capture("paywall.dismissed", properties: properties)
    }

    static func paywallPlanName(for productID: String, fallback: String = "unknown") -> String {
        switch productID {
        case "com.memori.ultra.annual", "com.memori.pro.annual":
            return "annual"
        case "com.memori.ultra.weekly", "com.memori.pro.weekly":
            return "weekly"
        case "com.memori.ultra.monthly", "com.memori.pro.monthly":
            return "monthly"
        case "com.memori.ultra.annual.firstyear":
            return "annual_founder"
        default:
            return fallback
        }
    }

    // MARK: - Sharing

    static func shareTapped(game: String) {
        PostHogSDK.shared.capture("share.tapped", properties: [
            "game": game
        ])
    }

    // MARK: - Engagement

    static func streakMilestone(streak: Int) {
        PostHogSDK.shared.capture("streak.milestone", properties: [
            "streak": streak
        ])
        updateUserProperties(streak: streak)
    }

    static func achievementUnlocked(achievement: String) {
        PostHogSDK.shared.capture("achievement.unlocked", properties: [
            "achievement": achievement
        ])
    }

    static func leaderboardViewed(category: String) {
        PostHogSDK.shared.capture("leaderboard.viewed", properties: [
            "category": category
        ])
    }

    // MARK: - Focus Mode

    static func focusModeEnabled() {
        PostHogSDK.shared.capture("focus_mode_enabled")
    }

    static func focusModeDisabled() {
        PostHogSDK.shared.capture("focus_mode_disabled")
    }

    // MARK: - Unlock loop (2.1.6)

    static func unlockSpin(result: String, attempt: Int) {
        PostHogSDK.shared.capture("unlock.spin", properties: ["result": result, "attempt": attempt])
    }

    static func unlockRunStarted(game: String) {
        PostHogSDK.shared.capture("unlock.run_started", properties: ["game": game])
    }

    static func unlockQualified(game: String, seconds: Int) {
        PostHogSDK.shared.capture("unlock.qualified", properties: ["game": game, "seconds": seconds])
    }

    static func unlockChoice(game: String, keepGoing: Bool) {
        PostHogSDK.shared.capture("unlock.choice", properties: ["game": game, "choice": keepGoing ? "keep_going" : "cash_out"])
    }

    static func unlockRunEnded(game: String, outcome: String, tier: Int, score: Int, minutes: Int, isPB: Bool) {
        PostHogSDK.shared.capture("unlock.run_ended", properties: [
            "game": game, "outcome": outcome, "tier": tier, "score": score, "minutes": minutes, "is_pb": isPB
        ])
    }

    static func unlockDenied(game: String, distance: Int) {
        PostHogSDK.shared.capture("unlock.denied", properties: ["game": game, "distance": distance])
    }

    static func unlockEscapeHatch() {
        PostHogSDK.shared.capture("unlock.escape_hatch")
    }

    static func unlockFreePass() {
        PostHogSDK.shared.capture("unlock.free_pass")
    }

    static func unlockPendingSpinResumed(game: String) {
        PostHogSDK.shared.capture("unlock.pending_spin_resumed", properties: ["game": game])
    }

    static func focusUnlockSlotShown() {
        PostHogSDK.shared.capture("focus_unlock_slot_shown")
    }

    static func focusUnlockSpinStarted() {
        PostHogSDK.shared.capture("focus_unlock_spin_started")
    }

    static func focusUnlockSpinLanded(gameType: String, payoutMinutes: Int) {
        PostHogSDK.shared.capture("focus_unlock_spin_landed", properties: [
            "game_type": gameType,
            "payout_minutes": payoutMinutes
        ])
    }

    static func focusUnlockGameStarted(gameType: String) {
        PostHogSDK.shared.capture("focus_unlock_game_started", properties: [
            "game_type": gameType
        ])
    }

    static func focusUnlockGameCompleted(gameType: String, score: Int) {
        PostHogSDK.shared.capture("focus_unlock_game_completed", properties: [
            "game_type": gameType,
            "score": score
        ])
    }

    static func focusUnlockGranted(durationMinutes: Int) {
        PostHogSDK.shared.capture("focus_unlock_granted", properties: [
            "duration_minutes": durationMinutes
        ])
    }

    static func focusSetupCompleted() {
        PostHogSDK.shared.capture("focus_setup_completed")
    }

    static func focusSetupSkipped() {
        PostHogSDK.shared.capture("focus_setup_skipped")
    }

    static func focusCooldownInitiated() {
        PostHogSDK.shared.capture("focus_cooldown_initiated")
    }
}

/// Answers to onboarding's "Where did you find Memo?" in the order they're shown.
/// Raw values are what PostHog and RevenueCat store, so keep them stable.
enum AcquisitionSource: String, CaseIterable, Identifiable {
    case tiktok
    case instagram
    case youtube
    case appStoreSearch = "app_store_search"
    case friend
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tiktok: return "TikTok"
        case .instagram: return "Instagram"
        case .youtube: return "YouTube"
        case .appStoreSearch: return "App Store search"
        case .friend: return "A friend"
        case .other: return "Other"
        }
    }
}
