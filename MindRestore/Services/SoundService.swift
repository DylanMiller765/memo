import AudioToolbox
import Foundation

final class SoundService {
    static let shared = SoundService()

    private init() {}

    /// Onboarding and its paywall run silent: the stock system sounds read as
    /// cheap there, so those moments lean on haptics until custom audio exists.
    var isSuppressed = false

    private var isEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "soundEnabled") == nil {
            return true
        }
        return defaults.bool(forKey: "soundEnabled")
    }

    func playCorrect() {
        play(systemSoundID: 1025)
    }

    func playWrong() {
        play(systemSoundID: 1521)
    }

    func playComplete() {
        play(systemSoundID: 1026)
    }

    func playTap() {
        play(systemSoundID: 1104)
    }

    // MARK: Focus unlock slot — the one screen that earns audio.
    // System IDs for v1; custom-recorded sounds are a flagged follow-up
    // (the recordings are TikTok material).

    func playReelTick() {
        play(systemSoundID: 1104)
    }

    func playReelLock() {
        play(systemSoundID: 1103)
    }

    func playJackpotSting() {
        play(systemSoundID: 1026)
    }

    private func play(systemSoundID: SystemSoundID) {
        guard isEnabled, !isSuppressed else { return }
        AudioServicesPlaySystemSound(systemSoundID)
    }
}
