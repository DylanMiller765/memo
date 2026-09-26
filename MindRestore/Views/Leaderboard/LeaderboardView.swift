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
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

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
    @Namespace private var filterSelectionNamespace

    private static var initialCategory: LeaderboardCategory {
        #if DEBUG
        // `--league chimp` (a category's short title) opens that board for screenshots.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--league"), args.indices.contains(i + 1),
           let category = LeaderboardCategory.allCases.first(where: { $0.shortTitle.lowercased() == args[i + 1].lowercased() }) {
            return category
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

    private static let ink = Color(red: 0.043, green: 0.106, blue: 0.133)          // #0B1B22
    private static let mint = Color(red: 0.482, green: 0.89, blue: 0.776)          // #7BE3C6
    private static let cardFill = Color(red: 0, green: 0.086, blue: 0.11)
    private static let cardShape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    /// Where the hill crest sits below the safe area: just under the category chips, so the podium stands on the grass.
    private static let hillCrest: CGFloat = 150

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    headerView
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

                    categoryChips
                        .padding(.top, 14)

                    leaderboardContentHost
                }
                .padding(.bottom, 128)
                .responsiveContent()
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(alignment: .top) {
                HomeHillScene(tier: .calm, crestFromSafeTop: Self.hillCrest)
            }
            .toolbar(.hidden, for: .navigationBar)
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

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedCategory.displayTitle)
                    .font(.brand(size: 30, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.opacity)
                    .accessibilityAddTraits(.isHeader)
                Text(headerSubtitle)
                    .font(.brand(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
            }
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)

            Spacer(minLength: 8)

            periodSegment
        }
        .animation(boardSwapAnimation, value: selectedCategory)
    }

    private var headerSubtitle: String {
        let rivals = rivalCount
        guard totalPlayerCount > 0 || rivals > 0 else { return selectedCategory.heroSubtitle }
        var text = "\(totalPlayerCount.formatted()) player\(totalPlayerCount == 1 ? "" : "s")"
        // With rivals the line gets long; the Today/Week toggle already says the period.
        if rivals > 0 { return text + " + \(rivals) rival\(rivals == 1 ? "" : "s")" }
        return "\(text) · \(periodPhrase)"
    }

    // MARK: - Rivals

    /// Real entries plus labeled Memo rivals when the board is sparse (see LeagueRivals).
    private var board: [LeaderboardEntryData] {
        guard hasRenderedLeaderboardContent else { return entries }
        let baseline = LeagueRivalMemory.baseline(
            category: renderedCategory,
            filter: renderedFilter,
            userScore: entries.first(where: { $0.isCurrentUser })?.score,
            now: .now,
            defaults: .standard
        )
        return LeagueRivals.board(real: entries, category: renderedCategory, baseline: baseline, day: .now)
    }

    private var rivalCount: Int { board.filter(\.isRival).count }

    private var periodPhrase: String {
        switch renderedFilter {
        case .today: return "today"
        case .thisWeek: return "this week"
        case .allTime: return "all time"
        }
    }

    // MARK: - Board Controls

    private var periodSegment: some View {
        HStack(spacing: 4) {
            ForEach(displayedFilters) { filter in
                let isSelected = selectedFilter == filter
                let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
                Button {
                    selectFilter(filter)
                } label: {
                    Text(filter.compactTitle)
                        .font(.brand(size: 13, weight: .heavy))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(isSelected ? Self.ink : .white.opacity(0.7))
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background {
                            if isSelected {
                                shape.fill(.white)
                                    .overlay(shape.strokeBorder(Self.ink, lineWidth: 2))
                                    .background(shape.fill(Self.ink).offset(y: 3))
                                    .matchedGeometryEffect(id: "filter-selection", in: filterSelectionNamespace)
                            }
                        }
                        .contentShape(shape)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(filter.rawValue)\(isSelected ? ", selected" : "")")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .padding(.bottom, 3)
        .background(Self.cardFill.opacity(0.55), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .animation(boardSwapAnimation, value: selectedFilter)
    }

    private var categoryChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(displayedCategories) { category in
                        LeagueCategoryChip(category: category, isSelected: selectedCategory == category) {
                            selectCategory(category)
                        }
                        .id(category.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 6)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                // Focus sits at the end of the rail; start with the selected chip in view.
                proxy.scrollTo(selectedCategory.id, anchor: .center)
            }
            .onChange(of: selectedCategory) { _, category in
                withAnimation(boardSwapAnimation) {
                    proxy.scrollTo(category.id, anchor: .center)
                }
            }
        }
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
        .frame(maxWidth: .infinity, alignment: .top)
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
        } else if board.isEmpty {
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
                    .frame(minHeight: 420)
            } else if isLoading && entries.isEmpty && !hasRenderedLeaderboardContent {
                skeletonLoadingView
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
            } else if entries.isEmpty && loadError != nil {
                errorLeaderboardView
                    .frame(minHeight: 420)
            } else if board.isEmpty {
                emptyLeaderboardView
                    .frame(minHeight: 420)
            } else {
                leaderboardList
                    .opacity(isLoading ? 0.72 : 1)
                    .scaleEffect(isLoading ? 0.994 : 1, anchor: .top)
                    .animation(.smooth(duration: 0.30, extraBounce: 0), value: isLoading)
            }
        }
    }

    // MARK: - Arena

    private var leaderboardList: some View {
        VStack(spacing: 0) {
            podiumView

            if let userEntry = board.first(where: { $0.isCurrentUser }) {
                yourRankCard(userEntry)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }

            climbButton
                .padding(.horizontal, 20)
                .padding(.top, 16)

            if board.count > 3 {
                restOfBoard
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
            }

            if gameCenterService.isAuthenticated {
                Button {
                    gameCenterService.showLeaderboard(category: selectedCategory, timeFilter: selectedFilter)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gamecontroller.fill")
                        Text("Open in Game Center")
                    }
                    .font(.brand(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
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
        let top = Array(board.prefix(3))
        return HStack(alignment: .bottom, spacing: 0) {
            podiumSlot(top, index: 1, lift: 14, delay: 0.3)
            podiumSlot(top, index: 0, lift: 44, delay: 0.5)
            podiumSlot(top, index: 2, lift: 0, delay: 0.15)
        }
        .padding(.horizontal, 12)
        .padding(.top, 44)
        .onAppear {
            podiumAppeared = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                podiumAppeared = true
            }
        }
    }

    @ViewBuilder
    private func podiumSlot(_ top: [LeaderboardEntryData], index: Int, lift: CGFloat, delay: Double) -> some View {
        if top.indices.contains(index) {
            podiumPlayer(top[index], rank: index + 1, paletteIndex: StickerAvatar.distinctIndices(for: top.map(\.username))[index])
                .padding(.bottom, lift)
                .opacity(podiumAppeared ? 1 : 0)
                .offset(y: podiumAppeared ? 0 : 20)
                .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(delay), value: podiumAppeared)
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
        }
    }

    private func podiumPlayer(_ entry: LeaderboardEntryData, rank: Int, paletteIndex: Int) -> some View {
        let size: CGFloat = rank == 1 ? 78 : (rank == 2 ? 62 : 58)
        let name = entry.isCurrentUser ? "You" : entry.username
        return VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                StickerAvatar(name: entry.username, size: size, floor: 5, paletteIndex: paletteIndex, isRival: entry.isRival)
                MedalSticker(rank: rank, size: rank == 1 ? 38 : 34)
                    .offset(x: 12, y: 12)
            }
            .overlay(alignment: .top) {
                if rank == 1 {
                    StickerIcon(kind: .crown, size: 38)
                        .offset(y: -32)
                }
            }

            OutlinedText(text: formatPodiumScore(entry.score), size: rank == 1 ? 22 : 18)
                .padding(.top, 12)

            HStack(spacing: 4) {
                Text(name)
                    .font(.brand(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.88))
                    .shadow(color: .black.opacity(0.4), radius: 4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if entry.isRival { botTag }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rank == 1 ? "First" : rank == 2 ? "Second" : "Third") place, \(name)\(entry.isRival ? ", Memo rival bot" : ""), \(formatScoreCompact(entry.score))")
    }

    /// Small "BOT" label so rivals are never mistaken for real players.
    private var botTag: some View {
        Text("BOT")
            .font(.brand(size: 9, weight: .heavy))
            .foregroundStyle(Self.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Self.mint, in: Capsule())
            .overlay(Capsule().strokeBorder(Self.ink, lineWidth: 1.2))
            .accessibilityHidden(true)
    }

    // MARK: - Your Rank Card

    private func yourRankCard(_ entry: LeaderboardEntryData) -> some View {
        let chase = LeagueChase.make(category: renderedCategory, entries: board)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                OutlinedText(text: "#\(entry.rank)", size: 34)
                StickerAvatar(name: entry.username, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("You · \(formatScoreCompact(entry.score))")
                        .font(.brand(size: 16, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if rivalCount == 0, let percentile = percentileText(rank: entry.rank) {
                        Text("\(percentile) \(periodPhrase)")
                            .font(.brand(size: 12, weight: .bold))
                            .foregroundStyle(Self.mint)
                    }
                }
                Spacer(minLength: 0)
            }

            if let chase {
                HStack {
                    Text(chase.text)
                    Spacer(minLength: 8)
                    if let next = chase.nextRank { Text("#\(next)") }
                }
                .font(.brand(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.top, 12)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2))
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.851, green: 1, blue: 0.945), Self.mint],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: max(14, geo.size.width * chase.progress))
                    }
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Self.ink.opacity(0.7), lineWidth: 2))
                }
                .frame(height: 14)
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Self.cardFill.opacity(0.6), in: Self.cardShape)
        .overlay(Self.cardShape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func percentileText(rank: Int) -> String? {
        guard totalPlayerCount > 0, rank > 0 else { return nil }
        let ratio = Double(rank) / Double(totalPlayerCount)
        let percentile = min(100, max(1, Int(ceil(ratio * 100))))
        return "Top \(percentile)%"
    }

    // MARK: - Climb CTA

    @ViewBuilder
    private var climbButton: some View {
        switch renderedCategory {
        case .focusBlocking:
            if !focusModeService.isEnabled {
                ChunkyButton(title: "Block now to climb", systemImage: "lock.fill") {
                    deepLinkRouter.pendingDestination = .home
                }
            }
        case .streak:
            ChunkyButton(title: "Train today to climb") {
                deepLinkRouter.pendingDestination = .train
            }
        default:
            if let game = renderedCategory.exerciseType {
                ChunkyButton(title: "Play \(renderedCategory.shortTitle) to climb") {
                    deepLinkRouter.pendingDestination = .game(game)
                }
            }
        }
    }

    // MARK: - Rest of the board

    private var restOfBoard: some View {
        VStack(spacing: 0) {
            ForEach(Array(board.dropFirst(3).enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                        .padding(.leading, 56)
                }
                leaderboardRow(entry)
            }
        }
        .background(Self.cardFill.opacity(0.42), in: Self.cardShape)
        .overlay(Self.cardShape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
    }

    private func leaderboardRow(_ entry: LeaderboardEntryData) -> some View {
        let rowShape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.brand(size: 16, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 30)
            StickerAvatar(name: entry.username, size: 38, isRival: entry.isRival)
            Text(entry.isCurrentUser ? "\(entry.username) (you)" : entry.username)
                .font(.brand(size: 15, weight: .heavy))
                .lineLimit(1)
            if entry.isRival { botTag }
            Spacer(minLength: 8)
            Text(formatScoreCompact(entry.score))
                .font(.brand(size: 15, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            if entry.isCurrentUser {
                rowShape.fill(Self.mint.opacity(0.12))
                    .overlay(rowShape.strokeBorder(Self.mint, lineWidth: 2))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(entry.rank), \(entry.isCurrentUser ? "You" : entry.username)\(entry.isRival ? ", Memo rival bot" : ""), \(formatScore(entry.score))")
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

    /// Short score for the podium, where there's no room for a unit word.
    private func formatPodiumScore(_ score: Int) -> String {
        switch renderedCategory {
        case .focusBlocking: return formatScoreCompact(score)
        case .streak: return "\(score)d"
        case .reactionTime: return "\(score) ms"
        case .visualMemory: return "Lvl \(score)"
        default: return "\(score)"
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

            if ProcessInfo.processInfo.arguments.contains("--league-sparse") {
                return CachedLeaderboardSnapshot(entries: [LeaderboardEntryData(rank: 1, username: user?.username ?? "Dylan", score: 142, avatarEmoji: "", level: 12, isCurrentUser: true)], totalPlayerCount: 1)
            }
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

        if ProcessInfo.processInfo.arguments.contains("--league-sparse") {
            return CachedLeaderboardSnapshot(
                entries: [
                    LeaderboardEntryData(rank: 1, username: "Maya", score: 14, avatarEmoji: "", level: 16, isCurrentUser: false),
                    LeaderboardEntryData(rank: 2, username: user?.username ?? "Dylan", score: 11, avatarEmoji: "", level: 12, isCurrentUser: true),
                ],
                totalPlayerCount: 2
            )
        }
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

/// One category in the league rail: sticker + name; the selected one is a chunky white chip.
private struct LeagueCategoryChip: View {
    let category: LeaderboardCategory
    let isSelected: Bool
    let action: () -> Void

    private static let ink = Color(red: 0.043, green: 0.106, blue: 0.133)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: action) {
            HStack(spacing: 6) {
                StickerIcon(kind: category.stickerKind, size: 22)
                Text(category.shortTitle)
                    .font(.brand(size: 14, weight: isSelected ? .heavy : .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Self.ink : .white.opacity(0.85))
            .padding(.leading, 9)
            .padding(.trailing, 13)
            .frame(height: 38)
            .background(shape.fill(isSelected ? Color.white : Color(red: 0, green: 0.086, blue: 0.11).opacity(0.5)))
            .overlay {
                if isSelected {
                    shape.strokeBorder(Self.ink, lineWidth: 2.5)
                } else {
                    shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
            }
            .background {
                if isSelected { shape.fill(Self.ink).offset(y: 4) }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.displayTitle), \(category.pickerMetric)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.smooth(duration: 0.3), value: isSelected)
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
    var stickerKind: StickerKind {
        switch self {
        case .focusBlocking: return .padlock
        case .streak: return .flame
        case .visualMemory: return .grid
        case .numberMemory: return .hash
        case .chimpTest: return .paw
        case .mathSprint: return .math
        case .colorMatch: return .palette
        case .reactionTime: return .bolt
        }
    }

    /// The game a "Play … to climb" button opens; nil for Focus and Streak.
    var exerciseType: ExerciseType? {
        switch self {
        case .visualMemory: return .visualMemory
        case .numberMemory: return .sequentialMemory
        case .chimpTest: return .chimpTest
        case .mathSprint: return .mathSpeed
        case .colorMatch: return .colorMatch
        case .reactionTime: return .reactionTime
        case .focusBlocking, .streak: return nil
        }
    }

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
