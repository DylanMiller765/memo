import SwiftUI

enum InkColor: String, CaseIterable {
    case red, blue, green, yellow, purple

    var color: Color {
        switch self {
        case .red: Color(red: 1.0, green: 0.36, blue: 0.30)
        case .blue: Color(red: 0.42, green: 0.60, blue: 1.0)
        case .green: Color(red: 0.24, green: 0.86, blue: 0.52)
        case .yellow: Color(red: 1.0, green: 0.80, blue: 0.25)
        case .purple: Color(red: 0.72, green: 0.45, blue: 1.0)
        }
    }

    var label: String { rawValue.uppercased() }
}

struct StroopPrompt: Equatable {
    let word: InkColor
    let ink: InkColor
    let choices: [InkColor]
}

enum ColorMatchEngine {
    static let qualifyCount = 10

    static func prompt<R: RandomNumberGenerator>(completed: Int, previous: StroopPrompt?, using rng: inout R) -> StroopPrompt {
        let palette: [InkColor] = completed < qualifyCount ? [.red, .blue, .green, .yellow] : InkColor.allCases
        let congruentChance = completed < qualifyCount ? 0.15 : 0.08
        while true {
            let ink = palette.randomElement(using: &rng)!
            let word: InkColor = Double.random(in: 0..<1, using: &rng) < congruentChance
                ? ink
                : palette.filter { $0 != ink }.randomElement(using: &rng)!
            let candidate = StroopPrompt(word: word, ink: ink, choices: palette)
            if candidate != previous { return candidate }
        }
    }
}
