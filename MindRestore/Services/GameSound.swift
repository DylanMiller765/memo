import AVFoundation

/// In-game sounds (synthesized by Scripts/synth-game-sounds.py). Each level
/// clear or correct answer in a row plays a two-note pluck one step higher on a
/// major scale (Balatro-style), so a good run climbs; a miss resets it.
enum GameSound {
    static let steps = 10
    private static var combo = 0
    private static var players: [String: AVAudioPlayer] = [:]
    private static var configured = false

    /// Call when a run starts.
    static func resetCombo() { combo = 0 }

    static func levelUp() {
        combo = min(combo + 1, steps)
        play("level-up-\(combo)", volume: 0.6)
    }

    static func wrong() {
        combo = 0
        play("wrong-soft", volume: 0.55)
    }

    static func complete() { play("game-complete", volume: 0.65) }

    private static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "soundEnabled") == nil || defaults.bool(forKey: "soundEnabled")
    }

    private static func play(_ name: String, volume: Float) {
        guard isEnabled else { return }
        if !configured {
            // Same as the slot: respects the silent switch, mixes with the user's music.
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            configured = true
        }
        let player = players[name] ?? {
            guard let url = Bundle.main.url(forResource: name, withExtension: "caf"),
                  let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
            p.prepareToPlay()
            players[name] = p
            return p
        }()
        guard let player else { return }
        player.volume = volume
        player.currentTime = 0
        player.play()
    }
}
