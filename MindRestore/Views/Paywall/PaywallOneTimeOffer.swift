import SwiftUI

/// Shown once, the first time someone closes the paywall: the yearly plan at the
/// one-time price. The free-trial line appears only when StoreKit says this account
/// can get one, so the screen never promises a trial the payment sheet won't honor.
struct PaywallOneTimeOffer: View {
    enum Style: String { case sheet, fullScreen }

    let style: Style
    let priceText: String
    let regularPriceText: String
    let weeklyText: String
    let discountPercent: Int
    let trialLabel: String?
    let isBusy: Bool
    let onClaim: () -> Void
    let onDecline: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    static var debugStyle: Style {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--one-time-offer-style"), args.indices.contains(i + 1),
           let style = Style(rawValue: args[i + 1]) { return style }
        #endif
        return .sheet
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(style == .sheet ? 0.6 : 0.0)
                .ignoresSafeArea()
                .onTapGesture {} // keep taps off the paywall underneath
            switch style {
            case .sheet: sheet
            case .fullScreen: fullScreen
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.82)) { shown = true }
            HapticService.complete()
        }
    }

    // MARK: Pieces

    private var ticket: some View {
        ClimbPassSticker(title: "\(discountPercent)% OFF", width: 230)
            .rotationEffect(.degrees(-3))
            .scaleEffect(shown ? 1 : 0.6)
            .opacity(shown ? 1 : 0)
    }

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 11, weight: .black))
            Text("EXCLUSIVE · ONE-TIME OFFER")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .tracking(1.2)
        }
        .foregroundStyle(ClimbColor.amber)
    }

    private var priceLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(regularPriceText)
                .strikethrough(true, color: .white.opacity(0.6))
                .foregroundStyle(.white.opacity(0.55))
            Text("\(priceText)/year")
                .foregroundStyle(.white)
        }
        .font(.system(size: 20, weight: .heavy, design: .rounded))
    }

    private var terms: String {
        if let trialLabel {
            return "\(trialLabel.capitalizedFirst) free, then \(priceText)/year. Cancel anytime."
        }
        return "\(priceText) today, then yearly. Cancel anytime."
    }

    private var buttons: some View {
        VStack(spacing: 6) {
            ChunkyButton(title: trialLabel == nil ? "Claim my offer" : "Start my free \(trialLabel!)", systemImage: nil, style: .amber, action: onClaim)
                .disabled(isBusy)
                .opacity(isBusy ? 0.6 : 1)
            Button("No thanks", action: onDecline)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .frame(minWidth: 120, minHeight: 40)
                .disabled(isBusy)
        }
    }

    private var copy: some View {
        VStack(spacing: 10) {
            eyebrow
            Text("Memo Pro, \(discountPercent)% off.\nJust this once.")
                .font(.brand(size: 28, weight: .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            priceLine
            Text("That's \(weeklyText). \(terms)")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("You won't see this price again after you leave.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(ClimbColor.amber.opacity(0.85))
        }
    }

    // MARK: A · Sheet over the paywall

    private var sheet: some View {
        VStack(spacing: 18) {
            ticket.padding(.top, -64)
            copy
            buttons
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                .fill(Color(red: 0.07, green: 0.08, blue: 0.16))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                        .strokeBorder(ClimbColor.amber.opacity(0.55), lineWidth: 1.5)
                )
                .ignoresSafeArea(edges: .bottom)
        )
        .offset(y: shown ? 0 : 500)
    }

    // MARK: B · Full screen

    private var fullScreen: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.1, green: 0.07, blue: 0.2), Color(red: 0.03, green: 0.04, blue: 0.1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            RadialGradient(colors: [ClimbColor.amber.opacity(0.28), .clear], center: .init(x: 0.5, y: 0.3), startRadius: 10, endRadius: 320)
                .ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer(minLength: 0)
                ClimbMemo(mood: .happy, size: 120)
                    .padding(.bottom, -30)
                ticket
                copy
                Spacer(minLength: 0)
                buttons
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .opacity(shown ? 1 : 0)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
