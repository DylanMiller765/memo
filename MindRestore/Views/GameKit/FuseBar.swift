import SwiftUI

struct FuseFloat: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let positive: Bool
}

struct FuseBar: View {
    let fraction: Double
    var overtime = false
    var floatText: FuseFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownFloat: FuseFloat?

    private var fill: LinearGradient {
        let low = fraction < 0.25
        let colors: [Color] = overtime || low ? [OB.coral, OB.amber] : [OB.accent, Color(red: 0.56, green: 0.69, blue: 1.0)]
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08))
                Capsule().fill(fill).frame(width: max(14, geo.size.width * fraction))
                    .animation(reduceMotion ? nil : .linear(duration: 0.1), value: fraction)
            }
        }
        .frame(height: 14)
        .overlay(alignment: .trailing) {
            if let shownFloat {
                Text(shownFloat.text)
                    .font(HeroNumber.font(20))
                    .foregroundStyle(shownFloat.positive ? OB.success : OB.coral)
                    .offset(y: -26)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
        }
        .onChange(of: floatText) { _, new in
            guard let new else { return }
            withAnimation(.spring(duration: 0.3)) { shownFloat = new }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                if shownFloat == new { withAnimation(.easeOut(duration: 0.2)) { shownFloat = nil } }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Time left")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

