import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity

// MARK: - Shared UserDefaults Keys

private enum FocusKey {
    static let enabled          = "focus_mode_enabled"
    static let unlockUntil      = "focus_unlock_until"
    static let unlockDuration   = "focus_unlock_duration"
    static let scheduleEnabled  = "focus_schedule_enabled"
    static let scheduleStart    = "focus_schedule_start"
    static let scheduleEnd      = "focus_schedule_end"
    static let dailyAttemptCount = "focus_daily_attempt_count"
    static let dailyAttemptDate  = "focus_daily_attempt_date"
    static let cooldownUntil    = "focus_cooldown_until"
    static let activitySelection = "focus_activity_selection"
    static let scheduleDays     = "focus_schedule_days"
    static let manualScheduleOverrideUntil = "focus_manual_schedule_override_until"
    // Weekly blocking metric (for leaderboard)
    static let dailyMinutes     = "focus_daily_minutes"
    static let weeklyMinutes    = "focus_weekly_minutes"
    static let monthlyMinutes   = "focus_monthly_minutes"
    static let dayStart         = "focus_day_start"
    static let weekStart        = "focus_week_start"
    static let monthStart       = "focus_month_start"
    static let lastBlockStart   = "focus_last_block_start"
    static let authorizationApproved = "focus_screen_time_authorization_approved"
}

// MARK: - FocusModeService

@MainActor
@Observable
final class FocusModeService {

    // MARK: Published state

    /// Whether Focus Mode is currently active (shields applied).
    var isEnabled: Bool = false

    /// Date until which a temporary unlock is active (nil = not unlocked).
    var unlockUntil: Date?

    /// Duration in minutes for a temporary unlock (default 15).
    var unlockDuration: Int = 15

    /// Whether a schedule is active.
    var scheduleEnabled: Bool = false

    /// Schedule window start time (hour/minute only; day ignored).
    var scheduleStart: Date = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()

    /// Schedule window end time (hour/minute only; day ignored).
    var scheduleEnd: Date = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()

    /// Days of week the schedule is active (1=Sun, 7=Sat). Empty = every day.
    var scheduleDays: Set<Int> = [1, 2, 3, 4, 5, 6, 7]

    /// Temporary "block now" override while the regular schedule is currently off.
    var manualScheduleOverrideUntil: Date?

    /// Number of times the user has attempted to disable Focus Mode today.
    var dailyAttemptCount: Int = 0

    /// Date until which the disable cooldown is active (nil = no cooldown).
    var cooldownUntil: Date?

    /// The user-selected set of apps/categories to block.
    var activitySelection: FamilyActivitySelection = FamilyActivitySelection()

    /// Authorization status for FamilyControls.
    var authorizationStatus: AuthorizationStatus = .notDetermined

    // MARK: Derived state

    /// True when a temporary unlock window is currently active.
    var isTemporarilyUnlocked: Bool {
        guard let until = unlockUntil else { return false }
        return Date.now < until
    }

    /// True when the disable cooldown is still running.
    var isInCooldown: Bool {
        guard let until = cooldownUntil else { return false }
        return Date.now < until
    }

    /// Number of seconds remaining in the current temporary unlock.
    var secondsUntilRelockNeeded: TimeInterval {
        guard let until = unlockUntil, isTemporarilyUnlocked else { return 0 }
        return until.timeIntervalSinceNow
    }

    /// True when the user manually started blocking during a scheduled-off window.
    var isManualScheduleOverrideActive: Bool {
        guard let until = manualScheduleOverrideUntil else { return false }
        return Date.now < until
    }

    /// True when shields should be applied at this moment.
    var isBlockingNow: Bool {
        isEnabled && !isTemporarilyUnlocked && shouldApplyShieldsNow()
    }

    /// The start of the current contiguous shielded window, if Memo is tracking one.
    var currentBlockStartDate: Date? {
        sharedDefaults.object(forKey: FocusKey.lastBlockStart) as? Date
    }

    /// True when the UI should show the scheduled-off state instead of the blocking state.
    var shouldShowScheduledOffNow: Bool {
        Self.shouldShowScheduledOff(
            scheduleEnabled: scheduleEnabled,
            isWithinScheduledWindow: isWithinScheduledWindow(),
            manualOverrideActive: isManualScheduleOverrideActive
        )
    }

    /// Number of apps/categories currently being blocked.
    var blockedAppCount: Int {
        activitySelection.applicationTokens.count +
        activitySelection.categoryTokens.count +
        activitySelection.webDomainTokens.count
    }

    // MARK: Private

    private let sharedDefaults: UserDefaults
    private let store = ManagedSettingsStore()
    private let activityCenter = DeviceActivityCenter()
    private var relockTask: Task<Void, Never>?
    private var hasStarted = false
    private let cooldownMinutes: Int = 10
    static let focusLeagueDailyCapacityMinutes = 1_440
    static let focusLeagueWeeklyCapacityMinutes = 10_080
    private static let activityName = DeviceActivityName("com.memori.focus")
    private static let relockActivityName = DeviceActivityName("com.memori.focus.relock")

    // MARK: Init

    init() {
        sharedDefaults = UserDefaults(suiteName: "group.com.memori.shared") ?? .standard
        loadPersistedState()
        if sharedDefaults.bool(forKey: FocusKey.authorizationApproved) {
            authorizationStatus = .approved
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        hasStarted = true
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            updateAuthorizationStatus(AuthorizationCenter.shared.authorizationStatus)
            reconcileShieldState()
        } catch {
            updateAuthorizationStatus(.denied)
        }
    }

    func checkAuthorizationStatus() async {
        updateAuthorizationStatus(AuthorizationCenter.shared.authorizationStatus)
    }

    func startIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true
        await checkAuthorizationStatus()
        reconcileShieldState()
        reconcileBlockedMinutes()
    }

    func refreshForAppForeground() async {
        guard hasStarted else {
            await startIfNeeded()
            return
        }
        await checkAuthorizationStatus()
        reconcileShieldState()
        reconcileBlockedMinutes()
    }

    private func updateAuthorizationStatus(_ status: AuthorizationStatus) {
        authorizationStatus = status
        sharedDefaults.set(status == .approved, forKey: FocusKey.authorizationApproved)
    }

    // MARK: - Unlock Duration

    func setUnlockDuration(_ minutes: Int) {
        unlockDuration = minutes
        sharedDefaults.set(minutes, forKey: FocusKey.unlockDuration)
    }

    // MARK: - Activity Selection

    /// True if `selection` drops any app/category/web the user currently
    /// blocks — i.e. it lowers their guard. Adding or reorganizing returns
    /// false. Used to gate removals behind the "this hurts Memo" confirm.
    func selectionLowersGuard(_ selection: FamilyActivitySelection) -> Bool {
        let lostApps = !activitySelection.applicationTokens.isSubset(of: selection.applicationTokens)
        let lostCategories = !activitySelection.categoryTokens.isSubset(of: selection.categoryTokens)
        let lostWeb = !activitySelection.webDomainTokens.isSubset(of: selection.webDomainTokens)
        return lostApps || lostCategories || lostWeb
    }

    /// Persist a new FamilyActivitySelection chosen by the picker.
    func updateActivitySelection(_ selection: FamilyActivitySelection) {
        activitySelection = selection
        persist(selection: selection)
        if shouldApplyShieldsNow() && !isTemporarilyUnlocked {
            applyShields()
        }
    }

    // MARK: - Enable / Disable

    /// Enable Focus Mode and apply shields immediately.
    func enable() {
        isEnabled = true
        persist(bool: true, forKey: FocusKey.enabled)
        clearUnlock()
        clearCooldown()
        clearManualScheduleOverride()

        if scheduleEnabled {
            registerDeviceActivitySchedule()
            reconcileShieldState()
        } else {
            applyShields()
        }
        Analytics.focusModeEnabled()
    }

    /// Force shields on until the next scheduled blocking window starts.
    func blockNowUntilNextSchedule() {
        isEnabled = true
        persist(bool: true, forKey: FocusKey.enabled)
        clearUnlock()
        clearCooldown()

        if scheduleEnabled {
            if let nextStart = nextScheduleStart(after: .now) {
                manualScheduleOverrideUntil = nextStart
                persist(date: nextStart, forKey: FocusKey.manualScheduleOverrideUntil)
            }
            registerDeviceActivitySchedule()
        } else {
            clearManualScheduleOverride()
        }

        applyShields()
        Analytics.focusModeEnabled()
    }

    /// Disable Focus Mode (subject to cooldown).
    /// Returns false if cooldown is still active.
    @discardableResult
    func disable() -> Bool {
        if isInCooldown { return false }

        // Increment daily attempt count
        incrementDailyAttemptCount()

        // Apply cooldown
        let cooldownEnd = Date.now.addingTimeInterval(TimeInterval(cooldownMinutes * 60))
        cooldownUntil = cooldownEnd
        persist(date: cooldownEnd, forKey: FocusKey.cooldownUntil)

        isEnabled = false
        persist(bool: false, forKey: FocusKey.enabled)
        clearUnlock()
        clearManualScheduleOverride()
        removeShields()
        activityCenter.stopMonitoring([Self.activityName, Self.relockActivityName])
        Analytics.focusModeDisabled()
        Analytics.focusCooldownInitiated()
        return true
    }

    /// Reset All Data: stop blocking and forget the picked apps, schedule and
    /// counters. Screen Time permission stays; it's an iOS setting, not app data.
    func resetAll() {
        removeShields()
        activityCenter.stopMonitoring()
        for key in [FocusKey.enabled, FocusKey.unlockUntil, FocusKey.unlockDuration, FocusKey.scheduleEnabled,
                    FocusKey.scheduleStart, FocusKey.scheduleEnd, FocusKey.dailyAttemptCount, FocusKey.dailyAttemptDate,
                    FocusKey.cooldownUntil, FocusKey.activitySelection, FocusKey.scheduleDays,
                    FocusKey.manualScheduleOverrideUntil, FocusKey.dailyMinutes, FocusKey.weeklyMinutes,
                    FocusKey.monthlyMinutes, FocusKey.dayStart, FocusKey.weekStart, FocusKey.monthStart,
                    FocusKey.lastBlockStart] {
            sharedDefaults.removeObject(forKey: key)
        }
        isEnabled = false
        unlockUntil = nil
        unlockDuration = 15
        scheduleEnabled = false
        scheduleStart = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
        scheduleEnd = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
        scheduleDays = [1, 2, 3, 4, 5, 6, 7]
        manualScheduleOverrideUntil = nil
        dailyAttemptCount = 0
        cooldownUntil = nil
        activitySelection = FamilyActivitySelection()
    }

    // MARK: - Temporary Unlock

    /// Temporarily remove shields for `durationMinutes` minutes, then re-apply.
    func temporaryUnlock(durationMinutes: Int? = nil) {
        let minutes = durationMinutes ?? unlockDuration
        let unlockEnd = Date.now.addingTimeInterval(TimeInterval(minutes * 60))
        unlockUntil = unlockEnd
        persist(date: unlockEnd, forKey: FocusKey.unlockUntil)
        removeShields()
        scheduleRelock(at: unlockEnd)
        scheduleDurableRelock(at: unlockEnd)
        Analytics.focusUnlockGranted(durationMinutes: minutes)
    }

    /// Cancel an active temporary unlock and re-apply shields immediately.
    func cancelTemporaryUnlock() {
        clearUnlock()
        if shouldApplyShieldsNow() {
            applyShields()
        }
    }

    // MARK: - Shield Management

    private func applyShields() {
        store.shield.applications = activitySelection.applicationTokens.isEmpty
            ? nil
            : activitySelection.applicationTokens
        store.shield.applicationCategories = activitySelection.categoryTokens.isEmpty
            ? nil
            : ShieldSettings.ActivityCategoryPolicy.specific(activitySelection.categoryTokens)
        store.shield.webDomains = activitySelection.webDomainTokens.isEmpty
            ? nil
            : activitySelection.webDomainTokens

        beginBlockedMinutesIfNeeded()
    }

    private func removeShields() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil

        flushBlockedMinutes()
    }

    private func beginBlockedMinutesIfNeeded(at date: Date = .now) {
        rolloverFocusCountersIfNeeded()
        let start = Self.blockWindowStartToPersist(existingStart: currentBlockStartDate, now: date)
        guard currentBlockStartDate != start else { return }
        sharedDefaults.set(start, forKey: FocusKey.lastBlockStart)
    }

    /// If a block window is open, count elapsed minutes into the weekly total and report.
    @discardableResult
    private func flushBlockedMinutes(at date: Date = .now) -> Int {
        guard let start = sharedDefaults.object(forKey: FocusKey.lastBlockStart) as? Date else { return 0 }
        let elapsed = date.timeIntervalSince(start)
        let minutes = Int(elapsed / 60)
        sharedDefaults.removeObject(forKey: FocusKey.lastBlockStart)
        guard minutes > 0 else { return 0 }

        rolloverFocusCountersIfNeeded()
        let dailyUpdated = sharedDefaults.integer(forKey: FocusKey.dailyMinutes) + minutes
        let weeklyUpdated = sharedDefaults.integer(forKey: FocusKey.weeklyMinutes) + minutes
        let monthlyUpdated = sharedDefaults.integer(forKey: FocusKey.monthlyMinutes) + minutes
        sharedDefaults.set(dailyUpdated, forKey: FocusKey.dailyMinutes)
        sharedDefaults.set(weeklyUpdated, forKey: FocusKey.weeklyMinutes)
        sharedDefaults.set(monthlyUpdated, forKey: FocusKey.monthlyMinutes)
        return minutes
    }

    /// Resets Focus leaderboard counters when their current period changes.
    private func rolloverFocusCountersIfNeeded() {
        let cal = Calendar.current

        let dayStart = cal.startOfDay(for: .now)
        if let saved = sharedDefaults.object(forKey: FocusKey.dayStart) as? Date,
           cal.isDate(saved, inSameDayAs: dayStart) {
            // Same day; keep accumulating.
        } else if sharedDefaults.object(forKey: FocusKey.dayStart) == nil {
            sharedDefaults.set(dayStart, forKey: FocusKey.dayStart)
        } else {
            sharedDefaults.set(0, forKey: FocusKey.dailyMinutes)
            sharedDefaults.set(dayStart, forKey: FocusKey.dayStart)
        }

        if let weekStart = cal.dateInterval(of: .weekOfYear, for: .now)?.start {
            if let saved = sharedDefaults.object(forKey: FocusKey.weekStart) as? Date,
               cal.isDate(saved, equalTo: weekStart, toGranularity: .weekOfYear) {
                // Same week; keep accumulating.
            } else if sharedDefaults.object(forKey: FocusKey.weekStart) == nil {
                sharedDefaults.set(weekStart, forKey: FocusKey.weekStart)
            } else {
                sharedDefaults.set(0, forKey: FocusKey.weeklyMinutes)
                sharedDefaults.set(weekStart, forKey: FocusKey.weekStart)
            }
        }

        if let monthStart = cal.dateInterval(of: .month, for: .now)?.start {
            if let saved = sharedDefaults.object(forKey: FocusKey.monthStart) as? Date,
               cal.isDate(saved, equalTo: monthStart, toGranularity: .month) {
                // Same month; keep accumulating.
            } else if sharedDefaults.object(forKey: FocusKey.monthStart) == nil {
                let seedMonthlyMinutes = sharedDefaults.integer(forKey: FocusKey.monthlyMinutes)
                if seedMonthlyMinutes == 0 {
                    sharedDefaults.set(sharedDefaults.integer(forKey: FocusKey.weeklyMinutes), forKey: FocusKey.monthlyMinutes)
                }
                sharedDefaults.set(monthStart, forKey: FocusKey.monthStart)
            } else {
                sharedDefaults.set(0, forKey: FocusKey.monthlyMinutes)
                sharedDefaults.set(monthStart, forKey: FocusKey.monthStart)
            }
        }
    }

    /// Public hook — call when app foregrounds or rank UI is opened, to roll over expired sessions.
    func reconcileBlockedMinutes() {
        if isBlockingNow {
            beginBlockedMinutesIfNeeded()
        } else {
            flushBlockedMinutes()
        }
    }

    /// Current week's blocked minutes (for UI display).
    var weeklyBlockedMinutes: Int {
        rolloverFocusCountersIfNeeded()
        let stored = sharedDefaults.integer(forKey: FocusKey.weeklyMinutes)
        return Self.effectiveProtectedMinutes(storedMinutes: stored, blockStart: currentBlockStartDate, now: .now)
    }

    /// Current day's protected Focus minutes. This is app-owned time while Memo shields are active,
    /// not private Screen Time report data.
    var dailyBlockedMinutes: Int {
        rolloverFocusCountersIfNeeded()
        let stored = sharedDefaults.integer(forKey: FocusKey.dailyMinutes)
        return Self.effectiveProtectedMinutes(
            storedMinutes: stored,
            blockStart: currentBlockStartDate,
            now: .now,
            requireSameDay: true
        )
    }

    func focusLeagueProtectedMinutes(for filter: LeaderboardTimeFilter) -> Int {
        switch filter {
        case .today:
            return dailyBlockedMinutes
        case .thisWeek, .allTime:
            return weeklyBlockedMinutes
        }
    }

    func focusLeagueScore(for filter: LeaderboardTimeFilter) -> Int? {
        guard isEnabled || blockedAppCount > 0 else { return nil }
        let capacity = Self.focusLeagueCapacityMinutes(for: filter)
        let protected = min(capacity, max(0, focusLeagueProtectedMinutes(for: filter)))
        return protected > 0 ? protected : nil
    }

    static func focusLeagueCapacityMinutes(for filter: LeaderboardTimeFilter) -> Int {
        switch filter {
        case .today:
            return focusLeagueDailyCapacityMinutes
        case .thisWeek, .allTime:
            return focusLeagueWeeklyCapacityMinutes
        }
    }

    nonisolated static func blockWindowStartToPersist(existingStart: Date?, now: Date) -> Date {
        guard let existingStart, existingStart <= now else { return now }
        return existingStart
    }

    nonisolated static func effectiveProtectedMinutes(
        storedMinutes: Int,
        blockStart: Date?,
        now: Date,
        requireSameDay: Bool = false,
        calendar: Calendar = .current
    ) -> Int {
        guard let blockStart else { return storedMinutes }
        if requireSameDay && !calendar.isDate(blockStart, inSameDayAs: now) {
            return storedMinutes
        }

        let liveMinutes = Int(now.timeIntervalSince(blockStart) / 60)
        return storedMinutes + max(0, liveMinutes)
    }

    // MARK: - Relock scheduling

    private func scheduleRelock(at date: Date) {
        relockTask?.cancel()
        relockTask = Task { [weak self] in
            let delay = max(0, date.timeIntervalSinceNow)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.isEnabled else { return }
                self.clearUnlock()
                self.applyShields()
            }
        }
    }

    private func scheduleDurableRelock(at date: Date) {
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute, .second], from: date)
        let endComponents = calendar.dateComponents([.hour, .minute, .second], from: date.addingTimeInterval(60))
        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )

        do {
            activityCenter.stopMonitoring([Self.relockActivityName])
            try activityCenter.startMonitoring(Self.relockActivityName, during: schedule)
        } catch {
            // The in-app relock task remains as a fallback while the app is alive.
        }
    }

    private func stopDurableRelock() {
        activityCenter.stopMonitoring([Self.relockActivityName])
    }

    // MARK: - Schedule

    func updateScheduleDays(_ days: Set<Int>) {
        scheduleDays = days
        let array = Array(days)
        sharedDefaults.set(array, forKey: FocusKey.scheduleDays)
        if isEnabled && scheduleEnabled {
            registerDeviceActivitySchedule()
            reconcileShieldState()
        }
    }

    func updateSchedule(enabled: Bool, start: Date, end: Date) {
        clearManualScheduleOverride()
        scheduleEnabled = enabled
        scheduleStart = start
        scheduleEnd = end
        persist(bool: enabled, forKey: FocusKey.scheduleEnabled)
        persist(date: start, forKey: FocusKey.scheduleStart)
        persist(date: end, forKey: FocusKey.scheduleEnd)

        guard isEnabled else { return }

        if enabled {
            registerDeviceActivitySchedule()
            reconcileShieldState()
        } else {
            // All day mode — stop scheduled monitoring, apply shields now
            activityCenter.stopMonitoring([Self.activityName])
            if !isTemporarilyUnlocked {
                applyShields()
            }
        }
    }

    /// Register a repeating daily schedule with DeviceActivityCenter.
    ///
    /// NOTE on day-of-week filtering: `DeviceActivitySchedule` is interval-only and has no
    /// native weekday filter. We work around this by:
    ///   1. Persisting `scheduleDays` to the shared App Group defaults (already done in
    ///      `updateScheduleDays`).
    ///   2. Having `DeviceActivityMonitorExtension.intervalDidStart` read that array and
    ///      skip applying shields when today's weekday isn't selected.
    /// This keeps the day filter honored even when the host app isn't running.
    private func registerDeviceActivitySchedule() {
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: scheduleStart)
        let endComponents = calendar.dateComponents([.hour, .minute], from: scheduleEnd)

        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: true
        )

        do {
            activityCenter.stopMonitoring([Self.activityName])
            try activityCenter.startMonitoring(Self.activityName, during: schedule)
        } catch {
            // Fallback: apply shields immediately if scheduling fails
            if !isTemporarilyUnlocked {
                applyShields()
            }
        }
    }

    // MARK: - Helpers

    private func reconcileShieldState() {
        clearExpiredManualScheduleOverride()
        clearExpiredUnlock()

        if shouldApplyShieldsNow() && !isTemporarilyUnlocked {
            applyShields()
        } else if isTemporarilyUnlocked, let until = unlockUntil {
            removeShields()
            scheduleRelock(at: until)
            scheduleDurableRelock(at: until)
        } else {
            removeShields()
        }
    }

    private func incrementDailyAttemptCount() {
        let today = Date.now
        if let saved = sharedDefaults.object(forKey: FocusKey.dailyAttemptDate) as? Date,
           Calendar.current.isDateInToday(saved) {
            dailyAttemptCount += 1
        } else {
            dailyAttemptCount = 1
            persist(date: today, forKey: FocusKey.dailyAttemptDate)
        }
        sharedDefaults.set(dailyAttemptCount, forKey: FocusKey.dailyAttemptCount)
    }

    private func clearUnlock() {
        unlockUntil = nil
        sharedDefaults.removeObject(forKey: FocusKey.unlockUntil)
        relockTask?.cancel()
        relockTask = nil
        stopDurableRelock()
    }

    private func clearCooldown() {
        cooldownUntil = nil
        sharedDefaults.removeObject(forKey: FocusKey.cooldownUntil)
    }

    private func clearManualScheduleOverride() {
        manualScheduleOverrideUntil = nil
        sharedDefaults.removeObject(forKey: FocusKey.manualScheduleOverrideUntil)
    }

    private func clearExpiredManualScheduleOverride() {
        guard let until = manualScheduleOverrideUntil, until <= Date.now else { return }
        clearManualScheduleOverride()
    }

    private func clearExpiredUnlock() {
        guard let until = unlockUntil, until <= Date.now else { return }
        clearUnlock()
    }

    nonisolated static func shouldShowScheduledOff(
        scheduleEnabled: Bool,
        isWithinScheduledWindow: Bool,
        manualOverrideActive: Bool
    ) -> Bool {
        scheduleEnabled && !isWithinScheduledWindow && !manualOverrideActive
    }

    func shouldApplyShieldsNow(at date: Date = .now) -> Bool {
        guard isEnabled else { return false }
        guard scheduleEnabled else { return true }
        if isManualScheduleOverrideActive { return true }
        return isWithinScheduledWindow(at: date)
    }

    func isWithinScheduledWindow(at date: Date = .now) -> Bool {
        guard scheduleEnabled else { return true }
        let cal = Calendar.current
        let startComponents = cal.dateComponents([.hour, .minute], from: scheduleStart)
        let endComponents = cal.dateComponents([.hour, .minute], from: scheduleEnd)
        let nowComponents = cal.dateComponents([.hour, .minute], from: date)
        let startMinutes = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
        let endMinutes = (endComponents.hour ?? 0) * 60 + (endComponents.minute ?? 0)
        let nowMinutes = (nowComponents.hour ?? 0) * 60 + (nowComponents.minute ?? 0)
        let todayWeekday = cal.component(.weekday, from: date)
        let yesterdayWeekday = ((todayWeekday - 2 + 7) % 7) + 1
        let activeDays = scheduleDays.isEmpty ? Set(1...7) : scheduleDays

        if startMinutes <= endMinutes {
            guard activeDays.contains(todayWeekday) else { return false }
            return nowMinutes >= startMinutes && nowMinutes < endMinutes
        }

        if nowMinutes >= startMinutes {
            return activeDays.contains(todayWeekday)
        } else if nowMinutes < endMinutes {
            return activeDays.contains(yesterdayWeekday)
        }
        return false
    }

    func nextScheduleStart(after date: Date = .now) -> Date? {
        let cal = Calendar.current
        let startComponents = cal.dateComponents([.hour, .minute], from: scheduleStart)
        let startHour = startComponents.hour ?? 0
        let startMinute = startComponents.minute ?? 0
        let activeDays = scheduleDays.isEmpty ? Set(1...7) : scheduleDays

        for offset in 0..<8 {
            guard let candidateDay = cal.date(byAdding: .day, value: offset, to: date) else { continue }
            let weekday = cal.component(.weekday, from: candidateDay)
            guard activeDays.contains(weekday) else { continue }
            var components = cal.dateComponents([.year, .month, .day], from: candidateDay)
            components.hour = startHour
            components.minute = startMinute
            guard let candidate = cal.date(from: components), candidate > date else { continue }
            return candidate
        }

        return nil
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        isEnabled      = sharedDefaults.bool(forKey: FocusKey.enabled)
        unlockDuration = sharedDefaults.integer(forKey: FocusKey.unlockDuration).nonZeroOrDefault(15)
        scheduleEnabled = sharedDefaults.bool(forKey: FocusKey.scheduleEnabled)
        unlockUntil    = sharedDefaults.object(forKey: FocusKey.unlockUntil) as? Date
        cooldownUntil  = sharedDefaults.object(forKey: FocusKey.cooldownUntil) as? Date
        manualScheduleOverrideUntil = sharedDefaults.object(forKey: FocusKey.manualScheduleOverrideUntil) as? Date

        if let start = sharedDefaults.object(forKey: FocusKey.scheduleStart) as? Date {
            scheduleStart = start
        }
        if let end = sharedDefaults.object(forKey: FocusKey.scheduleEnd) as? Date {
            scheduleEnd = end
        }

        let savedCount = sharedDefaults.integer(forKey: FocusKey.dailyAttemptCount)
        if let savedDate = sharedDefaults.object(forKey: FocusKey.dailyAttemptDate) as? Date,
           Calendar.current.isDateInToday(savedDate) {
            dailyAttemptCount = savedCount
        } else {
            dailyAttemptCount = 0
        }

        if let savedDays = sharedDefaults.array(forKey: FocusKey.scheduleDays) as? [Int], !savedDays.isEmpty {
            scheduleDays = Set(savedDays)
        }

        if let data = sharedDefaults.data(forKey: FocusKey.activitySelection),
           let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            activitySelection = selection
        }
    }

    private func persist(bool value: Bool, forKey key: String) {
        sharedDefaults.set(value, forKey: key)
    }

    private func persist(date value: Date, forKey key: String) {
        sharedDefaults.set(value, forKey: key)
    }

    private func persist(selection: FamilyActivitySelection) {
        if let data = try? JSONEncoder().encode(selection) {
            sharedDefaults.set(data, forKey: FocusKey.activitySelection)
        }
    }
}

// MARK: - Helpers

private extension Int {
    func nonZeroOrDefault(_ fallback: Int) -> Int {
        self == 0 ? fallback : self
    }
}
