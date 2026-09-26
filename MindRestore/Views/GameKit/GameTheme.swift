import SwiftUI

enum GameMode {
    case train
    case unlock(UnlockRun)
    var run: UnlockRun? { if case .unlock(let run) = self { return run } else { return nil } }
}

enum HeroNumber {
    static func font(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded) }
}

extension LinearGradient {
    static func hero(_ bottom: Color) -> LinearGradient {
        LinearGradient(colors: [.white, bottom], startPoint: .top, endPoint: .bottom)
    }
}

/// Radial glow backdrop shared by every game surface.
struct GameBackdrop: View {
    var glow: Color = Color(red: 0.086, green: 0.094, blue: 0.227)
    var body: some View {
        // Opaque base: a translucent glow must never let the screen underneath show through.
        RadialGradient(colors: [glow, OB.bg], center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 520)
            .background(OB.bg)
            .ignoresSafeArea()
    }
}
