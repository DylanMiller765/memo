import SwiftUI

struct GameScaffold<Content: View>: View {
    let mode: GameMode
    let trainTitle: String
    var trainBest: String?
    var bannerLabel: (UnlockRun) -> String = { run in
        let p = run.progress
        if p.isMaxed { return "MAX" }
        if run.game == .reactionTime { return "≤\(UnlockRulebook.threshold(.pass, for: .reactionTime))ms" }
        let banked = run.bankedTier >= .pass
        return banked ? "\(run.liveMinutes) min ✓" : "\(UnlockRulebook.minutes(for: .pass, isPersonalBest: false)) min"
    }
    var glow: Color = Color(red: 0.086, green: 0.094, blue: 0.227)
    /// Replaces the glow backdrop with a full-bleed surface drawn under the banner (Reaction Time).
    var backdrop: AnyView?
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            if let backdrop { backdrop.ignoresSafeArea() } else { GameBackdrop(glow: glow) }
            VStack(spacing: 0) {
                header.padding(.horizontal, 16).padding(.top, 8)
                content().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var header: some View {
        if let run = mode.run {
            HStack(spacing: 8) {
                UnlockBanner(progress: run.progress, minutesLabel: bannerLabel(run),
                             isUnlocked: run.bankedTier >= .pass, overtime: run.phase == .overtime)
                // Leaving mid-run: DENIED before the pass line, cash out after it.
                Button { run.abandon() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(OB.fg3)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(OB.surface.opacity(0.8)))
                }
                .accessibilityLabel("Leave game")
            }
        } else {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(OB.fg2)
                        .frame(width: 36, height: 36).background(Circle().fill(OB.surface))
                }
                .accessibilityLabel("Close")
                Spacer()
                Text(trainTitle).font(.brand(size: 16, weight: .bold)).foregroundStyle(OB.fg)
                Spacer()
                Text(trainBest.map { "Best \($0)" } ?? " ")
                    .font(.brand(size: 13, weight: .semibold)).foregroundStyle(OB.fg2)
                    .frame(minWidth: 36, alignment: .trailing)
            }
        }
    }
}
