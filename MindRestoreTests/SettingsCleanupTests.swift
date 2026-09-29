import XCTest
@testable import MindRestore

final class SettingsCleanupTests: XCTestCase {
    private func freshDefaults(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testSoundIsOnUntilSomeoneTurnsItOff() {
        let d = freshDefaults("SettingsCleanupTests.sound")
        XCTAssertTrue(SoundPreference.isOn(in: d))
        d.set(false, forKey: SoundPreference.key)
        XCTAssertFalse(SoundPreference.isOn(in: d))
    }

    func testAnOldOffSwitchCarriesOverOnce() {
        let d = freshDefaults("SettingsCleanupTests.migrate")
        SoundPreference.migrate(userSoundEnabled: false, defaults: d)
        XCTAssertFalse(SoundPreference.isOn(in: d))
        // A later choice in Settings wins over the old model value.
        d.set(true, forKey: SoundPreference.key)
        SoundPreference.migrate(userSoundEnabled: false, defaults: d)
        XCTAssertTrue(SoundPreference.isOn(in: d))
    }

    func testNotificationsSwitchKeepsTheTrialReminder() {
        XCTAssertTrue(NotificationService.isReminder("daily_reminder"))
        XCTAssertTrue(NotificationService.isReminder("milestone_30"))
        XCTAssertFalse(NotificationService.isReminder("trial_reminder_selected"))
        XCTAssertFalse(NotificationService.isReminder("trial_reminder_last_day"))
    }

    func testResetClearsProgressButNotTheFreePassDay() {
        let standard = freshDefaults("SettingsCleanupTests.standard")
        let shared = freshDefaults("SettingsCleanupTests.shared")
        standard.set(true, forKey: "exercise.hasPlayed.chimpTest")
        standard.set(2, forKey: "home_charge_seen_value")
        standard.set(14, forKey: "lastCelebratedStreak")
        standard.set(true, forKey: "onboarding_completed_marker")
        shared.set(Data(), forKey: "unlock_pending_spin")
        shared.set(20260929, forKey: "unlock_free_pass_day")

        ProgressReset.clear(standard: standard, shared: shared)

        XCTAssertNil(standard.object(forKey: "exercise.hasPlayed.chimpTest"))
        XCTAssertNil(standard.object(forKey: "home_charge_seen_value"))
        XCTAssertNil(standard.object(forKey: "lastCelebratedStreak"))
        XCTAssertNotNil(standard.object(forKey: "onboarding_completed_marker"))
        XCTAssertNil(shared.object(forKey: "unlock_pending_spin"))
        XCTAssertNotNil(shared.object(forKey: "unlock_free_pass_day"))
    }
}
