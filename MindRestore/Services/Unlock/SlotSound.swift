import AVFoundation

/// Slot-machine sounds. `.ambient` respects the silent switch and mixes with
/// whatever else is playing; every other screen in the app stays silent.
enum SlotSound {
    private static var players: [String: AVAudioPlayer] = [:]
    private static var configured = false

    static func tick() { play("slot-tick", volume: 0.55) }
    static func lock() { play("slot-lock", volume: 0.8) }
    static func chime() { play("slot-chime", volume: 0.9) }

    private static func play(_ name: String, volume: Float) {
        if !configured {
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
