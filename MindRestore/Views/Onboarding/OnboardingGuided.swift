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
    var compact = false

    var body: some View {
        VStack(spacing: 0) {
            Text(question)
                .font(.brand(size: compact ? 22 : 25, weight: .heavy))
                .foregroundStyle(ClimbColor.ink)
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
        .foregroundStyle(ClimbColor.ink)
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
            Spacer(minLength: 0)
            GuidedMemoAsks(question: title, compact: compact)
            ClimbBodyText(text: detail, size: compact ? 13 : 14)
                .padding(.top, compact ? 14 : 10)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: compact ? 10 : 12) {
                ForEach(options) { option in
                    GuidedChoiceTile(title: label(option), selected: picked == option, compact: compact) { pick(option) }
                }
            }
            .padding(.top, compact ? 14 : 20)
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

/// Their answers lock in on three reels, then the big reel lands on the years
/// the feed takes: the feed is a slot machine, and the house always wins.
struct OnboardingGuidedCalculatingPage: View {
    let math: GuidedLifeMath
    let screenTime: GuidedScreenTime
    let ageLabel: String
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = 0 // reels locked so far (4 = the years)
    @State private var spinning = false
    @State private var thud = false

    private var reels: [(label: String, final: String, filler: [String])] {
        [("A DAY", screenTime.reelLabel, ["1 HR", "8+ HRS", "3 HRS", "6 HRS", "<2 HRS", "5 HRS"]),
         ("YOUR AGE", ageLabel, ["16", "45", "30", "60", "25", "52"]),
         ("YEARS LEFT", "\(max(1, 80 - math.age))", ["12", "70", "38", "5", "44", "61"])]
    }

    var body: some View {
        GuidedPage { compact in
            Spacer(minLength: 0)
            ClimbHeadline(text: landed == 4 ? "The house always wins." : "Doing the math…", size: compact ? 26 : 30)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: landed == 4)
            ClimbBodyText(text: landed == 4 ? "Your feed pays out in years of your life." : "Your answers, spun into years.", size: compact ? 14 : 15)
                .padding(.top, 6)
                .contentTransition(.opacity)
            ClimbMemo(mood: landed == 4 ? .sad : .neutral, size: compact ? 90 : 120)
                .padding(.top, compact ? 8 : 14)
                .padding(.bottom, -10)
                .zIndex(0)
            machine(compact: compact)
                .zIndex(1)
            Spacer(minLength: 0)
        } bar: {
            EmptyView()
        }
        .task { await run() }
    }

    private func machine(compact: Bool) -> some View {
        let rowHeight: CGFloat = compact ? 44 : 58
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return VStack(spacing: compact ? 10 : 14) {
            HStack(spacing: 8) {
                ForEach(reels.indices, id: \.self) { i in
                    VStack(spacing: 6) {
                        GuidedReel(filler: reels[i].filler, final: reels[i].final, rowHeight: rowHeight,
                                   spinning: spinning, landed: landed > i, reduceMotion: reduceMotion)
                        Text(reels[i].label)
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(landed > i ? ClimbColor.amber : .white.opacity(0.5))
                    }
                }
            }
            GuidedReel(filler: ["2 YEARS", "31 YEARS", "9 YEARS", "20 YEARS", "5 YEARS", "26 YEARS"],
                       final: "\(math.yearsOnPhone) YEARS", rowHeight: rowHeight * 1.35,
                       spinning: spinning, landed: landed == 4, reduceMotion: reduceMotion, jackpot: true)
                .scaleEffect(thud ? 1.06 : 1)
            Text(landed == 4 ? "TO YOUR PHONE, BEFORE 80" : "THE FEED'S CUT")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .tracking(1)
                .foregroundStyle(landed == 4 ? ClimbColor.amber : .white.opacity(0.5))
        }
        .padding(compact ? 14 : 18)
        .background(shape.fill(Color(red: 0.07, green: 0.07, blue: 0.13)))
        .overlay(
            shape.stroke(ClimbColor.amber, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.1, 12]))
                .padding(5)
                .shadow(color: ClimbColor.amber.opacity(0.6), radius: 4)
        )
        .overlay(shape.strokeBorder(ClimbColor.ink, lineWidth: 2.5))
        .background(shape.fill(ClimbColor.ink).offset(y: 5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(landed == 4 ? "\(math.yearsOnPhone) years of your life go to your phone before 80" : "Doing the math")
    }

    private func run() async {
        if reduceMotion {
            landed = 4
            try? await Task.sleep(for: .milliseconds(1800))
            onDone()
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        spinning = true
        SlotSound.tick()
        for i in 1...3 {
            try? await Task.sleep(for: .milliseconds(i == 1 ? 900 : 550))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { landed = i }
            SlotSound.lock()
            HapticService.tap()
        }
        try? await Task.sleep(for: .milliseconds(900))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { landed = 4; thud = true }
        SlotSound.chime()
        HapticService.complete()
        try? await Task.sleep(for: .milliseconds(220))
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { thud = false }
        try? await Task.sleep(for: .milliseconds(1900))
        onDone()
    }
}

/// One reel: a blurred strip rolling while spinning, snapping to its value when it lands.
private struct GuidedReel: View {
    let filler: [String]
    let final: String
    let rowHeight: CGFloat
    let spinning: Bool
    let landed: Bool
    let reduceMotion: Bool
    var jackpot = false

    var body: some View {
        let window = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack {
            window.fill(landed && jackpot ? ClimbColor.amber : Color.white.opacity(0.07))
            if landed || !spinning {
                Text(landed ? final : "?")
                    .font(.brand(size: jackpot ? rowHeight * 0.5 : rowHeight * 0.4, weight: .heavy))
                    .foregroundStyle(landed && jackpot ? ClimbColor.ink : (landed ? .white : .white.opacity(0.35)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 6)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            } else {
                // TimelineView keeps the roll moving without a state change every frame.
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate * (jackpot ? 9 : 11)
                    let index = Int(t) % filler.count
                    let frac = CGFloat(t - floor(t))
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { k in
                            Text(filler[(index + k) % filler.count])
                                .font(.brand(size: jackpot ? rowHeight * 0.5 : rowHeight * 0.4, weight: .heavy))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(height: rowHeight)
                        }
                    }
                    .offset(y: -frac * rowHeight)
                    .blur(radius: 1.2)
                }
                .frame(height: rowHeight, alignment: .top)
                .clipped()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
        .clipShape(window)
        .overlay(window.strokeBorder(landed ? ClimbColor.amber : Color.white.opacity(0.12), lineWidth: landed ? 2.5 : 1))
        .shadow(color: landed && jackpot ? ClimbColor.amber.opacity(0.7) : .clear, radius: 18)
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
        GuidedNumberSticker(value: math.yearsOnPhone, unit: "years", color: ClimbColor.amber, size: compact ? 78 : 96)
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
            ClimbHeadline(text: "The good news: Memo can\nwin you back", size: compact ? 26 : 30)
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
         (.dumbbell, "Train your memory every unlock", "A 30-second game each time you open a blocked app."),
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

    var body: some View {
        GuidedPage { compact in
            Spacer(minLength: 0)
            ZStack {
                OnboardingSparkBurst(active: true, radius: compact ? 110 : 140)
                ClimbMemo(mood: .happy, size: compact ? 130 : 164)
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
    }
}
