import SwiftUI
import SwiftData
import GameKit
import UIKit

private struct LeaderboardCacheKey: Hashable {
    let category: String
    let filter: String

    init(category: LeaderboardCategory, filter: LeaderboardTimeFilter) {
        self.category = category.rawValue
        self.filter = filter.rawValue
    }
}

private struct CachedLeaderboardSnapshot {
    let entries: [LeaderboardEntryData]
    let totalPlayerCount: Int
}

struct LeaderboardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var users: [User]
    @Query(sort: \Exercise.completedAt, order: .reverse) private var exercises: [Exercise]
    @Environment(GameCenterService.self) private var gameCenterService
    @Environment(FocusModeService.self) private var focusModeService

    @State private var selectedCategory: LeaderboardCategory = Self.initialCategory
    @State private var selectedFilter: LeaderboardTimeFilter = .thisWeek
    @State private var entries: [LeaderboardEntryData] = []
    @State private var totalPlayerCount: Int = 0
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var podiumAppeared = false
    @State private var loadError: Error?
    @State private var leaderboardCache: [LeaderboardCacheKey: CachedLeaderboardSnapshot] = [:]
    @State private var activeLoadTask: Task<Void, Never>?
    @State private var hasRenderedLeaderboardContent = false
    @State private var renderedCategory: LeaderboardCategory = Self.initialCategory
    @State private var renderedFilter: LeaderboardTimeFilter = .thisWeek
    @Namespace private var categorySelectionNamespace
    @Namespace private var filterSelectionNamespace

    private static var initialCategory: LeaderboardCategory {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--screenshot-mode") {
            return .focusBlocking
        }
        #endif
        return .focusBlocking
    }

    private var user: User? { users.first }
    private let boardSwapAnimation = Animation.smooth(duration: 0.48, extraBounce: 0.015)
    private let uncachedLoadDelayNanoseconds: UInt64 = 260_000_000
    private var displayedFilters: [LeaderboardTimeFilter] {
        Self.displayedFilters(for: selectedCategory)
    }

    private static func displayedFilters(for category: LeaderboardCategory) -> [LeaderboardTimeFilter] {
        category == .focusBlocking ? [.today, .thisWeek] : [.thisWeek, .allTime]
    }

    private static func defaultFilter(for category: LeaderboardCategory) -> LeaderboardTimeFilter {
        .thisWeek
    }

    private static func normalizedFilter(_ filter: LeaderboardTimeFilter, for category: LeaderboardCategory) -> LeaderboardTimeFilter {
        displayedFilters(for: category).contains(filter) ? filter : defaultFilter(for: category)
    }

    /// Games first (Train-tab order), then Streak and Focus.
    private var displayedCategories: [LeaderboardCategory] {
        LeaderboardCategory.allCases
    }
    private var categoryRows: [GridItem] {
        [
            GridItem(.fixed(40), spacing: 8),
            GridItem(.fixed(40), spacing: 8)
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    headerView
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .padding(.bottom, 10)

                    categoryRail

                    periodPicker
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 14)

                    leaderboardContentHost
                }
                .pageBackground()
                .onAppear {
                    if !hasLoaded {
                        Analytics.leaderboardViewed(category: selectedCategory.rawValue)
                    }
                    refreshVisibleLeaderboard()
                }
                .onDisappear {
                    activeLoadTask?.cancel()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { @MainActor in
                        await focusModeService.refreshForAppForeground()
                        refreshVisibleLeaderboard()
                    }
                }
                .onChange(of: gameCenterService.isAuthenticated) { _, isAuthenticated in
                    guard isAuthenticated else { return }
                    refreshVisibleLeaderboard()
                }
                .onChange(of: focusModeService.authorizationStatus) { _, status in
                    guard status == .approved else { return }
                    refreshVisibleLeaderboard()
                }
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Text(selectedCategory.displayTitle)
                    .mainScreenTitleStyle()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .contentTransition(.opacity)

                Spacer()

                if gameCenterService.isAuthenticated {
                    Button {
                        gameCenterService.showLeaderboard(category: selectedCategory, timeFilter: selectedFilter)
                    } label: {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 44, height: 44)
                            .leaderboardGlassCircle(tint: AppColors.accent, isInteractive: true)
                    }
                    .accessibilityLabel("Open \(selectedCategory.displayTitle) in Game Center")
                }
            }

            Text(selectedCategory.heroSubtitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .contentTransition(.opacity)
        }
        .animation(boardSwapAnimation, value: selectedCategory)
    }

    // MARK: - Board Controls

    private var categoryRail: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 8) {
                    categoryRailContent
                }
            } else {
                categoryRailContent
            }
        }
        .frame(height: 88)
    }

    private var categoryRailContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHGrid(rows: categoryRows, spacing: 8) {
                    ForEach(displayedCategories) { category in
                        CategoryRailChip(
                            category: category,
                            title: category.shortTitle,
                            isSelected: selectedCategory == category,
                            selectionNamespace: categorySelectionNamespace
                        ) {
                            selectCategory(category)
                        }
                        .id(category.id)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selectedCategory) { _, category in
                withAnimation(boardSwapAnimation) {
                    proxy.scrollTo(category.id, anchor: .center)
                }
            }
        }
    }

    private var periodPicker: some View {
        periodPickerButtons
            .frame(height: 42)
    }

    private var periodPickerButtons: some View {
        HStack(spacing: 6) {
            ForEach(displayedFilters) { filter in
                let isSelected = selectedFilter == filter

                Button {
                    selectFilter(filter)
                } label: {
                    ZStack(alignment: .bottom) {
                        Text(filter.compactTitle)
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(isSelected ? .primary : AppColors.textSecondary)
                            .padding(.horizontal, 18)
                            .frame(height: 34)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(AppColors.cardElevated.opacity(0.52))
                                        .matchedGeometryEffect(id: "filter-selection", in: filterSelectionNamespace)
                                        .shadow(color: AppColors.accent.opacity(0.16), radius: 14, y: 5)
                                }
                            }

                        if isSelected {
                            Capsule()
                                .fill(AppColors.accent.opacity(0.92))
                                .frame(width: 22, height: 2)
                                .shadow(color: AppColors.accent.opacity(0.42), radius: 8, y: 2)
                                .offset(y: 3)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(filter.rawValue)\(isSelected ? ", selected" : "")")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .animation(boardSwapAnimation, value: selectedFilter)
    }

    private var leaderboardContentHost: some View {
        ZStack(alignment: .top) {
            leaderboardStateContent
                .id(leaderboardContentID)
                .transition(leaderboardContentTransition)

            if isLoading && hasRenderedLeaderboardContent {
                leaderboardLoadingVeil
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(boardSwapAnimation, value: leaderboardContentID)
        .animation(.smooth(duration: 0.30, extraBounce: 0), value: isLoading)
    }

    private var leaderboardContentID: String {
        let phase: String
        if !gameCenterService.isAuthenticated {
            phase = "auth"
        } else if isLoading && entries.isEmpty && !hasRenderedLeaderboardContent {
            phase = "loading"
        } else if entries.isEmpty && loadError != nil {
            phase = "error"
        } else if entries.isEmpty {
            phase = "empty"
        } else {
            phase = "list"
        }

        return "\(renderedCategory.rawValue)-\(renderedFilter.rawValue)-\(phase)"
    }

    private var leaderboardContentTransition: AnyTransition {
        .asymmetric(
            insertion: .leaderboardSettleIn,
            removal: .leaderboardSettleOut
        )
    }

    private var leaderboardLoadingVeil: some View {
        LinearGradient(
            colors: [
                AppColors.pageBg.opacity(0.18),
                AppColors.pageBg.opacity(0.06),
                AppColors.pageBg.opacity(0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private var leaderboardStateContent: some View {
        Group {
            if !gameCenterService.isAuthenticated && !screenshotMode {
                gameCenterRequiredView
            } else if isLoading && entries.isEmpty && !hasRenderedLeaderboardContent {
                skeletonLoadingView
                    .padding(.horizontal)
                    .padding(.top, 8)
            } else if entries.isEmpty && loadError != nil {
                errorLeaderboardView
            } else if entries.isEmpty {
                emptyLeaderboardView
            } else {
                leaderboardList
                    .opacity(isLoading ? 0.72 : 1)
                    .scaleEffect(isLoading ? 0.994 : 1, anchor: .top)
                    .animation(.smooth(duration: 0.30, extraBounce: 0), value: isLoading)
            }
        }
    }

    // MARK: - Leaderboard List

    private var leaderboardList: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Player count
                if totalPlayerCount > 0 {
                    Text("\(totalPlayerCount) player\(totalPlayerCount == 1 ? "" : "s") ranked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 8)
                }

                // Top 3 podium
                if !entries.isEmpty {
                    podiumView
                        .padding(.bottom, 16)
                }

                // Current user position
                if let userEntry = entries.first(where: { $0.isCurrentUser }) {
                    yourRankCard(userEntry)
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                }

                // Full list
                LazyVStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        leaderboardRow(entry, index: index)
                    }
                }
                .appCard(padding: 0)
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .responsiveContent()
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Empty State

    private var emptyLeaderboardView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image("mascot-podium")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(height: 160)

            Text(renderedCategory == .focusBlocking ? "No Focus Score Yet" : "No Rankings Yet")
                .font(.title3.weight(.semibold))

            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
    }

    private var emptyStateMessage: String {
        if renderedCategory == .focusBlocking {
            return "Turn on Focus Mode and protect time to appear on the board."
        }
        return "Be the first to set a score!\nComplete exercises to appear on the leaderboard."
    }

    // MARK: - Error State

    private var errorLeaderboardView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)

            Text("Couldn't Load Rankings")
                .font(.title3.weight(.semibold))

            Text("Check your connection and try again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                loadLeaderboard()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(AppColors.accent, in: Capsule())
                .foregroundStyle(.white)
            }

            Spacer()
        }
    }

    // MARK: - Game Center Required

    private var gameCenterRequiredView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.violet)

            Text("Game Center Required")
                .font(.title3.weight(.semibold))

            Text("Sign in via Settings \u{2192} Game Center to compete on leaderboards")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Podium

    private var podiumView: some View {
        let count = min(entries.count, 3)
        return VStack(spacing: 0) {
            // Players floating above pedestals
            HStack(alignment: .bottom, spacing: 6) {
                if count >= 2 {
                    podiumPlayer(entries[1], rank: 2)
                        .padding(.bottom, 64)
                        .opacity(podiumAppeared ? 1 : 0)
                        .offset(y: podiumAppeared ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.3), value: podiumAppeared)
                } else {
                    Color.clear.frame(maxWidth: .infinity)
                }
                if count >= 1 {
                    podiumPlayer(entries[0], rank: 1)
                        .padding(.bottom, 88)
                        .opacity(podiumAppeared ? 1 : 0)
                        .offset(y: podiumAppeared ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.5), value: podiumAppeared)
                }
                if count >= 3 {
                    podiumPlayer(entries[2], rank: 3)
                        .padding(.bottom, 48)
                        .opacity(podiumAppeared ? 1 : 0)
                        .offset(y: podiumAppeared ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.15), value: podiumAppeared)
                } else {
                    Color.clear.frame(maxWidth: .infinity)
                }
            }

            // Pedestals
            HStack(alignment: .bottom, spacing: 4) {
                if count >= 2 {
                    podiumPedestal(rank: 2, height: podiumAppeared ? 64 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.2), value: podiumAppeared)
                } else {
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
                if count >= 1 {
                    podiumPedestal(rank: 1, height: podiumAppeared ? 88 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.35), value: podiumAppeared)
                }
                if count >= 3 {
                    podiumPedestal(rank: 3, height: podiumAppeared ? 48 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1), value: podiumAppeared)
                } else {
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .onAppear {
            podiumAppeared = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                podiumAppeared = true
            }
        }
    }

    private func podiumPlayer(_ entry: LeaderboardEntryData, rank: Int) -> some View {
        let color = podiumColor(rank)
        let isFirst = rank == 1

        return VStack(spacing: 6) {
            // Crown for 1st
            if isFirst {
                Image(systemName: "crown.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 1.0, green: 0.65, blue: 0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.6), radius: 6)
            }

            // Avatar circle
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: podiumGradientColors(rank),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: isFirst ? 56 : 46, height: isFirst ? 56 : 46)
                    .shadow(color: color.opacity(0.4), radius: isFirst ? 8 : 4)

                // Initials
                Text(String((entry.isCurrentUser ? "You" : entry.username).prefix(1)).uppercased())
                    .font(.system(size: isFirst ? 22 : 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                // Medal badge
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Text("\(rank)")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(color)
                    )
                    .offset(x: isFirst ? 20 : 16, y: isFirst ? 20 : 16)
            }

            // Score (compact for podium — no wrapping)
            Text(formatScoreCompact(entry.score))
                .font(.system(size: isFirst ? 20 : 15, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(color)

            // Username
            Text(entry.isCurrentUser ? "You" : entry.username)
                .font(.system(size: isFirst ? 12 : 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rank == 1 ? "First" : rank == 2 ? "Second" : "Third") place, \(entry.isCurrentUser ? "You" : entry.username), score \(formatScoreCompact(entry.score))")
    }

    private func podiumPedestal(rank: Int, height: CGFloat) -> some View {
        let color = podiumColor(rank)
        let isFirst = rank == 1

        return ZStack {
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            color.opacity(0.30),
                            color.opacity(0.15),
                            color.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [color.opacity(0.5), color.opacity(0.15)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                )

            // Shine highlight at top
            VStack {
                UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(isFirst ? 0.25 : 0.15), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 16)
                Spacer()
            }

            // Rank number watermark
            Text("\(rank)")
                .font(.system(size: height * 0.55, weight: .black, design: .rounded))
                .foregroundStyle(color.opacity(0.12))
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func podiumColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.76, blue: 0.03) // Gold
        case 2: return Color(red: 0.65, green: 0.68, blue: 0.72) // Silver
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20) // Bronze
        default: return .secondary
        }
    }

    private func podiumGradientColors(_ rank: Int) -> [Color] {
        switch rank {
        case 1: return [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 0.93, green: 0.65, blue: 0.0)]
        case 2: return [Color(red: 0.75, green: 0.78, blue: 0.82), Color(red: 0.55, green: 0.58, blue: 0.62)]
        case 3: return [Color(red: 0.85, green: 0.55, blue: 0.25), Color(red: 0.65, green: 0.38, blue: 0.15)]
        default: return [.gray, .gray]
        }
    }

    // MARK: - Your Rank Card

    private func yourRankCard(_ entry: LeaderboardEntryData) -> some View {
        let scoreText = formatScoreCompact(entry.score)

        return HStack(spacing: 14) {
            yourRankBadge(rank: entry.rank)
            yourRankIdentity(username: entry.username)
            Spacer()
            yourRankScore(scoreText: scoreText, rank: entry.rank)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(AppColors.cardSurface)
                .shadow(color: AppColors.accent.opacity(0.10), radius: 8, y: 2)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.accent.opacity(0.15), lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your rank: number \(entry.rank), score \(scoreText)")
    }

    private func yourRankBadge(rank: Int) -> some View {
        ZStack {
            Circle()
                .fill(AppColors.accent.opacity(0.12))
                .frame(width: 56, height: 56)
            Text("#\(rank)")
                .font(.system(size: 24, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(AppColors.accent)
        }
    }

    private func yourRankIdentity(username: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("YOUR RANK")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(1)
            Text(username)
                .font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder
    private func yourRankScore(scoreText: String, rank: Int) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(scoreText)
                .font(.headline.weight(.bold).monospacedDigit())
            if let percentileText = percentileText(rank: rank) {
                Text(percentileText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.accent)
            }
        }
    }

    private func percentileText(rank: Int) -> String? {
        guard totalPlayerCount > 0, rank > 0 else { return nil }
        let ratio = Double(rank) / Double(totalPlayerCount)
        let percentile = min(100, max(1, Int(ceil(ratio * 100))))
        return "Top \(percentile)%"
    }

    // MARK: - Row

    private func leaderboardRow(_ entry: LeaderboardEntryData, index: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(entry.rank <= 3 ? medalColor("\(entry.rank)") : .secondary)
                .frame(width: 30, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.isCurrentUser ? "You" : entry.username)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(entry.isCurrentUser ? AppColors.accent : .primary)
            }

            Spacer()

            Text(formatScore(entry.score))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(entry.isCurrentUser ? AppColors.accent : .primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            if entry.isCurrentUser {
                // Accent left border for current user
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColors.accent)
                        .frame(width: 3)
                    Spacer()
                }
                .background(AppColors.accent.opacity(0.06))
            } else if index % 2 == 0 {
                // Alternating row background
                AppColors.pageBg.opacity(0.5)
            }
        }
        .overlay(alignment: .bottom) {
            if entry.rank < entries.count {
                Divider().padding(.leading, 56)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(entry.rank), \(entry.isCurrentUser ? "You" : entry.username), score \(formatScore(entry.score))\(entry.isCurrentUser ? ", you" : "")")
    }

    private func medalColor(_ medal: String) -> Color {
        switch medal {
        case "1": return AppColors.amber
        case "2": return Color.gray
        case "3": return AppColors.coral
        default: return .secondary
        }
    }

    // MARK: - Helpers

    private func formatScoreCompact(_ score: Int) -> String {
        switch renderedCategory {
        case .focusBlocking:
            let h = score / 60
            let m = score % 60
            return h > 0 ? "\(h)h \(m)m" : "\(m)m"
        default:
            return formatScore(score)
        }
    }

    private func formatScore(_ score: Int) -> String {
        switch renderedCategory {
        case .streak: return "\(score)d"
        case .reactionTime: return "\(score) ms"
        case .visualMemory: return "Lvl \(score)"
        case .numberMemory: return "\(score) digits"
        case .chimpTest: return "\(score) numbers"
        case .mathSprint, .colorMatch: return "\(score)"
        case .focusBlocking:
            let h = score / 60
            let m = score % 60
            return h > 0 ? "\(h)h \(m)m protected" : "\(m)m protected"
        default:
            if score >= 1000 {
                return String(format: "%.1fk", Double(score) / 1000.0)
            }
            return "\(score)"
        }
    }

    // MARK: - Skeleton Loading

    private var skeletonLoadingView: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: [100, 120, 90, 140, 80][index], height: 14)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 60, height: 10)
                    }

                    Spacer()

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 50, height: 16)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)

                if index < 4 {
                    Divider().padding(.leading, 54)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(AppColors.cardSurface)
                .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        }
        .shimmer()
    }

    private func selectCategory(_ category: LeaderboardCategory) {
        guard selectedCategory != category else { return }
        playSelectionHaptic()
        let nextFilter = Self.normalizedFilter(selectedFilter, for: category)
        withAnimation(boardSwapAnimation) {
            selectedCategory = category
            selectedFilter = nextFilter
        }
        refreshVisibleLeaderboard(deferUncachedBy: uncachedLoadDelayNanoseconds)
        Analytics.leaderboardViewed(category: category.rawValue)
    }

    private func selectFilter(_ filter: LeaderboardTimeFilter) {
        guard displayedFilters.contains(filter) else { return }
        guard selectedFilter != filter else { return }
        playSelectionHaptic()
        withAnimation(boardSwapAnimation) {
            selectedFilter = filter
        }
        refreshVisibleLeaderboard(deferUncachedBy: uncachedLoadDelayNanoseconds)
    }

    private func playSelectionHaptic() {
        let feedback = UISelectionFeedbackGenerator()
        feedback.selectionChanged()
    }

    private func loadLeaderboard(deferUncachedBy delayNanoseconds: UInt64 = 0) {
        #if DEBUG
        if screenshotMode {
            hasLoaded = true
            let category = selectedCategory
            let filter = selectedFilter
            let snapshot = screenshotSnapshot(category: category, filter: filter)
            leaderboardCache[LeaderboardCacheKey(category: category, filter: filter)] = snapshot
            withAnimation(boardSwapAnimation) {
                hasRenderedLeaderboardContent = true
                renderedCategory = category
                renderedFilter = filter
                loadError = nil
                entries = snapshot.entries
                totalPlayerCount = snapshot.totalPlayerCount
                isLoading = false
            }
            return
        }
        #endif

        guard gameCenterService.isAuthenticated else {
            hasLoaded = true
            return
        }

        hasLoaded = true

        let category = selectedCategory
        let filter = selectedFilter
        let key = LeaderboardCacheKey(category: category, filter: filter)
        let cachedSnapshot = leaderboardCache[key]

        activeLoadTask?.cancel()

        if let cached = cachedSnapshot {
            withAnimation(boardSwapAnimation) {
                hasRenderedLeaderboardContent = true
                renderedCategory = category
                renderedFilter = filter
                loadError = nil
                entries = cached.entries
                totalPlayerCount = cached.totalPlayerCount
                isLoading = false
            }
        } else if delayNanoseconds == 0 || !hasRenderedLeaderboardContent {
            withAnimation(boardSwapAnimation) {
                if !hasRenderedLeaderboardContent {
                    renderedCategory = category
                    renderedFilter = filter
                    totalPlayerCount = 0
                }
                loadError = nil
                isLoading = true
            }
        }

        activeLoadTask = Task {
            if cachedSnapshot == nil, delayNanoseconds > 0, hasRenderedLeaderboardContent {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                guard !Task.isCancelled, selectedCategory == category, selectedFilter == filter else { return }

                withAnimation(boardSwapAnimation) {
                    loadError = nil
                    isLoading = true
                }
            }

            let result = await gameCenterService.loadLeaderboardEntries(
                category: category,
                timeFilter: filter
            )
            guard !Task.isCancelled else { return }
            if result.error != nil, cachedSnapshot != nil {
                guard selectedCategory == category, selectedFilter == filter else { return }
                withAnimation(boardSwapAnimation) {
                    hasRenderedLeaderboardContent = true
                    renderedCategory = category
                    renderedFilter = filter
                    loadError = result.error
                    isLoading = false
                }
                return
            }

            let snapshot = makeSnapshot(from: result, category: category, filter: filter)
            leaderboardCache[key] = snapshot

            guard selectedCategory == category, selectedFilter == filter else { return }
            withAnimation(boardSwapAnimation) {
                hasRenderedLeaderboardContent = true
                renderedCategory = category
                renderedFilter = filter
                loadError = result.error
                entries = snapshot.entries
                totalPlayerCount = snapshot.totalPlayerCount
                isLoading = false
            }
        }
    }

    private func refreshVisibleLeaderboard(deferUncachedBy delayNanoseconds: UInt64 = 0) {
        if selectedCategory == .focusBlocking {
            focusModeService.reconcileBlockedMinutes()
            reportFocusLeagueScoresIfNeeded()
        }
        loadLeaderboard(deferUncachedBy: delayNanoseconds)
    }

    private func makeSnapshot(
        from result: GameCenterService.LeaderboardResult,
        category: LeaderboardCategory,
        filter: LeaderboardTimeFilter
    ) -> CachedLeaderboardSnapshot {
        var loadedEntries = result.entries
        let lowerScoreWins = isLowerScoreBetter(category)

        // Update local player's score if local Focus/game data is fresher than Game Center.
        if let localBest = localScore(for: category, timeFilter: filter), shouldUseLocalScore(localBest, for: category),
           let idx = loadedEntries.firstIndex(where: { $0.isCurrentUser }),
           lowerScoreWins ? loadedEntries[idx].score > localBest : loadedEntries[idx].score < localBest {
            loadedEntries[idx] = LeaderboardEntryData(
                rank: loadedEntries[idx].rank,
                username: loadedEntries[idx].username,
                score: localBest,
                avatarEmoji: loadedEntries[idx].avatarEmoji,
                level: loadedEntries[idx].level,
                isCurrentUser: true
            )
        }

        // If the local player isn't in the results yet, inject their local score.
        let hasLocalPlayer = loadedEntries.contains { $0.isCurrentUser }
        if !hasLocalPlayer, let localScore = localScore(for: category, timeFilter: filter), shouldUseLocalScore(localScore, for: category) {
            loadedEntries.append(LeaderboardEntryData(
                rank: 0,
                username: GKLocalPlayer.local.displayName,
                score: localScore,
                avatarEmoji: "",
                level: 0,
                isCurrentUser: true
            ))
        }

        // Zero minutes is not a real Focus League entry, and zero-score game rows are noise.
        loadedEntries = loadedEntries.filter { $0.score > 0 || $0.isCurrentUser }

        loadedEntries.sort { lowerScoreWins ? $0.score < $1.score : $0.score > $1.score }
        loadedEntries = rankedEntries(from: loadedEntries)

        // Remove current user if their score is 0.
        if let userEntry = loadedEntries.first(where: { $0.isCurrentUser }), userEntry.score <= 0 {
            loadedEntries = loadedEntries.filter { !$0.isCurrentUser }
        }

        return CachedLeaderboardSnapshot(
            entries: loadedEntries,
            totalPlayerCount: max(result.totalPlayerCount, loadedEntries.count)
        )
    }

    #if DEBUG
    private var screenshotMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--screenshot-mode")
    }

    private func screenshotSnapshot(category: LeaderboardCategory, filter: LeaderboardTimeFilter) -> CachedLeaderboardSnapshot {
        if category == .focusBlocking {
            let focusEntries = [
                LeaderboardEntryData(rank: 1, username: "Maya", score: 614, avatarEmoji: "M", level: 16, isCurrentUser: false),
                LeaderboardEntryData(rank: 2, username: "Ava", score: 548, avatarEmoji: "A", level: 18, isCurrentUser: false),
                LeaderboardEntryData(rank: 3, username: "Leo", score: 487, avatarEmoji: "L", level: 14, isCurrentUser: false),
                LeaderboardEntryData(rank: 4, username: user?.username ?? "Dylan", score: 426, avatarEmoji: "", level: user?.level ?? 12, isCurrentUser: true),
                LeaderboardEntryData(rank: 5, username: "Noah", score: 392, avatarEmoji: "N", level: 13, isCurrentUser: false),
                LeaderboardEntryData(rank: 6, username: "Zoe", score: 361, avatarEmoji: "Z", level: 11, isCurrentUser: false)
            ]

            return CachedLeaderboardSnapshot(entries: focusEntries, totalPlayerCount: 1_204)
        }

        let baseEntries = [
            LeaderboardEntryData(rank: 1, username: "Ava", score: 872, avatarEmoji: "A", level: 18, isCurrentUser: false),
            LeaderboardEntryData(rank: 2, username: "Maya", score: 846, avatarEmoji: "M", level: 16, isCurrentUser: false),
            LeaderboardEntryData(rank: 3, username: "Leo", score: 821, avatarEmoji: "L", level: 14, isCurrentUser: false),
            LeaderboardEntryData(rank: 4, username: "Noah", score: 803, avatarEmoji: "N", level: 13, isCurrentUser: false),
            LeaderboardEntryData(rank: 5, username: user?.username ?? "Dylan", score: 748, avatarEmoji: "", level: user?.level ?? 12, isCurrentUser: true),
            LeaderboardEntryData(rank: 6, username: "Zoe", score: 731, avatarEmoji: "Z", level: 11, isCurrentUser: false)
        ]

        return CachedLeaderboardSnapshot(entries: baseEntries, totalPlayerCount: 128)
    }
    #else
    private var screenshotMode: Bool { false }
    #endif

    private func rankedEntries(from entries: [LeaderboardEntryData]) -> [LeaderboardEntryData] {
        entries.enumerated().map { index, entry in
            LeaderboardEntryData(
                rank: index + 1,
                username: entry.username,
                score: entry.score,
                avatarEmoji: entry.avatarEmoji,
                level: entry.level,
                isCurrentUser: entry.isCurrentUser
            )
        }
    }

    /// Get the user's local best score for a leaderboard category
    private func localScore(for category: LeaderboardCategory, timeFilter: LeaderboardTimeFilter) -> Int? {
        switch category {
        case .streak:
            return user?.longestStreak
        case .reactionTime:
            // PersonalBestTracker stores inverted (1000-ms), but leaderboard is raw ms now
            let inverted = PersonalBestTracker.shared.best(for: .reactionTime)
            return inverted > 0 ? (1000 - inverted) : nil
        case .visualMemory:
            return PersonalBestTracker.shared.best(for: .visualMemory)
        case .numberMemory:
            return PersonalBestTracker.shared.best(for: .sequentialMemory)
        case .chimpTest:
            return PersonalBestTracker.shared.best(for: .chimpTest)
        case .mathSprint:
            return PersonalBestTracker.shared.best(for: .mathSpeed)
        case .colorMatch:
            return PersonalBestTracker.shared.best(for: .colorMatch)
        case .focusBlocking:
            return focusModeService.focusLeagueScore(for: timeFilter)
        }
    }

    private func isLowerScoreBetter(_ category: LeaderboardCategory) -> Bool {
        category == .reactionTime
    }

    private func shouldUseLocalScore(_ score: Int, for category: LeaderboardCategory) -> Bool {
        score > 0
    }

    private func reportFocusLeagueScoresIfNeeded() {
        guard selectedCategory == .focusBlocking,
              gameCenterService.isAuthenticated else { return }

        for filter in Self.displayedFilters(for: .focusBlocking) {
            guard let score = focusModeService.focusLeagueScore(for: filter) else { continue }
            gameCenterService.reportFocusLeagueScore(score, for: filter)
        }
    }
}

private struct CategoryRailChip: View {
    let category: LeaderboardCategory
    let title: String
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(category.pickerTint.opacity(0.18))
                        .matchedGeometryEffect(id: "category-selection", in: selectionNamespace)
                        .shadow(color: category.pickerTint.opacity(0.26), radius: 18, y: 5)
                }

                HStack(spacing: 8) {
                    Image(systemName: category.icon)
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(isSelected ? .white : category.pickerTint)
                        .frame(width: 24, height: 24)
                        .background(iconBackground, in: Circle())

                    Text(title)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(isSelected ? .primary : AppColors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .padding(.leading, 8)
                .padding(.trailing, 12)
            }
            .frame(minWidth: category.chipWidth, maxWidth: category.chipWidth)
            .frame(height: 40)
            .leaderboardGlassCapsule(tint: isSelected ? category.pickerTint : category.pickerTint.opacity(0.24), isInteractive: true)
            .overlay(
                Capsule()
                    .stroke(isSelected ? category.pickerTint.opacity(0.76) : AppColors.cardBorder.opacity(0.42), lineWidth: isSelected ? 1.35 : 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.015 : 1)
        .accessibilityLabel("\(category.displayTitle), \(category.pickerMetric)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.smooth(duration: 0.42, extraBounce: 0.015), value: isSelected)
    }

    private var iconBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [category.pickerTint, AppColors.electricViolet.opacity(0.88)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(AppColors.cardElevated.opacity(0.64))
    }
}

private struct LeaderboardSettleModifier: ViewModifier {
    let opacity: Double
    let scale: CGFloat
    let y: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale, anchor: .top)
            .offset(y: y)
    }
}

private extension AnyTransition {
    static var leaderboardSettleIn: AnyTransition {
        .modifier(
            active: LeaderboardSettleModifier(opacity: 0, scale: 0.985, y: 10),
            identity: LeaderboardSettleModifier(opacity: 1, scale: 1, y: 0)
        )
    }

    static var leaderboardSettleOut: AnyTransition {
        .modifier(
            active: LeaderboardSettleModifier(opacity: 0, scale: 1.006, y: -6),
            identity: LeaderboardSettleModifier(opacity: 1, scale: 1, y: 0)
        )
    }
}

private extension LeaderboardCategory {
    var displayTitle: String {
        switch self {
        case .focusBlocking: return "Focus League"
        default: return rawValue
        }
    }

    var heroSubtitle: String {
        switch self {
        case .focusBlocking: return "Most protected Focus time ranks first."
        case .streak: return "Longest training streak ranks first."
        case .reactionTime: return "Fastest 5-round average ranks first."
        case .colorMatch: return "Most correct before the bar runs out."
        case .visualMemory: return "Highest grid level ranks first."
        case .numberMemory: return "Longest number recalled ranks first."
        case .mathSprint: return "Most questions before the bar runs out."
        case .chimpTest: return "Most numbers in a completed level."
        }
    }

    var pickerMetric: String {
        switch self {
        case .focusBlocking: return "Protected Focus time"
        case .streak: return "Longest daily run"
        case .reactionTime: return "Lowest average milliseconds"
        case .colorMatch: return "Most correct"
        case .visualMemory: return "Highest grid level"
        case .numberMemory: return "Longest number"
        case .mathSprint: return "Most questions"
        case .chimpTest: return "Most numbers"
        }
    }

    var compactMetric: String {
        switch self {
        case .focusBlocking: return "Protected time"
        case .streak: return "Daily run"
        case .reactionTime: return "Lower ms"
        case .colorMatch: return "Correct"
        case .visualMemory: return "Grid level"
        case .numberMemory: return "Digits"
        case .mathSprint: return "Questions"
        case .chimpTest: return "Numbers"
        }
    }

    var shelfTitle: String {
        switch self {
        case .focusBlocking: return "Focus"
        case .streak: return "Streak"
        default: return shortTitle
        }
    }

    var shortTitle: String {
        switch self {
        case .focusBlocking: return "Focus"
        case .reactionTime: return "Reaction"
        case .colorMatch: return "Color"
        case .visualMemory: return "Visual"
        case .numberMemory: return "Number"
        case .mathSprint: return "Math"
        case .chimpTest: return "Chimp"
        default: return rawValue
        }
    }

    var chipWidth: CGFloat {
        switch self {
        case .streak, .colorMatch, .visualMemory, .numberMemory, .mathSprint, .chimpTest:
            return 96
        case .focusBlocking:
            return 104
        case .reactionTime:
            return 112
        }
    }

    var pickerTint: Color {
        switch self {
        case .focusBlocking: return AppColors.periwinkle
        case .streak: return AppColors.coral
        case .reactionTime: return AppColors.sky
        case .colorMatch: return AppColors.rose
        case .visualMemory: return AppColors.teal
        case .numberMemory: return AppColors.mint
        case .mathSprint: return AppColors.indigo
        case .chimpTest: return AppColors.amber
        }
    }

}

private extension LeaderboardTimeFilter {
    var compactTitle: String {
        switch self {
        case .today: return "Today"
        case .thisWeek: return "Week"
        case .allTime: return "All time"
        }
    }
}

private extension View {
    @ViewBuilder
    func leaderboardGlassCapsule(tint: Color, isInteractive: Bool) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular.tint(tint.opacity(0.18)).interactive(isInteractive), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppColors.cardBorder.opacity(0.78), lineWidth: 1)
                )
                .shadow(color: tint.opacity(0.14), radius: 16, y: 6)
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .background(AppColors.cardSurface.opacity(0.68), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppColors.cardBorder.opacity(0.78), lineWidth: 1)
                )
                .shadow(color: tint.opacity(0.12), radius: 12, y: 4)
        }
    }

    @ViewBuilder
    func leaderboardGlassRounded(cornerRadius: CGFloat, tint: Color, isInteractive: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular.tint(tint.opacity(0.13)).interactive(isInteractive), in: shape)
                .background(AppColors.cardSurface.opacity(0.35), in: shape)
                .overlay(
                    shape.stroke(AppColors.cardBorder.opacity(0.64), lineWidth: 1)
                )
                .shadow(color: tint.opacity(0.10), radius: 16, y: 6)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .background(AppColors.cardSurface.opacity(0.78), in: shape)
                .overlay(
                    shape.stroke(AppColors.cardBorder.opacity(0.72), lineWidth: 1)
                )
                .shadow(color: tint.opacity(0.08), radius: 10, y: 4)
        }
    }

    @ViewBuilder
    func leaderboardGlassCircle(tint: Color, isInteractive: Bool) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular.tint(tint.opacity(0.16)).interactive(isInteractive), in: Circle())
                .overlay(
                    Circle()
                        .stroke(AppColors.cardBorder.opacity(0.72), lineWidth: 1)
                )
                .shadow(color: tint.opacity(0.12), radius: 12, y: 4)
        } else {
            self
                .background(.ultraThinMaterial, in: Circle())
                .background(AppColors.cardSurface.opacity(0.68), in: Circle())
                .overlay(
                    Circle()
                        .stroke(AppColors.cardBorder.opacity(0.72), lineWidth: 1)
                )
                .shadow(color: tint.opacity(0.10), radius: 9, y: 3)
        }
    }
}

#if DEBUG
#Preview("Compete") {
    MainScreenPreview {
        LeaderboardView()
    }
}
#endif
