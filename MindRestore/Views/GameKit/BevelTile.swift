import SwiftUI

enum BevelState: Equatable { case idle, lit, correct, wrong }

struct BevelTile<Label: View>: View {
    let state: BevelState
    var tint: Color = OB.accent
    var cornerRadius: CGFloat = 12
    @ViewBuilder var label: () -> Label

    init(state: BevelState, tint: Color = OB.accent, cornerRadius: CGFloat = 12, @ViewBuilder label: @escaping () -> Label) {
        self.state = state; self.tint = tint; self.cornerRadius = cornerRadius; self.label = label
    }

    private var fill: Color {
        switch state {
        case .idle: Color(red: 0.11, green: 0.12, blue: 0.21)
        case .lit: tint
        case .correct: OB.success
        case .wrong: OB.coral
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [fill.opacity(state == .idle ? 1 : 0.92), fill], startPoint: .top, endPoint: .bottom))
            shape.strokeBorder(.white.opacity(state == .idle ? 0.06 : 0.45), lineWidth: 1).mask(
                LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
            shape.fill(.black.opacity(state == .idle ? 0.35 : 0.22))
                .mask(LinearGradient(colors: [.clear, .clear, .white], startPoint: .top, endPoint: .bottom))
            label()
        }
        .shadow(color: state == .idle ? .clear : fill.opacity(0.6), radius: 10)
        .animation(.easeOut(duration: 0.18), value: state)
        .accessibilityAddTraits(state == .correct ? .isSelected : [])
    }
}

extension BevelTile where Label == EmptyView {
    init(state: BevelState, tint: Color = OB.accent, cornerRadius: CGFloat = 12) {
        self.init(state: state, tint: tint, cornerRadius: cornerRadius) { EmptyView() }
    }
}
