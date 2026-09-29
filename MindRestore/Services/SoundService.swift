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

    // The stock "Fanfare"/"Ladder" tones read as cheap; these route to Memo's own sounds.
    func playCorrect() {
        guard !isSuppressed else { return }
        GameSound.levelUp()
    }

    func playWrong() {
        guard !isSuppressed else { return }
        GameSound.wrong()
    }

    func playComplete() {
        guard !isSuppressed else { return }
        GameSound.complete()
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
