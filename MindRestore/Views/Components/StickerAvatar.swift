import SwiftUI

/// A player's initial in a pastel sticker circle (dark outline + floor), colored stably by name.
struct StickerAvatar: View {
    let name: String
    var size: CGFloat = 40
    var floor: CGFloat = 0
    /// Palette slot to use instead of the name's own (the podium de-duplicates neighbours).
    var paletteIndex: Int? = nil

    private static let ink = Color(red: 0.043, green: 0.106, blue: 0.133) // #0B1B22
    private static let palette: [Color] = [
        Color(red: 1, green: 0.62, blue: 0.78),     // #FF9EC7
        Color(red: 0.56, green: 0.69, blue: 1),     // #8FB0FF
        Color(red: 1, green: 0.72, blue: 0.30),     // #FFB84D
        Color(red: 0.48, green: 0.89, blue: 0.78),  // #7BE3C6
        Color(red: 0.79, green: 0.72, blue: 1),     // #C9B8FF
        Color(red: 1, green: 0.88, blue: 0.54),     // #FFE08A
        Color(red: 0.62, green: 0.90, blue: 0.63),  // #9FE6A0
    ]

    static var paletteCount: Int { palette.count }

    /// Stable palette slot for a name (FNV-1a).
    static func paletteIndex(for name: String) -> Int {
        let hash = name.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
        return Int(hash % UInt32(palette.count))
    }

    /// Palette slots for a group shown side by side: each keeps its own color unless an earlier one took it.
    static func distinctIndices(for names: [String]) -> [Int] {
        var used = Set<Int>()
        return names.map { name in
            var index = paletteIndex(for: name)
            while used.contains(index) && used.count < palette.count { index = (index + 1) % palette.count }
            used.insert(index)
            return index
        }
    }

    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        let border = max(2, size * 0.06)
        Text(initial)
            .font(.brand(size: size * 0.42, weight: .heavy))
            .foregroundStyle(Self.ink)
            .frame(width: size, height: size)
            .background(Self.palette[(paletteIndex ?? Self.paletteIndex(for: name)) % Self.palette.count], in: Circle())
            .overlay(Circle().strokeBorder(Self.ink, lineWidth: border))
            .background(Circle().fill(Self.ink).offset(y: floor))
            .accessibilityHidden(true)
    }
}

/// White heavy text with a dark sticker outline (the Home meter look), for scores and ranks.
struct OutlinedText: View {
    let text: String
    var size: CGFloat
    var outline: CGFloat = 2

    private static let ink = Color(red: 0.043, green: 0.106, blue: 0.133)

    var body: some View {
        let d = outline
        let offsets = [CGSize(width: d, height: 0), CGSize(width: -d, height: 0), CGSize(width: 0, height: d), CGSize(width: 0, height: -d),
                       CGSize(width: d * 0.75, height: d * 0.75), CGSize(width: -d * 0.75, height: -d * 0.75),
                       CGSize(width: d * 0.75, height: -d * 0.75), CGSize(width: -d * 0.75, height: d * 0.75)]
        ZStack {
            ForEach(offsets.indices, id: \.self) { i in
                Text(text).foregroundStyle(Self.ink).offset(offsets[i])
            }
            Text(text).foregroundStyle(.white)
        }
        .font(.brand(size: size, weight: .heavy))
        .monospacedDigit()
        .lineLimit(1)
        .shadow(color: .black.opacity(0.25), radius: 0, y: d * 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
