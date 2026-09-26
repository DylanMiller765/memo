import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreService.self) private var storeService
    @Environment(GameCenterService.self) private var gameCenterService
    @Query private var users: [User]

    @State private var showingPaywall = false
    @State private var showingResetConfirmation = false
    @State private var showingScreenshotDataConfirmation = false
    @State private var screenshotDataLoaded = false
    @State private var debugTapCount = 0
    @State private var showingDebugFocusSetup = false
    @State private var editingName = false
    @State private var editedName = ""
    @State private var showingAgePicker = false

    private var user: User? { users.first }
    private var isProUser: Bool { storeService.isProUser }


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Settings Section
                    settingsCard

                    // About/Legal Section
                    aboutCard

                    // Reset Data (standalone red button)
                    resetDataButton

                    // Debug (7-tap easter egg)
                    #if DEBUG
                    debugCard
                    #endif
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .responsiveContent()
                .frame(maxWidth: .infinity)
            }
            .pageBackground()
            .navigationTitle("Settings")
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showingDebugFocusSetup) {
                FocusModeSetupView()
            }
            .alert("Reset All Data", isPresented: $showingResetConfirmation) {
                Button("Reset Everything", role: .destructive) { resetAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure? This will delete all your progress, scores, and settings.")
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

    private var settingsCard: some View {
        VStack(spacing: 0) {
            // Name
            settingsRow(icon: "person.fill", color: AppColors.accent, title: "Name") {
                if editingName {
                    TextField("Your name", text: $editedName)
                        .font(.subheadline)
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
                        Text(user?.username.isEmpty == false ? user!.username : "Not set")
                            .font(.subheadline)
                            .foregroundStyle(user?.username.isEmpty == false ? .primary : .secondary)
                    }
                }
            }
            Divider().padding(.leading, 44)

            // Notifications
            settingsRow(icon: "bell.fill", color: AppColors.coral, title: "Notifications") {
                if let user {
                    Toggle("", isOn: Binding(
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
                                NotificationService.shared.cancelAll()
                            }
                        }
                    ))
                    .tint(AppColors.accent)
                    .labelsHidden()
                }
            }
            Divider().padding(.leading, 44)

            // Sounds
            settingsRow(icon: "speaker.wave.2.fill", color: AppColors.teal, title: "Sounds") {
                if let user {
                    Toggle("", isOn: Binding(
                        get: { user.soundEnabled },
                        set: { user.soundEnabled = $0 }
                    ))
                    .tint(AppColors.accent)
                    .labelsHidden()
                }
            }
            Divider().padding(.leading, 44)

            // Daily Goal
            settingsRow(icon: "target", color: AppColors.amber, title: "Daily Goal") {
                if let user {
                    Stepper("\(user.dailyGoal) games", value: Binding(
                        get: { user.dailyGoal },
                        set: { user.dailyGoal = $0 }
                    ), in: 1...10)
                    .font(.subheadline)
                }
            }
            Divider().padding(.leading, 44)

            // Your Age
            Button {
                showingAgePicker = true
            } label: {
                settingsRow(icon: "birthday.cake.fill", color: AppColors.coral, title: "Your Age") {
                    HStack(spacing: 4) {
                        Text(user?.userAge ?? 0 > 0 ? "\(user!.userAge)" : "Not set")
                            .font(.subheadline)
                            .foregroundStyle(user?.userAge ?? 0 > 0 ? .primary : .secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .appCard(padding: 0)
        .sheet(isPresented: $showingAgePicker) {
            NavigationStack {
                VStack(spacing: 16) {
                    Text("Select your age")
                        .font(.headline)

                    if let user {
                        Picker("Age", selection: Binding(
                            get: { user.userAge > 0 ? user.userAge : 25 },
                            set: { user.userAge = $0 }
                        )) {
                            ForEach(18...99, id: \.self) { age in
                                Text("\(age)").tag(age)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 150)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                        Text("Stored on your device only. Never shared.")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingAgePicker = false }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Remove") {
                            user?.userAge = 0
                            showingAgePicker = false
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func settingsRow<Trailing: View>(icon: String, color: Color, title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color, in: RoundedRectangle(cornerRadius: 7))

            Text(title)
                .font(.subheadline)

            Spacer()

            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - 6. About/Legal Section

    private var aboutCard: some View {
        VStack(spacing: 0) {
            aboutRow(icon: "info.circle.fill", color: .gray, title: "Version", trailing: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                #if DEBUG
                .onTapGesture { debugTapCount += 1 }
                #endif
            Divider().padding(.leading, 52)
            if isProUser {
                aboutRow(icon: "creditcard.fill", color: .blue, title: "Manage Subscription", isLink: true) {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                }
                Divider().padding(.leading, 52)
            }
            if isProUser {
                aboutRow(icon: "xmark.circle.fill", color: .gray, title: "How to Cancel", isLink: true) {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                }
                Divider().padding(.leading, 52)
            }
            aboutRow(icon: "arrow.clockwise", color: .teal, title: "Restore Purchases", isLink: true) {
                Task { await storeService.restorePurchases() }
            }
            Divider().padding(.leading, 52)
            Link(destination: URL(string: "https://getmemoriapp.com/privacy")!) {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.purple, in: RoundedRectangle(cornerRadius: 7))

                    Text("Privacy Policy")
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
            Divider().padding(.leading, 52)
            Link(destination: URL(string: "https://getmemoriapp.com/terms")!) {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.gray, in: RoundedRectangle(cornerRadius: 7))

                    Text("Terms of Use")
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
            Divider().padding(.leading, 52)
            Button {
                if let url = URL(string: "itms-apps://itunes.apple.com/app/id6760178716") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 7))

                    Text("Rate Memo")
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 52)
            Link(destination: URL(string: "mailto:dylanjaws@icloud.com")!) {
                HStack(spacing: 12) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 7))

                    Text("Support")
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
        }
        .appCard(padding: 0)
    }

    private func aboutRow(icon: String, color: Color, title: String, trailing: String? = nil, isLink: Bool = false, action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(color, in: RoundedRectangle(cornerRadius: 7))

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                if let trailing {
                    Text(trailing).font(.subheadline).foregroundStyle(.secondary)
                } else if isLink {
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    // MARK: - 7. Reset Data Button

    private var resetDataButton: some View {
        Button {
            showingResetConfirmation = true
        } label: {
            Text("Reset All Data")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.red)
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
            NotificationService.shared.cancelAll()
        } catch {
            // Silent fail — data will be inconsistent but app won't crash
        }
    }
}
