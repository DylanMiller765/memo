import SwiftUI

/// Full-width game-style button: bright face, dark outline, and a dark "floor"
/// the face sinks into when pressed.
struct ChunkyButton: View {
    enum Style { case white, amber }

    let title: String
    var systemImage: String? = "play.fill"
    var style: Style = .white
    let action: () -> Void

    var body: some View {
        Button {
            HapticService.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .heavy))
                }
                Text(title)
                    .font(.brand(size: 17, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(ChunkyButtonPressStyle.ink)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ChunkyButtonPressStyle(face: style == .amber ? Color(red: 1, green: 0.827, blue: 0.42) : .white))
    }
}

private struct ChunkyButtonPressStyle: ButtonStyle {
    static let ink = Color(red: 0.043, green: 0.106, blue: 0.133) // #0B1B22

    let face: Color

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        configuration.label
            .frame(height: 54)
            .frame(maxWidth: .infinity)
            .background(shape.fill(face))
            .overlay(shape.strokeBorder(Self.ink, lineWidth: 2.5))
            .offset(y: configuration.isPressed ? 4 : 0)
            .background(shape.fill(Self.ink).offset(y: 5))
            .padding(.bottom, 5)
            .contentShape(shape)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: 20) {
        ChunkyButton(title: "Spin for your pass") {}
        ChunkyButton(title: "Cheer Memo up", style: .amber) {}
    }
    .padding(20)
    .background(Color(red: 0, green: 0.17, blue: 0.2))
}
