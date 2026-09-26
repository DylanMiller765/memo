import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreService.self) private var storeService
    @Environment(GameCenterService.self) private var gameCenterService
    @Query private var users: [User]
    @Query(sort: \DailySession.date, order: .reverse) private var sessions: [DailySession]

    @State private var showingSettings = false
    @State private var globalRank: Int?

    private var user: User? { users.first }
    private var isProUser: Bool { storeService.isProUser }

    private static let ink = Color(red: 0.043, green: 0.106, blue: 0.133)          // #0B1B22
    private static let mint = Color(red: 0.482, green: 0.89, blue: 0.776)          // #7BE3C6
    private static let tileFill = Color(red: 0, green: 0.086, blue: 0.11).opacity(0.42)
    private static let cardShape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    /// Hill crest below the safe area: under Memo's feet (header ≈ 54 + Memo 180 − a little).
    private static let hillCrest: CGFloat = 226

    private var profileMascotMood: MascotRiveMood {
        guard let lastSession = user?.lastSessionDate else { return .neutral }
        if Calendar.current.isDateInToday(lastSession) {
            return .happy
        } else if Calendar.current.isDateInYesterday(lastSession) {
            return .neutral
        } else {
            return .sad
        }
    }

    private var displayName: String {
        guard let name = user?.username, !name.isEmpty else { return "Player" }
        return name
    }

    var body: some View {
        // The tab bar tints labels mint; this tab's own controls keep the app accent.
        tabContent
            .tint(AppColors.accent)
    }

    private var tabContent: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .staggered(index: 0)

                    memo
                        .staggered(index: 1)

                    identity
                        .padding(.top, 4)
                        .staggered(index: 1)

                    statTiles
                        .padding(.horizontal, 20)
                        .padding(.top, 22)
                        .staggered(index: 2)

                    streakWeek
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .staggered(index: 3)

                    settingsRow
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .staggered(index: 4)
                }
                .padding(.bottom, 120)
                .responsiveContent()
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(alignment: .top) {
                HomeHillScene(tier: .calm, crestFromSafeTop: Self.hillCrest)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .task {
                await loadGlobalRank()
            }
        }
    }

    // MARK: - Data Loading

    private func loadGlobalRank() async {
        globalRank = await gameCenterService.bestWeeklyRank()
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Profile")
                .font(.brand(size: 30, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                HapticService.tap()
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Self.ink)
                    .frame(width: 42, height: 42)
                    .background(.white, in: Circle())
                    .overlay(Circle().strokeBorder(Self.ink, lineWidth: 2.5))
                    .background(Circle().fill(Self.ink).offset(y: 3))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    // MARK: - Memo + identity

    private var memo: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Color.black.opacity(0.45))
                .frame(width: 120, height: 20)
                .blur(radius: 4)
                .offset(y: -4)
            RiveMascotView(mood: profileMascotMood, size: 200, playbackPolicy: .continuous)
                .frame(height: 180)
                .accessibilityLabel("Memo")
        }
        .frame(maxWidth: .infinity)
    }

    private var identity: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                OutlinedText(text: displayName, size: 32, outline: 2.5)
                if isProUser {
                    Text("PRO")
                        .font(.brand(size: 11, weight: .heavy))
                        .foregroundStyle(Self.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Self.mint, in: Capsule())
                        .overlay(Capsule().strokeBorder(Self.ink, lineWidth: 1.5))
                }
            }
            if let user {
                Text("Joined \(user.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))")
                    .font(.brand(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .shadow(color: .black.opacity(0.4), radius: 4)
            }
        }
    }

    // MARK: - Stats

    private var statTiles: some View {
        HStack(spacing: 10) {
            statTile(.flame, value: "\(user?.currentStreak ?? 0)", label: "Day streak")
            statTile(.padlock, value: "\(user?.resistedCount ?? 0)", label: "Resisted")
            statTile(.trophy, value: globalRank.map { "#\($0)" } ?? "—", label: "This week")
        }
    }

    private func statTile(_ kind: StickerKind, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            StickerIcon(kind: kind, size: 40)
            Text(value)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Self.tileFill, in: Self.cardShape)
        .overlay(Self.cardShape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Streak week

    private var weekDays: [(letter: String, trained: Bool, isToday: Bool)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let trainedDays = Set(sessions.map { calendar.startOfDay(for: $0.date) })
        return (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return (date.formatted(.dateTime.weekday(.narrow)), trainedDays.contains(date), offset == 0)
        }
    }

    private var streakWeek: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .font(.brand(size: 17, weight: .heavy))
                    .foregroundStyle(.white)
                Spacer()
                Text("Best: \(user?.longestStreak ?? 0) days")
                    .font(.brand(size: 13, weight: .bold))
                    .foregroundStyle(Self.mint)
            }
            HStack(spacing: 0) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 6) {
                        StickerIcon(kind: .flame, size: 30, muted: !day.trained)
                            .opacity(day.trained ? 1 : 0.7)
                        Text(day.letter)
                            .font(.brand(size: 12, weight: .heavy))
                            .foregroundStyle(day.isToday ? Self.ink : .white.opacity(0.75))
                            .frame(width: 24, height: 20)
                            .background {
                                if day.isToday {
                                    Capsule().fill(.white)
                                        .overlay(Capsule().strokeBorder(Self.ink, lineWidth: 1.5))
                                }
                            }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.letter), \(day.trained ? "trained" : "no training")\(day.isToday ? ", today" : "")")
                }
            }
            if user?.isStreakActive != true {
                Text("Play a game today to keep your streak.")
                    .font(.brand(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(16)
        .background(Self.tileFill, in: Self.cardShape)
        .overlay(Self.cardShape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
    }

    // MARK: - Settings

    private var settingsRow: some View {
        Button {
            showingSettings = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("Settings")
                    .font(.brand(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Self.tileFill, in: Self.cardShape)
            .overlay(Self.cardShape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
            .contentShape(Self.cardShape)
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("Profile") {
    MainScreenPreview {
        ProfileView()
    }
}
#endif
