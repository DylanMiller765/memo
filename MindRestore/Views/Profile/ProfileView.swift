import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreService.self) private var storeService
    @Environment(GameCenterService.self) private var gameCenterService
    @Query private var users: [User]

    @State private var showingSettings = false
    @State private var globalRank: Int?

    private var user: User? { users.first }
    private var isProUser: Bool { storeService.isProUser }


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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    MainScreenTitle(text: "Profile")
                        .staggered(index: 0)

                    playerCard
                        .staggered(index: 1)

                    settingsButton
                        .staggered(index: 2)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .responsiveContent()
                .frame(maxWidth: .infinity)
            }
            .pageBackground()
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

    // MARK: - Player Card

    private var playerCard: some View {
        VStack(spacing: 0) {
            // Rive Mascot
            RiveMascotView(
                mood: profileMascotMood,
                size: 120
            )
            .frame(height: 110)
            .clipped()

            // Name + Join Date
            VStack(spacing: 6) {
                Text(user?.username.isEmpty == false ? user!.username : "Player")
                    .font(.system(size: 28, weight: .bold))

                if let user {
                    Text("joined \(user.createdAt.formatted(.dateTime.month(.twoDigits).day(.twoDigits).year()))")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 20)

            Divider()
                .padding(.horizontal, 20)

            // Stat Pills
            HStack(spacing: 0) {
                statPill(
                    value: "\(user?.resistedCount ?? 0)",
                    label: "RESISTED",
                    color: .primary
                )

                Divider()
                    .frame(height: 40)

                statPill(
                    value: "\(user?.currentStreak ?? 0)",
                    label: "STREAK",
                    color: AppColors.mint
                )

                Divider()
                    .frame(height: 40)

                statPill(
                    value: globalRank != nil ? "#\(globalRank!)" : "--",
                    label: "THIS WEEK",
                    color: AppColors.accent
                )
            }
            .padding(.vertical, 16)
        }
    }

    private func statPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - XP Progress


    // MARK: - Achievements



    // MARK: - Settings Button

    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)

                Text("Settings")
                    .font(.subheadline.weight(.medium))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
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
