import SwiftUI

struct PraisePop: View {
    let text: String?
    var tint: Color = OB.accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let text {
                Text(text)
                    .font(.system(size: 44, weight: .black, design: .rounded).italic())
                    .foregroundStyle(.white)
                    .shadow(color: tint, radius: 0, x: 0, y: 4)
                    .shadow(color: tint.opacity(0.9), radius: 18)
                    .rotationEffect(.degrees(-5))
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                    .id(text)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.55), value: text)
        .allowsHitTesting(false)
        .accessibilityHidden(text == nil)
    }
}
