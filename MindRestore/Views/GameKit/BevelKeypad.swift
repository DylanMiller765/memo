import SwiftUI

struct AnswerBoxes: View {
    let entry: String
    let length: Int
    var tint: Color = OB.accent
    var flash: BevelState = .idle

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 8
            let box = min(44, (geo.size.width - spacing * CGFloat(max(0, length - 1))) / CGFloat(max(1, length)))
            HStack(spacing: spacing) {
                ForEach(0..<length, id: \.self) { index in
                    let chars = Array(entry)
                    let isFocus = index == chars.count
                    RoundedRectangle(cornerRadius: box * 0.28, style: .continuous)
                        .fill(flash == .correct ? OB.success.opacity(0.25) : flash == .wrong ? OB.coral.opacity(0.25) : OB.surface)
                        .overlay(RoundedRectangle(cornerRadius: box * 0.28, style: .continuous)
                            .strokeBorder(isFocus ? tint : .white.opacity(0.12), lineWidth: 1.5))
                        .shadow(color: isFocus ? tint.opacity(0.5) : .clear, radius: 8)
                        .overlay(Text(index < chars.count ? String(chars[index]) : "")
                            .font(HeroNumber.font(box * 0.62)).foregroundStyle(OB.fg))
                        .frame(width: box, height: box * 1.25)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Answer \(entry.isEmpty ? "empty" : entry)")
    }
}

struct BevelKeypad: View {
    let onDigit: (Int) -> Void
    let onDelete: () -> Void

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(1...9, id: \.self) { key($0) }
            Button(action: { HapticService.tap(); onDelete() }) {
                keyFace { Image(systemName: "delete.left.fill").font(.system(size: 20, weight: .bold)) }
                    .opacity(0.7)
            }
            .buttonStyle(KeyPressStyle())
            .accessibilityLabel("Delete")
            key(0)
            Color.clear.frame(height: 52)
        }
    }

    private func key(_ digit: Int) -> some View {
        Button(action: { HapticService.tap(); onDigit(digit) }) {
            keyFace { Text("\(digit)").font(HeroNumber.font(24)) }
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel("\(digit)")
    }

    private func keyFace<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .foregroundStyle(OB.fg)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.14, green: 0.15, blue: 0.25), Color(red: 0.10, green: 0.11, blue: 0.19)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.07)))
                    .shadow(color: .black.opacity(0.45), radius: 0, y: 3)
            )
    }
}

private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 2 : 0)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
