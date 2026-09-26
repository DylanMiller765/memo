import SwiftUI
import GameKit

/// Shows the user's leaderboard rank after completing an exercise.
/// Pro users see their exact rank + nearby competitors from Game Center.
/// Free users see an upgrade CTA.
struct LeaderboardRankCard: View {
    let exerciseType: ExerciseType?  // nil for brain score
    let userScore: Int

    @Environment(GameCenterService.self) private var gameCenterService

    @State private var entries: [LeaderboardEntryData] = []
    @State private var userRank: Int = 0
    @State private var totalPlayers: Int = 0
    @State private var isLoading = true
    @State private var animateIn = false

    private var leaderboardCategory: LeaderboardCategory? {
        exerciseType.flatMap(UnlockGame.init(exerciseType:))?.leaderboardCategory
    }

    private var accentColor: Color {
        guard let type = exerciseType else { return AppColors.accent }
        switch type {
        case .reactionTime: return AppColors.coral
        case .colorMatch: return AppColors.violet
        case .speedMatch: return AppColors.sky
        case .visualMemory: return AppColors.indigo
        case .sequentialMemory: return AppColors.teal
        case .mathSpeed: return AppColors.amber
        case .dualNBack: return AppColors.sky
        case .chunkingTraining: return AppColors.rose
        default: return AppColors.accent
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if leaderboardCategory == nil {
                // Exercise type has no leaderboard
                EmptyView()
            } else if !gameCenterService.isAuthenticated {
                // Not signed in to Game Center
                EmptyView()
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading rank...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .appCard(padding: 0)
            } else if totalPlayers <= 1 {
                // Not enough players for meaningful ranking
                EmptyView()
            } else {
                proRankView
            }
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 12)
        .onAppear {
            loadRank()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3)) {
                animateIn = true
            }
        }
    }

    // MARK: - Pro User: Full Rank View

    private var proRankView: some View {
        VStack(spacing: 0) {
            // Header + Rank in one row
            HStack(spacing: 12) {
                // Rank number
                VStack(spacing: 1) {
                    Text("#\(userRank)")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(accentColor)
                    Text(percentileText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(width: 64)

                // Rank bar + labels
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(accentColor)
                        Text("LEADERBOARD")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppColors.textTertiary)
                            .tracking(1.0)
                        Spacer()
                        Text("\(totalPlayers) players")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    rankBar
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            // Nearby competitors
            if nearbyEntries.count > 1 {
                Rectangle().fill(AppColors.cardBorder).frame(height: 1)

                VStack(spacing: 0) {
                    ForEach(nearbyEntries) { entry in
                        nearbyRow(entry)
                        if entry.id != nearbyEntries.last?.id {
                            Rectangle().fill(AppColors.cardBorder).frame(height: 0.5)
                                .padding(.leading, 42)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .appCard(padding: 0)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Subviews

    private var rankBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let position = totalPlayers > 1
                ? CGFloat(userRank - 1) / CGFloat(totalPlayers - 1)
                : 0.5

            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(AppColors.cardBorder)
                    .frame(height: 4)

                // Filled portion
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.5)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, width * (1 - position)), height: 4)

                // User marker
                Circle()
                    .fill(accentColor)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    .shadow(color: accentColor.opacity(0.3), radius: 2)
                    .offset(x: width * position - 5)
            }
        }
        .frame(height: 10)
    }

    private func nearbyRow(_ entry: LeaderboardEntryData) -> some View {
        HStack(spacing: 8) {
            Text("#\(entry.rank)")
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(entry.isCurrentUser ? accentColor : AppColors.textTertiary)
                .frame(width: 28, alignment: .trailing)

            Text(entry.isCurrentUser ? "You" : entry.username)
                .font(.system(size: 12, weight: entry.isCurrentUser ? .bold : .medium))
                .foregroundStyle(entry.isCurrentUser ? AppColors.textPrimary : AppColors.textSecondary)
                .lineLimit(1)

            Spacer()

            Text(formatScore(entry.score))
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(entry.isCurrentUser ? accentColor : AppColors.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(entry.isCurrentUser ? accentColor.opacity(0.06) : .clear)
    }

    // MARK: - Data

    private var percentileText: String {
        guard totalPlayers > 0, userRank > 0 else { return "" }
        // rank 1 of 100 = Top 1%, rank 50 of 100 = Top 50%
        let pct = max(1, min(100, Int(ceil(Double(userRank) / Double(totalPlayers) * 100))))
        return "Top \(pct)%"
    }

    private var nearbyEntries: [LeaderboardEntryData] {
        guard let userIndex = entries.firstIndex(where: { $0.isCurrentUser }) else { return [] }
        let start = max(0, userIndex - 1)
        let end = min(entries.count - 1, userIndex + 1)
        return Array(entries[start...end])
    }

    private func formatScore(_ score: Int) -> String {
        guard let type = exerciseType else { return "\(score)" }
        switch type {
        case .reactionTime: return "\(score)ms"
        case .colorMatch, .speedMatch:
            let accuracy = score / 1000
            if accuracy == 0 { return "\(score)" }
            return "\(accuracy)%"
        case .mathSpeed:
            let correct = score / 1000
            if correct == 0 { return "\(score)" }
            return "\(correct)/20"
        case .visualMemory: return "Lvl \(score)"
        case .dualNBack: return "Lvl \(score)"
        case .sequentialMemory: return "\(score)"
        case .wordScramble:
            let primary = score / 1000
            if primary == 0 { return "\(score)" }
            return "\(primary)/10"
        case .memoryChain: return "\(score)"
        case .chimpTest: return "Lvl \(score)"
        case .verbalMemory: return "\(score)"
        default: return "\(score)"
        }
    }

    private func loadRank() {
        guard gameCenterService.isAuthenticated, let category = leaderboardCategory else {
            isLoading = false
            return
        }

        Task {
            let result = await gameCenterService.loadLeaderboardEntries(
                category: category,
                timeFilter: .allTime
            )
            var loadedEntries = result.entries
            var playerCount = result.totalPlayerCount

            if let userEntry = result.localPlayerEntry {
                userRank = max(1, userEntry.rank)
            } else if userScore > 0 {
                // GameCenter hasn't propagated yet — inject local score
                let isLowToHigh = category == .reactionTime
                let localEntry = LeaderboardEntryData(
                    rank: 0,
                    username: GKLocalPlayer.local.displayName,
                    score: userScore,
                    avatarEmoji: "",
                    level: 0,
                    isCurrentUser: true
                )
                loadedEntries.append(localEntry)

                if isLowToHigh {
                    loadedEntries.sort { $0.score < $1.score }
                } else {
                    loadedEntries.sort { $0.score > $1.score }
                }

                // Find injected rank
                if let idx = loadedEntries.firstIndex(where: { $0.isCurrentUser }) {
                    userRank = idx + 1
                }
                playerCount = max(playerCount, loadedEntries.count)
            }

            entries = loadedEntries.enumerated().map { index, entry in
                LeaderboardEntryData(
                    rank: index + 1,
                    username: entry.username,
                    score: entry.score,
                    avatarEmoji: entry.avatarEmoji,
                    level: entry.level,
                    isCurrentUser: entry.isCurrentUser
                )
            }
            totalPlayers = max(playerCount, 1)
            isLoading = false
        }
    }
}

// MARK: - Preview

#Preview {
    LeaderboardRankCard(
        exerciseType: .reactionTime,
        userScore: 245
    )
    .padding()
    .environment(GameCenterService())
}
