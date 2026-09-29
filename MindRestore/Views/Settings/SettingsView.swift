import SwiftUI
import SwiftData
import StoreKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreService.self) private var storeService
    @Environment(GameCenterService.self) private var gameCenterService
    @Environment(FocusModeService.self) private var focusModeService
    @Query private var users: [User]

    @State private var showingPaywall = false
    @State private var showingResetConfirmation = false
    @State private var showingScreenshotDataConfirmation = false
    @State private var screenshotDataLoaded = false
    @State private var debugTapCount = 0
    @State private var showingDebugFocusSetup = false
    @State private var editingName = false
    @State private var editedName = ""
    @State private var showingFocusSettings = false
    @State private var showingManageSubscriptions = false
    @State private var restoreMessage: String?
    @Environment(\.dismiss) private var dismiss

    // Profile's palette: Settings opens from Profile and should read as part of it.
    private static let ink = Color(red: 0.043, green: 0.106, blue: 0.133)          // #0B1B22
    private static let mint = Color(red: 0.482, green: 0.89, blue: 0.776)          // #7BE3C6
    @AppStorage(SoundPreference.key) private var soundOn = true

    private var user: User? { users.first }
    private var isProUser: Bool { storeService.isProUser }


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    // Memo stands on the hill, like Profile; the cards sit on the ground below.
                    ZStack(alignment: .bottom) {
                        Ellipse()
                            .fill(Color.black.opacity(0.45))
                            .frame(width: 80, height: 14)
                            .blur(radius: 4)
                            .offset(y: -3)
                        RiveMascotView(mood: .happy, size: 130, playbackPolicy: .continuous)
                            .frame(height: 116)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, -14)
                    section("Account") {
                        nameRow
                        rowDivider
                        gameCenterRow
                    }
                    section("Focus Mode") { focusRow }
                    section("Preferences") { preferencesRows }
                    section("Subscription") { subscriptionRows }
                    section("About") { aboutRows }

                    // Reset Data (standalone red button)
                    resetDataButton

                    // Debug (7-tap easter egg)
                    #if DEBUG
                    debugCard
                    #endif
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 40)
                .responsiveContent()
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(alignment: .top) {
                HomeHillScene(tier: .calm, crestFromSafeTop: 196)
            }
            .toolbar(.hidden, for: .navigationBar)
            .tint(Self.mint)
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showingDebugFocusSetup) {
                FocusModeSetupView()
            }
            .sheet(isPresented: $showingFocusSettings) {
                FocusModeSettingsView()
            }
            .manageSubscriptionsSheet(isPresented: $showingManageSubscriptions)
            .alert(restoreMessage ?? "", isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .alert("Reset All Data", isPresented: $showingResetConfirmation) {
                Button("Reset Everything", role: .destructive) { resetAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes your games, scores, streak and name, stops blocking your apps and clears your Focus schedule. Your subscription stays. Scores already on Game Center can't be removed.")
            }
            .alert("Load Screenshot Data", isPresented: $showingScreenshotDataConfirmation) {
                Button("Load Demo Data", role: .destructive) { loadScreenshotData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This replaces ALL your data with demo data for App Store screenshots. Your real progress will be lost.")
            }
        }
    }

    // MARK: - 1. Player Card Hero


    // MARK: - 2. Stats Grid






    // MARK: - 4. Pro Card


    // MARK: - 5. Settings Section

    /// Title and a close button, in Profile's style.
    private var header: some View {
        HStack {
            Text("Settings")
                .font(.brand(size: 30, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Self.ink)
                    .frame(width: 40, height: 40)
                    .background(.white, in: Circle())
                    .overlay(Circle().strokeBorder(Self.ink, lineWidth: 2.5))
                    .background(Circle().fill(Self.ink).offset(y: 3))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .accessibilityAddTraits(.isHeader)
    }

    /// A titled group of rows.
    private func section<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.brand(size: 15, weight: .heavy))
                .foregroundStyle(.white.opacity(0.8))
                .shadow(color: .black.opacity(0.35), radius: 4)
                .padding(.leading, 6)
            VStack(spacing: 0) { rows() }
                .background(Color(red: 0, green: 0.086, blue: 0.11).opacity(0.42), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.leading, 62)
    }

    private func rowIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 36, height: 36)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }

    private func rowTitle(_ title: String) -> some View {
        Text(title)
            .font(.brand(size: 16, weight: .heavy))
            .foregroundStyle(.white)
    }

    private func rowValue(_ text: String) -> some View {
        Text(text)
            .font(.brand(size: 15, weight: .bold))
            .foregroundStyle(Self.mint)
    }

    private var rowChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white.opacity(0.45))
    }

    private var nameRow: some View {
        settingsRow(icon: "person.fill", color: AppColors.accent, title: "Name") {
            if editingName {
                TextField("Your name", text: $editedName)
                    .font(.brand(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
                    .submitLabel(.done)
                    .onSubmit {
                        user?.username = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                        editingName = false
                    }
            } else {
                Button {
                    editedName = user?.username ?? ""
                    editingName = true
                } label: {
                    rowValue(user?.username.isEmpty == false ? user!.username : "Add your name")
                }
            }
        }
    }

    /// Blocked apps and schedule: the same screen Home's Focus card opens.
    private var focusRow: some View {
        Button { showingFocusSettings = true } label: {
            settingsRow(icon: "lock.fill", color: AppColors.violet, title: "Blocked apps & schedule") {
                HStack(spacing: 6) {
                    rowValue(focusStatus)
                    rowChevron
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var focusStatus: String {
        let count = focusModeService.blockedAppCount
        guard focusModeService.isEnabled, count > 0 else { return "Off" }
        return count == 1 ? "1 app" : "\(count) apps"
    }

    @ViewBuilder
    private var preferencesRows: some View {
        settingsRow(icon: "bell.fill", color: AppColors.coral, title: "Notifications") {
            if let user {
                Toggle("Notifications", isOn: Binding(
                    get: { user.notificationsEnabled },
                    set: { newValue in
                        user.notificationsEnabled = newValue
                        if newValue {
                            Task {
                                let granted = await NotificationService.shared.requestPermission()
                                if granted {
                                    NotificationService.shared.scheduleDailyReminder(
                                        hour: user.reminderHour,
                                        minute: user.reminderMinute,
                                        streak: user.currentStreak
                                    )
                                } else {
                                    user.notificationsEnabled = false
                                }
                            }
                        } else {
                            NotificationService.shared.cancelReminders()
                        }
                    }
                ))
                .tint(Self.mint)
                .labelsHidden()
            }
        }
        rowDivider
        settingsRow(icon: "speaker.wave.2.fill", color: AppColors.teal, title: "Sounds") {
            if let user {
                Toggle("Sounds", isOn: Binding(
                    get: { soundOn },
                    set: { soundOn = $0; user.soundEnabled = $0 }
                ))
                .tint(Self.mint)
                .labelsHidden()
            }
        }
    }

    /// Signed in, or a button to sign in: rankings on Compete and after each game need it.
    private var gameCenterRow: some View {
        settingsRow(icon: "gamecontroller.fill", color: AppColors.mint, title: "Game Center") {
            if gameCenterService.isAuthenticated {
                Label("Signed in", systemImage: "checkmark.circle.fill")
                    .font(.brand(size: 15, weight: .bold))
                    .foregroundStyle(Self.mint)
            } else {
                Button("Sign in") { gameCenterService.authenticate() }
                    .font(.brand(size: 15, weight: .heavy))
                    .foregroundStyle(Self.mint)
            }
        }
    }

    @ViewBuilder
    private var subscriptionRows: some View {
        if isProUser {
            aboutRow(icon: "creditcard.fill", color: .blue, title: "Manage subscription", isLink: true) {
                showingManageSubscriptions = true
            }
            rowDivider
        }
        aboutRow(icon: "arrow.clockwise", color: .teal, title: "Restore purchases", isLink: true) {
            Task {
                let restored = await storeService.restorePurchases()
                restoreMessage = restored ? "Purchases restored." : "No purchases to restore on this Apple ID."
            }
        }
    }

    private func settingsRow<Trailing: View>(icon: String, color: Color, title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            rowIcon(icon)
            rowTitle(title)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - About

    @ViewBuilder
    private var aboutRows: some View {
        Button {
            if let url = URL(string: "itms-apps://itunes.apple.com/app/id6760178716?action=write-review") {
                UIApplication.shared.open(url)
            }
        } label: {
            linkRowLabel(icon: "star.fill", color: .orange, title: "Rate Memo")
        }
        .buttonStyle(.plain)
        rowDivider
        Link(destination: URL(string: "https://getmemoriapp.com/privacy")!) {
            linkRowLabel(icon: "hand.raised.fill", color: .purple, title: "Privacy Policy")
        }
        .buttonStyle(.plain)
        rowDivider
        Link(destination: URL(string: "https://getmemoriapp.com/terms")!) {
            linkRowLabel(icon: "doc.text.fill", color: .gray, title: "Terms of Use")
        }
        .buttonStyle(.plain)
        rowDivider
        aboutRow(icon: "info.circle.fill", color: .gray, title: "Version", trailing: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            #if DEBUG
            .onTapGesture { debugTapCount += 1 }
            #endif
    }

    private func linkRowLabel(icon: String, color: Color, title: String) -> some View {
        HStack(spacing: 12) {
            rowIcon(icon)
            rowTitle(title)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func aboutRow(icon: String, color: Color, title: String, trailing: String? = nil, isLink: Bool = false, action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                rowIcon(icon)
                rowTitle(title)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.brand(size: 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                } else if isLink {
                    rowChevron
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(action != nil)
    }

    // MARK: - 7. Reset Data Button

    private var resetDataButton: some View {
        Button {
            showingResetConfirmation = true
        } label: {
            Text("Reset All Data")
                .font(.brand(size: 15, weight: .heavy))
                .foregroundStyle(Color(red: 1, green: 0.5, blue: 0.5))
        }
        .padding(.top, 8)
    }

    // MARK: - Debug (hidden behind 7-tap on version)

    @ViewBuilder
    private var debugCard: some View {
        #if DEBUG
        if debugTapCount >= 7 {
            debugCardContent
        }
        #else
        EmptyView()
        #endif
    }

    private var debugCardContent: some View {
        #if DEBUG
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Debug")

            // Pro toggle
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(AppColors.amber, in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Debug Membership")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(storeService.isProUser ? "Full access ON — tap to disable" : "Full access OFF — tap to enable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Circle()
                    .fill(storeService.isProUser ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 12, height: 12)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                storeService.isProUser.toggle()
            }

            // Reset onboarding
            debugRow(icon: "arrow.counterclockwise.circle.fill", color: .orange, title: "Reset Onboarding", subtitle: "Re-show onboarding on next launch") {
                if let user {
                    user.hasCompletedOnboarding = false
                }
            }

            // Set mascot mood
            debugRow(icon: "face.smiling.fill", color: AppColors.teal, title: "Memo Happy", subtitle: "Add 3 exercises today") {
                if let user {
                    user.lastSessionDate = Date()
                    for _ in 0..<3 {
                        let ex = Exercise(type: .reactionTime, difficulty: 1, score: 50, durationSeconds: 30)
                        modelContext.insert(ex)
                    }
                }
            }

            debugRow(icon: "face.smiling.inverse", color: AppColors.amber, title: "Memo Neutral", subtitle: "Clear today's exercises") {
                if let user {
                    user.lastSessionDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())
                }
                // Delete today's exercises so todayExerciseCount = 0
                let startOfDay = Calendar.current.startOfDay(for: Date())
                let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.completedAt >= startOfDay })
                if let todayExercises = try? modelContext.fetch(descriptor) {
                    for ex in todayExercises { modelContext.delete(ex) }
                }
            }

            debugRow(icon: "face.dashed.fill", color: AppColors.coral, title: "Memo Sad", subtitle: "Clear exercises + set 3 days ago") {
                if let user {
                    user.lastSessionDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())
                }
                let startOfDay = Calendar.current.startOfDay(for: Date())
                let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.completedAt >= startOfDay })
                if let todayExercises = try? modelContext.fetch(descriptor) {
                    for ex in todayExercises { modelContext.delete(ex) }
                }
            }

            // Focus Mode — reset setup
            debugRow(icon: "shield.fill", color: AppColors.violet, title: "Reset Focus Mode", subtitle: "Clear Focus Mode setup + onboarding flag") {
                UserDefaults.standard.removeObject(forKey: "has_seen_free_play_popup")
                let shared = UserDefaults(suiteName: "group.com.memori.shared")
                shared?.removeObject(forKey: "focus_mode_enabled")
                shared?.removeObject(forKey: "focus_activity_selection")
                shared?.removeObject(forKey: "focus_unlock_duration")
                shared?.removeObject(forKey: "focus_schedule_enabled")
                shared?.removeObject(forKey: "focus_daily_attempt_count")
                shared?.removeObject(forKey: "focus_cooldown_until")
                shared?.removeObject(forKey: "focus_unlock_until")
            }

            // Focus Mode — show setup flow
            debugRow(icon: "shield.lefthalf.filled", color: AppColors.violet, title: "Focus Mode Setup", subtitle: "Open Focus Mode setup flow") {
                showingDebugFocusSetup = true
            }

            // Load screenshot data
            Button {
                showingScreenshotDataConfirmation = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 7))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Load Screenshot Data")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Fills app with demo data for App Store screenshots")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if screenshotDataLoaded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .appCard()
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.accent.opacity(0.3), lineWidth: 1)
        )
        #else
        EmptyView()
        #endif
    }

    // Debug row helper
    private func debugRow(icon: String, color: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color, in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture { action() }
    }

    private func loadScreenshotData() {
        #if DEBUG
        guard let user else { return }
        ScreenshotDataGenerator.generate(modelContext: modelContext, user: user, gameCenterService: gameCenterService)
        screenshotDataLoaded = true
        #endif
    }

    // MARK: - Reset

    private func resetAllData() {
        do {
            try modelContext.delete(model: Exercise.self)
            try modelContext.delete(model: SpacedRepetitionCard.self)
            try modelContext.delete(model: DailySession.self)
            try modelContext.delete(model: BrainScoreResult.self)
            try modelContext.delete(model: Achievement.self)
            if let user {
                user.currentStreak = 0
                user.longestStreak = 0
                user.lastSessionDate = nil
                user.streakFreezes = 1
                user.streakFreezeUsedDate = nil
                user.streakFreezeLastAwardDate = nil
                user.totalXP = 0
                user.level = 1
                user.totalExercises = 0
                user.totalPerfectScores = 0
            }
            if let user {
                user.username = ""
                user.soundEnabled = true
            }
            soundOn = true
            NotificationService.shared.cancelReminders()
            focusModeService.resetAll()
            PersonalBestTracker.shared.resetAll()
            AdaptiveDifficultyEngine.shared.resetAll()
            ProgressReset.clear(standard: .standard, shared: UserDefaults(suiteName: "group.com.memori.shared") ?? .standard)
            WidgetDataService.updateWidgetData(streak: 0, exercisesToday: 0, trainedToday: false)
        } catch {
            // Silent fail — data will be inconsistent but app won't crash
        }
    }
}

