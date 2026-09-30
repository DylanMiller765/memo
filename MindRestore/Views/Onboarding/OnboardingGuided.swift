import SwiftUI

// The guided route: arm B of the onboarding test. BePresent's order (the #2
// screen-time app) in Memo's hill look, with Memo's playable demo kept up front:
// age → screen time → the math → years lost → years back → Screen Time →
// notifications → this week's plan → first step done → the trial pages.

enum GuidedAgeBand: String, CaseIterable, Identifiable {
    case under18, from18, from25, from35, from45, over55

    var id: String { rawValue }

    var title: String {
        switch self {
        case .under18: return "Under 18"
        case .from18: return "18–24"
        case .from25: return "25–34"
        case .from35: return "35–44"
        case .from45: return "45–54"
        case .over55: return "55 or over"
        }
    }

    /// The age the lifetime math uses for this band.
    var age: Int {
        switch self {
        case .under18: return 16
        case .from18: return 21
        case .from25: return 29
        case .from35: return 40
        case .from45: return 50
        case .over55: return 60
        }
    }
}

enum GuidedScreenTime: String, CaseIterable, Identifiable {
    case under2, from2, from4, from6, over8

    var id: String { rawValue }

    var title: String {
        switch self {
        case .under2: return "Under 2 hours"
        case .from2: return "2–4 hours"
        case .from4: return "4–6 hours"
        case .from6: return "6–8 hours"
        case .over8: return "8+ hours"
        }
    }

    /// How the slot reel shows it.
    var reelLabel: String {
        switch self {
        case .under2: return "<2 HRS"
        case .from2: return "2–4 HRS"
        case .from4: return "4–6 HRS"
        case .from6: return "6–8 HRS"
        case .over8: return "8+ HRS"
        }
    }

    var hours: Double {
        switch self {
        case .under2: return 1.5
        case .from2: return 3
        case .from4: return 5
        case .from6: return 7
        case .over8: return 9
        }
    }
}

/// The two numbers the guided route shows, from the same math as the old life receipt.
struct GuidedLifeMath: Equatable {
    let age: Int
    let dailyHours: Double

    var yearsOnPhone: Int {
        max(1, Int(OnboardingLifetimeProjection(age: age, dailyScreenTimeHours: dailyHours).phoneYears.rounded()))
    }

    /// Half the scrolling back, which is what the plan promises to aim for.
    var yearsBack: Int { max(1, Int((Double(yearsOnPhone) / 2).rounded())) }

    var hoursBackPerDay: String {
        let half = dailyHours / 2
        return half >= 1 ? "\(Int(half.rounded(.down)))+ hours" : "\(Int((half * 60).rounded())) minutes"
    }
}

// MARK: - Shared pieces

/// A single-answer tile, the attribution page's style without the icon.
struct GuidedChoiceTile: View {
    let title: String
    let selected: Bool
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: compact ? 15 : 16, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? ClimbColor.ink : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: compact ? 48 : 54)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? Color.white : Color(red: 0.024, green: 0.118, blue: 0.149).opacity(0.86)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(ClimbColor.ink, lineWidth: 2.5))
                .background(RoundedRectangle(cornerRadius: 19.5, style: .continuous)
                    .strokeBorder(selected ? ClimbColor.mint : .white.opacity(0.85), lineWidth: selected ? 3 : 2)
                    .padding(-2))
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(ClimbColor.ink).offset(y: 4))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Memo on the hill asking the question in a speech bubble.
struct GuidedMemoAsks: View {
    let question: String
    var hint: String? = nil
    var compact = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(question)
                    .font(.brand(size: compact ? 22 : 25, weight: .heavy))
                    .foregroundStyle(ClimbColor.ink)
                if let hint {
                    Text(hint)
                        .font(.system(size: compact ? 12.5 : 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(ClimbColor.ink.opacity(0.6))
                }
            }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.vertical, compact ? 12 : 14)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(ClimbColor.ink, lineWidth: 3))
                .overlay(alignment: .bottom) {
                    GuidedBubbleTail()
                        .fill(.white)
                        .overlay(GuidedBubbleTail().stroke(ClimbColor.ink, lineWidth: 3))
                        .frame(width: 26, height: 16)
                        .offset(y: 14)
                        // Hide the bubble's outline where the tail joins it.
                        .overlay(alignment: .top) { Rectangle().fill(.white).frame(width: 20, height: 4).offset(y: -1.5) }
                }
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(ClimbColor.ink).offset(y: 5))
                .accessibilityAddTraits(.isHeader)
            ClimbMemo(mood: .neutral, size: compact ? 88 : 108)
                .padding(.top, compact ? 16 : 20)
        }
    }
}

private struct GuidedBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

/// A sticker in a white rounded badge: the page's picture when it isn't Memo.
struct GuidedStickerBadge: View {
    let kind: StickerKind
    var size: CGFloat = 64

    var body: some View {
        StickerIcon(kind: kind, size: size * 0.66)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(ClimbColor.ink, lineWidth: 2.5))
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(ClimbColor.ink).offset(y: 4))
            .accessibilityHidden(true)
    }
}

/// A big number on an outlined sticker (the years lost, the years back).
struct GuidedNumberSticker: View {
    let value: Int
    let unit: String
    let color: Color
    var textColor: Color = ClimbColor.ink
    var size: CGFloat = 96
    var animateFromZero = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(shown)")
                .font(.brand(size: size, weight: .heavy))
                .contentTransition(.numericText(value: Double(shown)))
                .monospacedDigit()
            Text(unit)
                .font(.brand(size: size * 0.34, weight: .heavy))
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 26)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(color))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(ClimbColor.ink, lineWidth: 3))
        .stickerOutline(3)
        .shadow(color: color.opacity(0.5), radius: 24)
        .rotationEffect(.degrees(-3))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(unit)")
        .onAppear {
            guard animateFromZero, !reduceMotion else { shown = value; return }
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.snappy(duration: 1.2)) { shown = value }
            }
        }
    }
}

private struct GuidedPage<Content: View, Bar: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @ViewBuilder let bar: () -> Bar

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < OBLayout.compactHeight
            VStack(spacing: 0) { content(compact) }
                .padding(.horizontal, OBLayout.gutter)
                .frame(maxWidth: OBLayout.contentMaxWidth + OBLayout.gutter * 2, maxHeight: .infinity)
                .frame(maxWidth: .infinity)
        }
        .obBottomBar { bar() }
        .preferredColorScheme(.dark)
    }
}

// MARK: - 1 · Age and 2 · Screen time

struct OnboardingGuidedChoicePage<Option: Identifiable & Equatable>: View {
    let title: String
    let detail: String
    var columns = 2
    let options: [Option]
    let label: (Option) -> String
    var initial: Option?
    let onPick: (Option) -> Void

    @State private var picked: Option?
    @State private var answered = false

    var body: some View {
        GuidedPage { compact in
            // A fixed top gap, not a centering spacer: Memo and the bubble sit at the same height on
            // every question page (and the hill stays put), whatever the answers below need.
            Spacer().frame(height: compact ? 6 : 52)
            GuidedMemoAsks(question: title, hint: detail, compact: compact)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: compact ? 10 : 12) {
                ForEach(options) { option in
                    GuidedChoiceTile(title: label(option), selected: picked == option, compact: compact) { pick(option) }
                }
            }
            .padding(.top, compact ? 16 : 24)
            Spacer(minLength: 0)
        } bar: {
            EmptyView()
        }
        .onAppear { if picked == nil { picked = initial } }
    }

    private func pick(_ option: Option) {
        guard !answered else { return }
        answered = true
        picked = option
        HapticService.tap()
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            onPick(option)
        }
    }
}

// MARK: - 3 · The math, as a slot machine

/// Red is the cost: the years the feed takes. Mint (years back) is the relief.
enum GuidedColor {
    static let loss = Color(red: 1.0, green: 0.30, blue: 0.34)        // #FF4D57
    static let lossDeep = Color(red: 0.62, green: 0.06, blue: 0.13)
    static let cream = Color(red: 0.99, green: 0.96, blue: 0.9)
}

enum GuidedSlotStyle: String { case cabinet, receipt }

/// Their answers lock in on three reels, then the machine pays out the years the
/// feed takes: the feed is a slot machine, and the house always wins.
struct OnboardingGuidedCalculatingPage: View {
    let math: GuidedLifeMath
    let screenTime: GuidedScreenTime
    let ageLabel: String
    var style: GuidedSlotStyle = .cabinet
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = 0 // reels locked so far; 4 = paid out
    @State private var spinning = false
    @State private var lever = false
    @State private var shake: CGFloat = 0
    @State private var flash = false
    @State private var printed: CGFloat = 0

    private var reels: [(label: String, final: String, filler: [String])] {
        [("A DAY", screenTime.reelLabel, ["1 HR", "8+ HRS", "3 HRS", "6 HRS", "<2 HRS", "5 HRS"]),
         ("YOUR AGE", ageLabel, ["16", "45", "30", "60", "25", "52"]),
         ("YEARS LEFT", "\(max(1, 80 - math.age))", ["12", "70", "38", "5", "44", "61"])]
    }

    private var paidOut: Bool { landed == 4 }

    var body: some View {
        GuidedPage { compact in
            Spacer(minLength: 0)
            ClimbHeadline(text: paidOut ? (style == .cabinet ? "The house always wins." : "The feed sent the bill.") : "Doing the math…",
                          size: compact ? 26 : 30)
                .animation(.easeInOut(duration: 0.25), value: paidOut)
            ClimbBodyText(text: paidOut ? "It pays out in years of your life." : "Your answers, spun into years.", size: compact ? 14 : 15)
                .padding(.top, 6)
            Group {
                switch style {
                case .cabinet: cabinet(compact: compact)
                case .receipt: receiptMachine(compact: compact)
                }
            }
            .padding(.top, compact ? 10 : 18)
            .modifier(GuidedShake(amount: shake))
            Spacer(minLength: 0)
        } bar: {
            EmptyView()
        }
        .task { await run() }
    }

    // MARK: Reels

    private func reelRow(height: CGFloat, labelColor: Color) -> some View {
        HStack(spacing: 8) {
            ForEach(reels.indices, id: \.self) { i in
                VStack(spacing: 6) {
                    GuidedReel(filler: reels[i].filler, final: reels[i].final, height: height,
                               spinning: spinning, landed: landed > i)
                    Text(reels[i].label)
                        .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(labelColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    // MARK: A · Cabinet

    private func cabinet(compact: Bool) -> some View {
        let reelHeight: CGFloat = compact ? 70 : 100
        let body = RoundedRectangle(cornerRadius: 30, style: .continuous)
        return ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Memo peeks over the sign.
                ClimbMemo(mood: paidOut ? .sad : .neutral, size: compact ? 84 : 112)
                    .padding(.bottom, -22)
                    .zIndex(0)
                GuidedMarqueeSign(text: "THE FEED", flash: flash, lit: spinning || paidOut)
                    .zIndex(2)
                    .padding(.bottom, -16)
                VStack(spacing: compact ? 12 : 16) {
                    reelRow(height: reelHeight, labelColor: GuidedColor.cream.opacity(0.85))
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.55)))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(ClimbColor.ink, lineWidth: 2.5))
                    payoutWindow(height: compact ? 64 : 88)
                }
                .padding(.horizontal, 16)
                .padding(.top, 30)
                .padding(.bottom, 18)
                .background(
                    body.fill(LinearGradient(colors: [Color(red: 0.86, green: 0.17, blue: 0.24), GuidedColor.lossDeep],
                                             startPoint: .top, endPoint: .bottom))
                )
                .overlay(body.stroke(Color.white.opacity(0.28), lineWidth: 1.5).padding(4))
                .overlay(body.strokeBorder(ClimbColor.ink, lineWidth: 3))
                .background(body.fill(ClimbColor.ink).offset(y: 6))
                .overlay(alignment: .trailing) { GuidedLever(pulled: lever).offset(x: 26, y: -10) }
                .zIndex(1)
            }
        }
        .padding(.trailing, 14) // room for the lever
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(paidOut ? "\(math.yearsOnPhone) years of your life go to your phone before 80" : "Doing the math")
    }

    private func payoutWindow(height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return ZStack {
            shape.fill(Color(red: 0.05, green: 0.02, blue: 0.04))
            if paidOut {
                Text("\(math.yearsOnPhone) YEARS")
                    .font(.brand(size: height * 0.5, weight: .heavy))
                    .foregroundStyle(GuidedColor.loss)
                    .shadow(color: GuidedColor.loss.opacity(0.9), radius: flash ? 14 : 6)
                    .transition(.scale(scale: 1.4).combined(with: .opacity))
            } else {
                Text(spinning ? "· · ·" : "PAYOUT")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(GuidedColor.loss.opacity(0.45))
            }
        }
        .frame(height: height)
        .overlay(shape.strokeBorder(paidOut ? GuidedColor.loss : ClimbColor.ink, lineWidth: paidOut ? 2.5 : 2.5))
        .overlay(alignment: .bottom) {
            Text("TO YOUR PHONE, BEFORE 80")
                .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                .tracking(1)
                .foregroundStyle(GuidedColor.loss.opacity(paidOut ? 0.9 : 0))
                .padding(.bottom, 5)
        }
    }

    // MARK: B · Receipt

    private func receiptMachine(compact: Bool) -> some View {
        let reelHeight: CGFloat = compact ? 70 : 100
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return VStack(spacing: 0) {
            ClimbMemo(mood: paidOut ? .sad : .neutral, size: compact ? 84 : 112)
                .padding(.bottom, -18)
            VStack(spacing: 14) {
                reelRow(height: reelHeight, labelColor: .white.opacity(0.6))
                // The printer slot the receipt comes out of.
                Capsule().fill(Color.black).frame(height: 8).padding(.horizontal, 24)
            }
            .padding(16)
            .background(shape.fill(Color(red: 0.1, green: 0.1, blue: 0.15)))
            .overlay(shape.strokeBorder(GuidedColor.loss.opacity(spinning || paidOut ? 0.9 : 0.35), lineWidth: 2.5))
            .shadow(color: GuidedColor.loss.opacity(spinning || paidOut ? 0.55 : 0), radius: 16)
            .overlay(shape.strokeBorder(ClimbColor.ink, lineWidth: 2.5).padding(-2))
            .zIndex(1)
            GuidedReceipt(math: math, screenTime: screenTime, large: !compact)
                .frame(maxWidth: compact ? 260 : 300)
                .frame(height: (compact ? 170 : 214) * printed, alignment: .bottom)
                .clipped()
                .padding(.top, -12)
                .zIndex(0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(paidOut ? "\(math.yearsOnPhone) years of your life go to your phone before 80" : "Doing the math")
    }

    // MARK: Run

    private func run() async {
        if reduceMotion {
            landed = 4
            printed = 1
            try? await Task.sleep(for: .milliseconds(2000))
            onDone()
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.easeIn(duration: 0.18)) { lever = true }
        HapticService.tap()
        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { lever = false }
        spinning = true
        SlotSound.tick()
        for i in 1...3 {
            try? await Task.sleep(for: .milliseconds(i == 1 ? 850 : 520))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { landed = i }
            SlotSound.lock()
            HapticService.tap()
        }
        try? await Task.sleep(for: .milliseconds(style == .cabinet ? 800 : 400))
        if style == .receipt {
            spinning = false
            for step in 1...6 {
                withAnimation(.linear(duration: 0.16)) { printed = CGFloat(step) / 6 }
                SlotSound.tick()
                try? await Task.sleep(for: .milliseconds(170))
            }
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { landed = 4 }
        spinning = false
        SlotSound.chime()
        HapticService.wrong()
        withAnimation(.linear(duration: 0.45)) { shake = 1 }
        for _ in 0..<3 {
            withAnimation(.easeInOut(duration: 0.16)) { flash = true }
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.easeInOut(duration: 0.16)) { flash = false }
            try? await Task.sleep(for: .milliseconds(180))
        }
        try? await Task.sleep(for: .milliseconds(1400))
        onDone()
    }
}

/// A short side-to-side jolt when the machine pays out.
private struct GuidedShake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(amount * .pi * 6) * 6 * (1 - amount), y: 0))
    }
}

/// "THE FEED" in lights, like the booth's marquee; the bulbs flash red on the payout.
private struct GuidedMarqueeSign: View {
    let text: String
    let flash: Bool
    let lit: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Text(text)
            .font(.brand(size: 27, weight: .heavy))
            .tracking(2)
            .foregroundStyle(lit ? GuidedColor.cream : GuidedColor.cream.opacity(0.6))
            .shadow(color: (flash ? GuidedColor.loss : ClimbColor.amber).opacity(lit ? 0.9 : 0), radius: 8)
            .padding(.horizontal, 26)
            .padding(.vertical, 10)
            .background(shape.fill(Color(red: 0.1, green: 0.04, blue: 0.08)))
            .overlay(
                shape.stroke(flash ? GuidedColor.loss : ClimbColor.amber,
                             style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [0.1, 10]))
                    .padding(5)
                    .shadow(color: (flash ? GuidedColor.loss : ClimbColor.amber).opacity(0.8), radius: 4)
                    .opacity(lit ? 1 : 0.4)
            )
            .overlay(shape.strokeBorder(ClimbColor.ink, lineWidth: 3))
            .background(shape.fill(ClimbColor.ink).offset(y: 4))
    }
}

/// The slot's pull handle: a rod and a red ball that dips when pulled.
private struct GuidedLever: View {
    let pulled: Bool

    var body: some View {
        VStack(spacing: -2) {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.55, blue: 0.55), GuidedColor.loss, GuidedColor.lossDeep],
                                     center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: 16))
                .overlay(Circle().strokeBorder(ClimbColor.ink, lineWidth: 2.5))
                .frame(width: 26, height: 26)
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.55)], startPoint: .leading, endPoint: .trailing))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(ClimbColor.ink, lineWidth: 2))
                .frame(width: 9, height: pulled ? 30 : 64)
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(white: 0.4))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(ClimbColor.ink, lineWidth: 2))
                .frame(width: 18, height: 26)
        }
        .frame(height: 118, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// The feed's bill, printed in red: their answers and the total in years.
private struct GuidedReceipt: View {
    let math: GuidedLifeMath
    let screenTime: GuidedScreenTime
    var large = true

    var body: some View {
        VStack(spacing: 7) {
            Text("THE FEED · RECEIPT")
                .font(.system(size: large ? 13 : 11, weight: .heavy, design: .monospaced))
                .tracking(1.5)
            line("Daily scrolling", screenTime.title.lowercased())
            line("Years ahead", "\(max(1, 80 - math.age))")
            Rectangle().fill(GuidedColor.lossDeep.opacity(0.5)).frame(height: 1)
                .mask(HStack(spacing: 3) { ForEach(0..<40, id: \.self) { _ in Rectangle().frame(width: 3) } })
            HStack(alignment: .firstTextBaseline) {
                Text("TOTAL").font(.system(size: large ? 15 : 13, weight: .heavy, design: .monospaced))
                Spacer()
                Text("\(math.yearsOnPhone) YEARS").font(.brand(size: large ? 32 : 26, weight: .heavy))
            }
            Text("of your life, before 80. No refunds.")
                .font(.system(size: large ? 12.5 : 11, weight: .semibold, design: .monospaced))
                .opacity(0.8)
        }
        .foregroundStyle(GuidedColor.lossDeep)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(GuidedColor.cream)
        .overlay(alignment: .bottom) { GuidedZigzag().fill(Color(red: 0.07, green: 0.1, blue: 0.14)).frame(height: 6) }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).fontWeight(.heavy)
        }
        .font(.system(size: large ? 14 : 12.5, weight: .semibold, design: .monospaced))
    }
}

/// The torn bottom edge of a receipt.
private struct GuidedZigzag: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let teeth = 18
        let w = rect.width / CGFloat(teeth)
        p.move(to: CGPoint(x: 0, y: rect.maxY))
        for i in 0..<teeth {
            p.addLine(to: CGPoint(x: CGFloat(i) * w + w / 2, y: rect.minY))
            p.addLine(to: CGPoint(x: CGFloat(i + 1) * w, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}

/// One reel: a cream strip rolling while it spins, snapping to its value when it lands.
private struct GuidedReel: View {
    let filler: [String]
    let final: String
    let height: CGFloat
    let spinning: Bool
    let landed: Bool

    private var font: Font { .brand(size: height * 0.3, weight: .heavy) }

    var body: some View {
        let window = RoundedRectangle(cornerRadius: 10, style: .continuous)
        ZStack {
            window.fill(GuidedColor.cream)
            if landed || !spinning {
                Text(landed ? final : "?")
                    .font(font)
                    .foregroundStyle(landed ? ClimbColor.ink : ClimbColor.ink.opacity(0.3))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .padding(.horizontal, 6)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            } else {
                // TimelineView keeps the strip rolling without a state change every frame.
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate * 11
                    let index = Int(t) % filler.count
                    let frac = CGFloat(t - floor(t))
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { k in
                            Text(filler[(index + k) % filler.count])
                                .font(font)
                                .foregroundStyle(ClimbColor.ink.opacity(0.7))
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                                .frame(height: height * 0.62)
                        }
                    }
                    .offset(y: -frac * height * 0.62)
                    .blur(radius: 1.4)
                }
                .frame(height: height, alignment: .top)
                .clipped()
            }
            // Curved-drum shading, top and bottom.
            LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .clear, location: 0.3),
                                   .init(color: .clear, location: 0.7), .init(color: .black.opacity(0.35), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(window)
        .overlay(window.strokeBorder(landed ? ClimbColor.amber : ClimbColor.ink, lineWidth: landed ? 3 : 2))
    }
}

// MARK: - 4 · Years lost

enum GuidedShockStyle: String { case number, grid }

struct OnboardingGuidedShockPage: View {
    let math: GuidedLifeMath
    var style: GuidedShockStyle = .number
    let onContinue: () -> Void

    var body: some View {
        GuidedPage { compact in
            switch style {
            case .number: numberLayout(compact: compact)
            case .grid: gridLayout(compact: compact)
            }
        } bar: {
            OBActionBar(title: "Show me the way back", action: onContinue)
        }
        .climbSky(.night)
    }

    @ViewBuilder
    private func numberLayout(compact: Bool) -> some View {
        Spacer(minLength: 0)
        ClimbMemo(mood: .sad, size: compact ? 96 : 124)
        ClimbHeadline(text: "At this rate, your phone takes", size: compact ? 26 : 30)
            .padding(.top, compact ? 10 : 16)
        GuidedNumberSticker(value: math.yearsOnPhone, unit: "years", color: GuidedColor.loss, textColor: .white, size: compact ? 78 : 96)
            .background(
                // A red glow behind the number: the one screen where the cost sinks in.
                RadialGradient(colors: [GuidedColor.loss.opacity(0.45), .clear], center: .center, startRadius: 10, endRadius: 190)
                    .frame(width: 420, height: 320)
                    .allowsHitTesting(false)
            )
            .padding(.vertical, compact ? 14 : 20)
        ClimbBodyText(text: "of your life before you turn 80.", size: compact ? 16 : 18)
        Spacer(minLength: 0)
    }

    @ViewBuilder
    private func gridLayout(compact: Bool) -> some View {
        Spacer(minLength: 0)
        ClimbHeadline(text: "\(math.yearsOnPhone) years of your life,\non your phone.", size: compact ? 26 : 30)
        ClimbBodyText(text: "Each square is a year. Here's what the feed takes before you turn 80.", size: compact ? 14 : 15)
            .padding(.top, 6)
        GuidedLifeGrid(math: math, compact: compact)
            .padding(.top, compact ? 14 : 20)
        Spacer(minLength: 0)
    }
}

/// 80 years as squares: lived, the phone's (filling in amber), and yours.
struct GuidedLifeGrid: View {
    let math: GuidedLifeMath
    var compact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = 0

    private let columns = 10

    var body: some View {
        let lived = min(math.age, 79)
        let phone = min(math.yearsOnPhone, 80 - lived)
        ClimbCard(padding: compact ? 12 : 16) {
            VStack(spacing: compact ? 10 : 14) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: compact ? 5 : 6), count: columns), spacing: compact ? 5 : 6) {
                    ForEach(0..<80, id: \.self) { year in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(color(year: year, lived: lived, phone: phone))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                HStack(spacing: 14) {
                    legend(.white.opacity(0.28), "Lived")
                    legend(ClimbColor.amber, "Phone")
                    legend(ClimbColor.mint.opacity(0.9), "Yours")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(phone) of your remaining years go to your phone")
        .task {
            if reduceMotion { filled = phone; return }
            try? await Task.sleep(for: .milliseconds(400))
            for i in 1...max(phone, 1) {
                withAnimation(.easeOut(duration: 0.12)) { filled = i }
                try? await Task.sleep(for: .milliseconds(max(25, 900 / max(phone, 1))))
            }
        }
    }

    private func color(year: Int, lived: Int, phone: Int) -> Color {
        if year < lived { return .white.opacity(0.28) }
        // The phone's years sit at the end of the life: the ones you don't get back.
        if year >= 80 - phone { return (80 - year) <= filled ? ClimbColor.amber : .white.opacity(0.1) }
        return ClimbColor.mint.opacity(0.9)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(text).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.8))
        }
    }
}

// MARK: - 5 · Years back

struct OnboardingGuidedYearsBackPage: View {
    let math: GuidedLifeMath
    let onContinue: () -> Void

    var body: some View {
        GuidedPage { compact in
            Spacer(minLength: 0)
            ClimbHeadline(text: "Good news: Memo can\nwin you back", size: compact ? 26 : 30)
            GuidedNumberSticker(value: math.yearsBack, unit: "years", color: ClimbColor.mint, size: compact ? 78 : 96)
                .padding(.vertical, compact ? 14 : 20)
            ClimbBodyText(text: "Cut your scrolling in half and that's \(math.yearsBack) years back for friends, school and sleep.", size: compact ? 15 : 16)
            ClimbMemo(mood: .happy, size: compact ? 96 : 124)
                .padding(.top, compact ? 10 : 18)
            Spacer(minLength: 0)
        } bar: {
            OBActionBar(title: "Get those years back", action: onContinue)
        }
        .climbSky(.sunrise)
    }
}

// MARK: - 6 · Screen Time permission

enum GuidedPermissionStyle: String { case alert, card }

struct OnboardingGuidedScreenTimePage: View {
    var style: GuidedPermissionStyle = .alert
    let onContinue: () -> Void

    var body: some View {
        GuidedPage { compact in
            Spacer(minLength: 0)
            switch style {
            case .alert: alertLayout(compact: compact)
            case .card: cardLayout(compact: compact)
            }
            Spacer(minLength: 0)
        } bar: {
            OBActionBar(title: "Connect Screen Time", footnote: "Memo needs this to lock your apps.", action: onContinue)
        }
    }

    @ViewBuilder
    private func alertLayout(compact: Bool) -> some View {
        ClimbMemo(mood: .neutral, size: compact ? 76 : 100)
            .padding(.bottom, compact ? 8 : 12)
        ClimbHeadline(text: "Connect Memo to\nScreen Time", size: compact ? 26 : 30)
        ClimbBodyText(text: "Your data is private and never leaves your phone.", size: compact ? 14 : 15)
            .padding(.top, 6)
        // What iOS 26 is about to show (glass card, two pill buttons), so the real prompt isn't a surprise.
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("“Memo” Would Like to Access Screen Time")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                Text("Providing “Memo” access to Screen Time may allow it to see your activity data, restrict content, and limit the usage of apps and websites.")
                    .font(.system(size: 14))
                    .foregroundStyle(.black.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                Text("Continue")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(Color.black.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(ClimbColor.mint, lineWidth: 3).padding(-4))
                Text("Don't Allow")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(Color(red: 0.0, green: 0.48, blue: 1.0)))
            }
        }
        .padding(18)
        // Outline the card's shape only; outlining the whole view would rim the text too.
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color(white: 0.96)).stickerOutline(2.5))
        .frame(maxWidth: 310)
        .padding(.top, compact ? 18 : 28)
        .accessibilityHidden(true)
        HStack(spacing: 6) {
            Image(systemName: "arrow.up").font(.system(size: 18, weight: .black))
            Text("Tap Continue").font(.system(size: 16, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(ClimbColor.mint)
        .offset(x: -72)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func cardLayout(compact: Bool) -> some View {
        ClimbMemo(mood: .neutral, size: compact ? 90 : 112)
        ClimbHeadline(text: "Let Memo guard\nyour apps", size: compact ? 26 : 30)
            .padding(.top, compact ? 10 : 16)
        ClimbCard {
            VStack(alignment: .leading, spacing: 14) {
                row(.padlock, "Locks the apps you pick", "Until you play a quick game.")
                row(.chart, "Counts your real screen time", "So your years-back number is true.")
                row(.house, "Stays on your phone", "Apple keeps it private. Memo never sees your activity.")
            }
        }
        .padding(.top, compact ? 16 : 22)
    }

    private func row(_ kind: StickerKind, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            StickerIcon(kind: kind, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text(detail).font(.system(size: 13.5, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 7 · Notifications

struct OnboardingGuidedNotificationsPage: View {
    let onEnable: () -> Void
    let onLater: () -> Void

    var body: some View {
        GuidedPage { compact in
            Spacer(minLength: 0)
            ClimbHeadline(text: "Let Memo tap you\non the shoulder", size: compact ? 26 : 30)
            ClimbBodyText(text: "A nudge when your unlock time runs out, and when your streak needs you.", size: compact ? 14 : 15)
                .padding(.top, 6)
            VStack(spacing: 10) {
                banner(title: "Memo", text: "Your 10 minutes of TikTok are up. Back to your day?", time: "now")
                banner(title: "Memo", text: "Your 4-day streak ends at midnight. One quick game keeps it.", time: "8:02 PM")
                    .opacity(0.8)
            }
            .padding(.top, compact ? 24 : 28)
            ClimbMemo(mood: .happy, size: compact ? 86 : 108)
                .padding(.top, compact ? 12 : 22)
            Spacer(minLength: 0)
        } bar: {
            VStack(spacing: 4) {
                OBActionBar(title: "Turn on notifications", action: onEnable)
                Button("Maybe later", action: onLater)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(minHeight: 36)
                    .padding(.bottom, 4)
            }
        }
    }

    private func banner(title: String, text: String, time: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image("app-icon")
                .resizable()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(time).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                }
                Text(text).font(.system(size: 13.5)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 8 · This week's plan

struct OnboardingGuidedPlanPage: View {
    let math: GuidedLifeMath
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    private var items: [(StickerKind, String, String)] {
        [(.clock, "Win back \(math.hoursBackPerDay) a day", "Half your scrolling, one blocked app at a time."),
         (.dumbbell, "Train on every unlock", "A 30-second game each time you open a blocked app."),
         (.trophy, "Save \(math.yearsBack) years of your life", "For friends, school and sleep.")]
    }

    var body: some View {
        GuidedPage { compact in
            Spacer(minLength: 0)
            ClimbMemo(mood: .happy, size: compact ? 90 : 112)
            ClimbHeadline(text: "This week, Memo\nwill help you:", size: compact ? 26 : 30)
                .padding(.top, compact ? 10 : 16)
            VStack(spacing: compact ? 10 : 12) {
                ForEach(items.indices, id: \.self) { i in
                    ClimbCard(padding: 14) {
                        HStack(spacing: 12) {
                            StickerIcon(kind: items[i].0, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(items[i].1).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                                Text(items[i].2).font(.system(size: 13.5, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.7))
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(ClimbColor.mint)
                        }
                    }
                    .opacity(i < shown ? 1 : 0)
                    .offset(y: i < shown ? 0 : 12)
                }
            }
            .padding(.top, compact ? 16 : 22)
            Spacer(minLength: 0)
        } bar: {
            OBActionBar(title: "Let's go", action: onContinue)
        }
        .climbSky(.predawn)
        .task {
            for i in 1...3 {
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 280))
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { shown = i }
            }
        }
    }
}

// MARK: - 9 · First step done

struct OnboardingGuidedCongratsPage: View {
    let onContinue: () -> Void
    @State private var sparks = false

    var body: some View {
        GuidedPage { compact in
            Spacer(minLength: 0)
            ZStack {
                OnboardingSparkBurst(active: sparks, radius: compact ? 110 : 140)
                ClimbMemo(mood: .happy, size: compact ? 130 : 164)
                ConfettiView()
            }
            ClimbHeadline(text: "First step done.", size: compact ? 30 : 36)
                .padding(.top, compact ? 12 : 20)
            ClimbBodyText(text: "Most people never look at the number. You just did something about it.", size: compact ? 15 : 16)
                .padding(.top, 8)
            Spacer(minLength: 0)
        } bar: {
            OBActionBar(title: "Continue", action: onContinue)
        }
        .climbSky(.sunrise)
        .onAppear {
            sparks = true
            HapticService.complete()
        }
    }
}
