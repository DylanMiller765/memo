import SwiftUI
import FamilyControls
import ManagedSettings
import DeviceActivity

extension DeviceActivityReport.Context {
    /// Mirrors the context declared in the FocusUnlocksReport extension target.
    static let screenTime = Self("Screen Time")
    static let screenTimeWeekly = Self("Screen Time Weekly")
    static let focusHomeDashboard = Self("Focus Home Dashboard")
    static let focusInsightsReceipt = Self("Focus Insights Receipt")
    static let focusInsightsInteractive = Self("Focus Insights Interactive")
}

// MARK: - Design tokens (matches Claude Design spec for Focus Mode)

private enum FM {
    // Surface / strokes
    static let surface = Color(red: 0.078, green: 0.078, blue: 0.122)    // #14141F
    static let border = Color.white.opacity(0.06)
    static let border2 = Color.white.opacity(0.10)

    // Text
    static let fg = Color.white.opacity(0.92)
    static let fg2 = Color.white.opacity(0.55)
    static let fg3 = Color.white.opacity(0.35)

    // Brand
    static let accent = Color(red: 0.408, green: 0.565, blue: 0.996)     // #6890FE
    static let onAccent = Color(red: 0.039, green: 0.039, blue: 0.059)   // #0A0A0F
    static let memoPurple = Color(red: 0.722, green: 0.341, blue: 0.961) // #B857F5

    // Semantic
    static let speed = Color(red: 0.980, green: 0.420, blue: 0.349)      // #FA6B59 — coral / warning
    static let success = Color(red: 0.0, green: 0.820, blue: 0.620)      // #00D19E
    static let amber = Color(red: 1.0, green: 0.761, blue: 0.278)        // #FFC247
}

// MARK: - FocusModeCard

struct FocusModeCard: View {
    var previewUnlockMinutes: Int? = nil

    @Environment(FocusModeService.self) private var focusModeService
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Environment(StoreService.self) private var storeService

    @State private var showingSettings = false
    @State private var showingAppPicker = false
    @State private var showingProPaywall = false
    @State private var showingDeblockConfirm = false
    @State private var pendingLoweredSelection: FamilyActivitySelection?
    @State private var shouldArmAfterPicker = false
    @State private var previewStartedAt = Date.now

    private enum CardState { case notSetUp, idle, active, cooldown, unlocked, scheduled }
    private enum TargetListMode { case empty, locked, unlocked }

    private var currentSelectionExceedsFreeLimit: Bool {
        focusModeService.activitySelection.applicationTokens.count > 1 ||
        !focusModeService.activitySelection.categoryTokens.isEmpty ||
        !focusModeService.activitySelection.webDomainTokens.isEmpty
    }

    private var trainForPassTitle: String {
        "Spin for your pass"
    }

    private var cardState: CardState {
        if previewUnlockMinutes != nil { return .unlocked }
        if focusModeService.isTemporarilyUnlocked { return .unlocked }
        if focusModeService.isInCooldown { return .cooldown }
        if focusModeService.blockedAppCount == 0 { return .notSetUp }
        if !focusModeService.isEnabled { return .idle }
        if focusModeService.shouldShowScheduledOffNow { return .scheduled }
        return .active
    }

    var body: some View {
        // Re-evaluate state once per second so cooldown / unlock / schedule
        // transitions take effect when their deadlines pass (Date.now isn't observable on its own).
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Group {
                switch cardState {
                case .notSetUp:  notSetUpCard
                case .idle:      idleCard
                case .active:    activeCard
                case .cooldown:  cooldownCard
                case .unlocked:  unlockedCard
                case .scheduled: scheduledCard
                }
            }
        }
        // The `FM` token palette (surfaces, halos, fg opacities, glows) is composed for a dark
        // background — re-skinning each variant for light mode would compromise the cinematic feel
        // and require redoing every gradient/shadow. Pin the card to dark so it reads as a
        // deliberate "focus mode island" no matter the global appearance.
        .environment(\.colorScheme, .dark)
        .task {
            if previewUnlockMinutes == nil {
                await focusModeService.checkAuthorizationStatus()
            }
        }
        .sheet(isPresented: $showingSettings) { FocusModeSettingsView() }
        .familyActivityPicker(isPresented: $showingAppPicker, selection: Binding(
            get: { focusModeService.activitySelection },
            set: handlePickerSelection
        ))
        .onChange(of: showingAppPicker) { wasShowing, isShowing in
            guard wasShowing && !isShowing && shouldArmAfterPicker else { return }
            shouldArmAfterPicker = false
            guard focusModeService.blockedAppCount > 0 else { return }
            Task { @MainActor in
                if focusModeService.authorizationStatus != .approved {
                    await focusModeService.requestAuthorization()
                }
                if focusModeService.authorizationStatus == .approved {
                    focusModeService.enable()
                    Analytics.focusSetupCompleted()
                }
            }
        }
        .sheet(isPresented: $showingProPaywall) {
            PaywallView(triggerSource: "focus_mode_add_apps")
        }
        .sheet(isPresented: $showingDeblockConfirm) {
            DeblockConfirmSheet(
                onKeepGuard: {
                    pendingLoweredSelection = nil
                    showingDeblockConfirm = false
                },
                onLowerAnyway: {
                    if let sel = pendingLoweredSelection {
                        focusModeService.updateActivitySelection(sel)
                    }
                    pendingLoweredSelection = nil
                    showingDeblockConfirm = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(OB.bg)
        }
    }

    // MARK: - 00 · Not Set Up

    private var notSetUpCard: some View {
        flatFocusSection(
            accent: FM.accent,
            status: "Not armed",
            metric: "0",
            metricLabel: "targets blocked",
            leftTitle: "Focus Mode",
            leftValue: "Off duty",
            rightTitle: "Pass",
            rightValue: "5–20 min",
            targetMode: .empty,
            ctaTitle: "Pick targets",
            ctaAction: { showingAppPicker = true }
        )
    }

    // MARK: - 01 · Idle (off — tension)

    private var idleCard: some View {
        flatFocusSection(
            accent: FM.speed,
            status: "Off duty",
            metric: "\(focusModeService.blockedAppCount)",
            metricLabel: focusModeService.blockedAppCount == 1 ? "target ready" : "targets ready",
            leftTitle: "Focus Mode",
            leftValue: "Off duty",
            rightTitle: "Pass",
            rightValue: "5–20 min",
            targetMode: .unlocked,
            ctaTitle: "Start blocking",
            ctaAction: {
                if !storeService.isProUser && currentSelectionExceedsFreeLimit {
                    showingProPaywall = true
                } else {
                    Task { @MainActor in
                        if focusModeService.authorizationStatus != .approved {
                            await focusModeService.requestAuthorization()
                        }
                        if focusModeService.authorizationStatus == .approved {
                            focusModeService.enable()
                        }
                    }
                }
            }
        )
    }

    /// DeviceActivity filter for yesterday's data.
    private var yesterdayFilter: DeviceActivityFilter {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let yesterdayStart = cal.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: yesterdayStart, end: todayStart)),
            users: .all,
            devices: .init([.iPhone])
        )
    }

    /// Home should feel live, so this report reads today's Screen Time data.
    private var todayFilter: DeviceActivityFilter {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: todayStart, end: Date.now)),
            users: .all,
            devices: .init([.iPhone])
        )
    }

    // MARK: - 02 · Active (locked)

    private var activeCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let secondsLocked = Int(max(0, context.date.timeIntervalSince(focusModeService.currentBlockStartDate ?? context.date)))
            flatFocusSection(
                accent: FM.success,
                status: "Blocking",
                metric: fmtElapsedAdaptive(secondsLocked),
                metricLabel: "protected",
                leftTitle: "Focus Mode",
                leftValue: "Blocking",
                rightTitle: "Pass",
                rightValue: "5–20 min",
                targetMode: .locked,
                ctaTitle: trainForPassTitle,
                ctaAction: { deepLinkRouter.pendingDestination = .focusUnlock }
            )
        }
    }

    // MARK: - 03 · Cooldown

    private var cooldownCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(focusModeService.cooldownUntil?.timeIntervalSince(context.date) ?? 0))
            flatFocusSection(
                accent: FM.amber,
                status: "Resetting",
                metric: fmtMMSS(remaining),
                metricLabel: "until ready",
                leftTitle: "Focus Mode",
                leftValue: "Cooling down",
                rightTitle: "Pass",
                rightValue: "5–20 min",
                targetMode: .unlocked,
                ctaTitle: trainForPassTitle,
                ctaAction: { deepLinkRouter.pendingDestination = .focusUnlock }
            )
        }
    }

    // MARK: - 04 · Unlocked (window open)

    private var unlockedCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let previewEnd = previewUnlockMinutes.map {
                previewStartedAt.addingTimeInterval(TimeInterval($0 * 60))
            }
            let remaining = max(0, Int((previewEnd ?? focusModeService.unlockUntil)?.timeIntervalSince(context.date) ?? 0))
            flatFocusSection(
                accent: FM.speed,
                status: "Pass active",
                metric: fmtMMSS(remaining),
                metricLabel: "left",
                leftTitle: "Focus Mode",
                leftValue: "Unlocked",
                rightTitle: "Locks in",
                rightValue: fmtMMSS(remaining),
                targetMode: .unlocked,
                ctaTitle: previewUnlockMinutes == nil ? "Train for more time" : "Pass active",
                ctaAction: { deepLinkRouter.pendingDestination = .focusUnlock },
                showsCTA: previewUnlockMinutes == nil,
                secondaryActionTitle: previewUnlockMinutes == nil ? "Lock early" : nil,
                secondaryAction: previewUnlockMinutes == nil ? { focusModeService.cancelTemporaryUnlock() } : nil
            )
        }
    }

    // MARK: - 05 · Scheduled Off

    private var scheduledCard: some View {
        let resume = focusModeService.nextScheduleStart(after: .now) ?? Date.now
        let resumeLabel = formatClockTime(resume)
        let dayLabel = resumeDayLabel(for: resume)
        return VStack(alignment: .leading, spacing: 0) {
            // eyebrow + pill
            HStack {
                HStack(spacing: 8) {
                    PulsingDot(color: FM.amber, period: 2.4)
                    eyebrow("SCHEDULED", color: FM.amber)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill").font(.system(size: 9, weight: .bold))
                    Text("Off until \(resumeLabel)")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(FM.amber)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(FM.amber.opacity(0.15), in: Capsule())
            }
            .padding(.bottom, 14)

            // hero row
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(FM.amber.opacity(0.9))
                        .saturation(0.7)
                }
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Blocking starts at \(resumeLabel)")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .kerning(-0.2)
                        .foregroundStyle(FM.fg)
                    Text("Memo is off duty until your danger hours \(dayLabel).")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(FM.fg2)
                        .lineSpacing(2)
                }
                Spacer()
            }
            .padding(.bottom, 18)

            flatDivider
                .padding(.bottom, 12)

            compactScheduledTargets
                .padding(.bottom, 14)

            HStack(spacing: 10) {
                Button { showingSettings = true } label: {
                    Text("Edit schedule")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(FM.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(FM.amber, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button { focusModeService.blockNowUntilNextSchedule() } label: {
                    Text("Block now")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(FM.amber)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(FM.amber, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(
            ZStack {
                cardBackground()
                LinearGradient(colors: [FM.amber.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26))
        )
    }

    private var compactScheduledTargets: some View {
        HStack(spacing: 10) {
            blockedAppsRow(locked: false)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(focusModeService.blockedAppCount) \(focusModeService.blockedAppCount == 1 ? "target" : "targets") ready")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(FM.fg)
                Text("These block when the schedule starts.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(FM.fg2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private func eyebrow(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .tracking(1.3)
            .foregroundStyle(color)
    }

    private func flatFocusSection(
        accent: Color,
        status: String,
        metric: String,
        metricLabel: String,
        leftTitle: String,
        leftValue: String,
        rightTitle: String,
        rightValue: String,
        targetMode: TargetListMode,
        ctaTitle: String,
        ctaAction: @escaping () -> Void,
        showsCTA: Bool = true,
        secondaryActionTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let secondaryActionTitle, let secondaryAction {
                HStack {
                    Spacer()
                    Button(action: secondaryAction) {
                        Text(secondaryActionTitle)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(FM.fg2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.05), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            focusProofSection(
                fallbackLeftTitle: leftTitle,
                fallbackLeftValue: leftValue,
                fallbackRightTitle: rightTitle,
                fallbackRightValue: rightValue
            )

            flatDivider

            memoControlRow(
                accent: accent,
                status: status,
                metric: metric,
                metricLabel: metricLabel
            )

            flatDivider

            targetList(mode: targetMode)

            if showsCTA {
                ctaButton(title: ctaTitle, showArrow: true, action: ctaAction)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func focusProofSection(
        fallbackLeftTitle: String,
        fallbackLeftValue: String,
        fallbackRightTitle: String,
        fallbackRightValue: String
    ) -> some View {
        if previewUnlockMinutes != nil {
            fallbackFocusStats(
                leftTitle: fallbackLeftTitle,
                leftValue: fallbackLeftValue,
                rightTitle: fallbackRightTitle,
                rightValue: fallbackRightValue
            )
        } else {
        switch focusModeService.authorizationStatus {
        case .approved:
            DeviceActivityReport(.focusHomeDashboard, filter: todayFilter)
                .frame(height: 204)
        case .notDetermined:
            connectScreenTimeRow(title: "Connect Screen Time", subtitle: "Show today's usage and top offenders.")
        case .denied:
            fallbackFocusStats(
                leftTitle: fallbackLeftTitle,
                leftValue: fallbackLeftValue,
                rightTitle: fallbackRightTitle,
                rightValue: fallbackRightValue
            )
        @unknown default:
            fallbackFocusStats(
                leftTitle: fallbackLeftTitle,
                leftValue: fallbackLeftValue,
                rightTitle: fallbackRightTitle,
                rightValue: fallbackRightValue
            )
        }
        }
    }

    private func connectScreenTimeRow(title: String, subtitle: String) -> some View {
        Button {
            Task { await focusModeService.requestAuthorization() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(FM.accent)
                    .frame(width: 36, height: 36)
                    .background(FM.accent.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(FM.fg)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(FM.fg2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FM.fg3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func memoControlRow(accent: Color, status: String, metric: String, metricLabel: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Memo control")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(FM.fg2)
                Text(status)
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .kerning(-0.5)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(metricLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(FM.fg2)
                    .lineLimit(1)
                Text(metric)
                    .font(.system(size: metric.count > 5 ? 24 : 28, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(FM.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .contentTransition(.numericText())
            }
        }
    }

    private func fallbackFocusStats(leftTitle: String, leftValue: String, rightTitle: String, rightValue: String) -> some View {
        HStack(spacing: 0) {
            statColumn(title: leftTitle, value: leftValue)
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(FM.border2)
                .frame(width: 1, height: 42)

            statColumn(title: rightTitle, value: rightValue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 22)
        }
        .padding(.vertical, 2)
    }

    private func statColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(FM.fg2)
            Text(value)
                .font(.system(size: 25, weight: .black, design: .rounded))
                .kerning(-0.6)
                .foregroundStyle(FM.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var flatDivider: some View {
        Rectangle()
            .fill(FM.border2)
            .frame(height: 1)
    }

    private func targetList(mode: TargetListMode) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Targets")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(FM.fg)
                Spacer()
                if previewUnlockMinutes == nil && focusModeService.blockedAppCount > 0 {
                    Button {
                        if storeService.isProUser {
                            showingAppPicker = true
                        } else {
                            showingProPaywall = true
                        }
                    } label: {
                        Text(storeService.isProUser ? "Edit" : "Unlock")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(FM.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if previewUnlockMinutes != nil {
                HStack(spacing: 12) {
                    Image("logo-tiktok")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .clipShape(.rect(cornerRadius: 7))
                    Text("TikTok")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(FM.fg)
                    Spacer()
                    Text("pass")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(FM.success)
                }
            } else if focusModeService.blockedAppCount == 0 {
                Button { showingAppPicker = true } label: {
                    HStack(spacing: 12) {
                        HStack(spacing: 7) {
                            ForEach(0..<4, id: \.self) { _ in ghostSlot().frame(width: 30, height: 30) }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("No targets yet")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(FM.fg)
                            Text("Pick apps built to pull you back.")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(FM.fg2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 8) {
                    ForEach(targetRows.prefix(2)) { row in
                        targetRow(row, mode: mode)
                    }

                    if focusModeService.blockedAppCount > 2 {
                        Text("+\(focusModeService.blockedAppCount - 2) more targets")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(FM.fg3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private enum TargetRowContent {
        case application(index: Int)
        case category(index: Int)
    }

    private struct TargetRow: Identifiable {
        let id: String
        let content: TargetRowContent
    }

    private var targetRows: [TargetRow] {
        let appRows = Array(focusModeService.activitySelection.applicationTokens).enumerated().map { index, _ in
            TargetRow(
                id: "app-\(index)",
                content: .application(index: index)
            )
        }

        let categoryRows = Array(focusModeService.activitySelection.categoryTokens).enumerated().map { index, _ in
            TargetRow(
                id: "category-\(index)",
                content: .category(index: index)
            )
        }

        return appRows + categoryRows
    }

    private func targetRow(_ row: TargetRow, mode: TargetListMode) -> some View {
        HStack(spacing: 12) {
            targetRowContent(row.content)

            Spacer()

            Text(mode == .locked ? "blocked" : "pass")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(mode == .locked ? FM.speed : FM.success)
        }
    }

    @ViewBuilder
    private func targetRowContent(_ content: TargetRowContent) -> some View {
        switch content {
        case .application(let index):
            let tokens = Array(focusModeService.activitySelection.applicationTokens)
            if tokens.indices.contains(index) {
                targetTokenLabel(tokens[index])
            }
        case .category(let index):
            let tokens = Array(focusModeService.activitySelection.categoryTokens)
            if tokens.indices.contains(index) {
                targetTokenLabel(tokens[index])
            }
        }
    }

    private func targetTokenLabel(_ token: ApplicationToken) -> some View {
        HStack(spacing: 12) {
            Label(token)
                .labelStyle(.iconOnly)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Label(token)
                .labelStyle(.titleOnly)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(FM.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .scaleEffect(0.78, anchor: .leading)
        }
        .frame(height: 32, alignment: .leading)
    }

    private func targetTokenLabel(_ token: ActivityCategoryToken) -> some View {
        HStack(spacing: 12) {
            Label(token)
                .labelStyle(.iconOnly)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Label(token)
                .labelStyle(.titleOnly)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(FM.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .scaleEffect(0.78, anchor: .leading)
        }
        .frame(height: 32, alignment: .leading)
    }

    private func handlePickerSelection(_ newSelection: FamilyActivitySelection) {
        let exceedsFreeLimit = newSelection.applicationTokens.count > 1 ||
            !newSelection.categoryTokens.isEmpty ||
            !newSelection.webDomainTokens.isEmpty

        if !storeService.isProUser && exceedsFreeLimit {
            showingProPaywall = true
        } else if focusModeService.isEnabled && focusModeService.selectionLowersGuard(newSelection) {
            // Removing protection — make Memo sad before it applies.
            pendingLoweredSelection = newSelection
            showingDeblockConfirm = true
        } else {
            let isFirstSelection = focusModeService.blockedAppCount == 0
            focusModeService.updateActivitySelection(newSelection)
            if isFirstSelection && focusModeService.blockedAppCount > 0 && !focusModeService.isEnabled {
                shouldArmAfterPicker = true
            }
        }
    }

    private func statusPill(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
    }

    private func cardTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .kerning(-0.5)
            .foregroundStyle(FM.fg)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 6)
    }

    private func cardBody(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, design: .rounded))
            .foregroundStyle(FM.fg2)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 14)
    }

    private var emptyTargetsRow: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { _ in ghostSlot() }
            Spacer()
            Text("0 TARGETS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(FM.fg3)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color.white.opacity(0.10))
                )
        )
    }

    private func targetsRow(title: String, locked: Bool, showsCount: Bool, showAdd: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(FM.fg2)
                    if showAdd {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(FM.accent)
                    }
                }
                blockedAppsRow(locked: locked)
            }

            Spacer()

            if showsCount {
                Text("\(focusModeService.blockedAppCount)")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .kerning(-0.3)
                    .foregroundStyle(FM.fg)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(FM.border, lineWidth: 1))
        )
    }


    private func ctaButton(title: String, icon: String? = nil, showArrow: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 13, weight: .bold))
                }
                Text(title).font(.system(size: 15, weight: .bold, design: .rounded))
                if showArrow {
                    Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
                }
            }
            .foregroundStyle(FM.fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(FM.accent, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: FM.accent.opacity(0.30), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var focusMechanicRow: some View {
        HStack(spacing: 10) {
            mechanicStep(icon: "shield.fill", title: "Block", color: FM.accent)
            mechanicArrow
            mechanicStep(icon: "brain.head.profile", title: "Train", color: FM.memoPurple)
            mechanicArrow
            mechanicStep(icon: "lock.open.fill", title: "Unlock", color: FM.success)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.035))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(FM.border, lineWidth: 1))
        )
    }

    private func mechanicStep(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.16), in: Circle())

            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(FM.fg)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var mechanicArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(FM.fg3)
    }

    private func cardBackground(halo: Color? = nil, haloOpacity: Double = 0.0, top: CGFloat = 0) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26).fill(FM.surface)
            if let halo {
                LinearGradient(colors: [halo.opacity(haloOpacity), .clear], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
        }
    }

    private func appGlyph<Background: ShapeStyle>(_ glyph: String, bg: Background, dim: Bool) -> some View {
        Text(glyph)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(bg, in: RoundedRectangle(cornerRadius: 8))
            .opacity(dim ? 0.45 : 1)
            .saturation(dim ? 0.7 : 1)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
    }

    private func ghostSlot() -> some View {
        Text("?")
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.22))
            .frame(width: 32, height: 32)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .foregroundStyle(Color.white.opacity(0.14))
            )
    }

    /// Real app icons rendered via FamilyControls `Label(token)`. Shows actual Instagram/TikTok/etc. icons
    /// for whatever apps the user has blocked via the FamilyActivityPicker.
    private func blockedAppsRow(locked: Bool) -> some View {
        let tokens = Array(focusModeService.activitySelection.applicationTokens)
        let catTokens = Array(focusModeService.activitySelection.categoryTokens)
        let maxShown = 5
        let totalCount = tokens.count + catTokens.count
        return HStack(spacing: 6) {
            ForEach(Array(tokens.prefix(maxShown)), id: \.self) { token in
                ZStack {
                    Label(token)
                        .labelStyle(.iconOnly)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 2)
                    if locked {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(red: 0.039, green: 0.039, blue: 0.059).opacity(0.55))
                            .frame(width: 26, height: 26)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            // If user picked categories but no/few specific apps, show category tokens to fill the row
            let catSlots = max(0, maxShown - tokens.prefix(maxShown).count)
            ForEach(Array(catTokens.prefix(catSlots)), id: \.self) { token in
                ZStack {
                    Label(token)
                        .labelStyle(.iconOnly)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 2)
                    if locked {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(red: 0.039, green: 0.039, blue: 0.059).opacity(0.55))
                            .frame(width: 26, height: 26)
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            if totalCount > maxShown {
                Text("+\(totalCount - maxShown)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(FM.fg2)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    // MARK: - Computed

    private var isWithinSchedule: Bool {
        guard focusModeService.scheduleEnabled else { return true }
        let cal = Calendar.current
        let now = Date.now
        let startC = cal.dateComponents([.hour, .minute], from: focusModeService.scheduleStart)
        let endC = cal.dateComponents([.hour, .minute], from: focusModeService.scheduleEnd)
        let nowC = cal.dateComponents([.hour, .minute], from: now)
        let startMins = (startC.hour ?? 0) * 60 + (startC.minute ?? 0)
        let endMins = (endC.hour ?? 0) * 60 + (endC.minute ?? 0)
        let nowMins = (nowC.hour ?? 0) * 60 + (nowC.minute ?? 0)
        let todayWeekday = cal.component(.weekday, from: now)
        let yesterdayWeekday = ((todayWeekday - 2 + 7) % 7) + 1 // 1-based weekday for yesterday

        if startMins <= endMins {
            // same-day window
            guard focusModeService.scheduleDays.contains(todayWeekday) else { return false }
            return nowMins >= startMins && nowMins < endMins
        } else {
            // overnight window (e.g. 22:00 → 08:00):
            // - If now is past start (e.g. 23:00), it counts toward today's scheduled day.
            // - If now is before end (e.g. 03:00), it counts toward YESTERDAY's scheduled day
            //   because that's when this active interval began.
            if nowMins >= startMins {
                return focusModeService.scheduleDays.contains(todayWeekday)
            } else if nowMins < endMins {
                return focusModeService.scheduleDays.contains(yesterdayWeekday)
            }
            return false
        }
    }

    /// The next moment Focus Mode will resume blocking (when card is in `.scheduled` state).
    /// Handles three cases:
    ///   1. Same-day window (e.g. 09→17), now outside it: next start is the next scheduled `start` time.
    ///   2. Overnight window (e.g. 22→08), now in the daytime gap: next start is today at `start`.
    ///   3. Overnight active that crossed midnight but today isn't a scheduled day: returns next valid start.
    private func nextResumeDate() -> Date {
        let cal = Calendar.current
        let now = Date.now
        let startC = cal.dateComponents([.hour, .minute], from: focusModeService.scheduleStart)
        let startHour = startC.hour ?? 0
        let startMinute = startC.minute ?? 0
        let days = focusModeService.scheduleDays.isEmpty ? Set(1...7) : focusModeService.scheduleDays

        // Probe up to 8 days ahead to find the next scheduled start that's strictly in the future.
        for offset in 0..<8 {
            guard let candidateDay = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            let weekday = cal.component(.weekday, from: candidateDay)
            guard days.contains(weekday) else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: candidateDay)
            comps.hour = startHour
            comps.minute = startMinute
            guard let candidate = cal.date(from: comps), candidate > now else { continue }
            return candidate
        }
        return focusModeService.scheduleStart
    }

    /// Friendly day label for the next resume time ("today", "tomorrow", or weekday name).
    private func resumeDayLabel(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "today" }
        if cal.isDateInTomorrow(date) { return "tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return "on \(f.string(from: date))"
    }

    /// Idle subtitle. When Screen Time access is granted the stat above is real (yesterday's screen time);
    /// otherwise we fall back to the industry average and the copy reflects that.
    private var idleSubtitle: String {
        if focusModeService.authorizationStatus == .approved {
            return "yesterday. Memo's ready when you are."
        }
        return "industry average. Memo can do better."
    }

    // MARK: - Formatters

    private func fmtMMSS(_ secs: Int) -> String {
        let m = max(0, secs) / 60
        let s = max(0, secs) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func fmtHrsMin(_ secs: Int) -> String {
        let h = max(0, secs) / 3600
        let m = (max(0, secs) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    /// Headline elapsed-time format for active patrols: MM:SS until the first hour,
    /// then switches to "Xh Ym" so triple-digit minutes never display.
    private func fmtElapsedAdaptive(_ secs: Int) -> String {
        secs < 3600 ? fmtMMSS(secs) : fmtHrsMin(secs)
    }

    private func formatClockTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}

// MARK: - PulsingDot

private struct PulsingDot: View {
    let color: Color
    var period: Double = 1.6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(reduceMotion ? 0.45 : 0.8), radius: reduceMotion ? 2 : (pulse ? 6 : 2))
            .scaleEffect(reduceMotion ? 1 : (pulse ? 1.2 : 0.9))
            .opacity(reduceMotion ? 1 : (pulse ? 1 : 0.7))
            .onAppear {
                startPulseIfAllowed()
            }
            .onChange(of: reduceMotion) { _, _ in
                startPulseIfAllowed()
            }
    }

    private func startPulseIfAllowed() {
        guard !reduceMotion else {
            pulse = false
            return
        }

        withAnimation(.easeInOut(duration: period / 2).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}
