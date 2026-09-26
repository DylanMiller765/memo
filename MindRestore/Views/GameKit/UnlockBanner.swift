import SwiftUI
import FamilyControls
import ManagedSettings

enum BlockedAppTokenStore {
    static let key = "unlock_last_app_token"
    static func load() -> ApplicationToken? {
        guard let data = UserDefaults(suiteName: "group.com.memori.shared")?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ApplicationToken.self, from: data)
    }
}

struct BlockedAppIcon: View {
    var size: CGFloat = 30
    var showLock = true
    var unlocked = false
    @State private var token: ApplicationToken? = BlockedAppTokenStore.load()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let token {
                    Label(token).labelStyle(.iconOnly).scaleEffect(size / 30)
                } else if Self.screenshotStandIn {
                    Image("logo-tiktok").resizable().scaledToFill()
                } else {
                    Image(systemName: "app.fill").font(.system(size: size * 0.6, weight: .bold)).foregroundStyle(OB.fg2)
                }
            }
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(.black))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).strokeBorder(.white.opacity(0.22)))
            if showLock {
                Image(systemName: unlocked ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: size * 0.36, weight: .black))
                    .foregroundStyle(unlocked ? OB.success : OB.amber)
                    .offset(x: size * 0.18, y: size * 0.18)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .accessibilityLabel(unlocked ? "App unlocked" : "App locked")
    }

    /// Simulators have no FamilyControls token, so marketing captures show TikTok instead of a blank tile.
    private static var screenshotStandIn: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--screenshot-mode")
        #else
        false
        #endif
    }
}

struct UnlockBanner: View {
    let progress: BannerProgress
    let minutesLabel: String       // "5 min", "10 min ✓", "MAX", "≤400ms"
    let isUnlocked: Bool
    var overtime = false

    var body: some View {
        HStack(spacing: 10) {
            BlockedAppIcon(size: 30, showLock: true, unlocked: isUnlocked)
            HStack(spacing: progress.total > 12 ? 2 : 3) {
                ForEach(0..<min(progress.total, 16), id: \.self) { index in
                    Capsule()
                        .fill(index < scaledFilled ? (overtime ? OB.amber : OB.accent) : .white.opacity(0.14))
                        .shadow(color: index < scaledFilled ? (overtime ? OB.amber : OB.accent).opacity(0.6) : .clear, radius: 4)
                        .frame(height: 8)
                }
            }
            .animation(.spring(duration: 0.3), value: progress)
            Text(minutesLabel)
                .font(.brand(size: 13, weight: .heavy))
                .foregroundStyle(isUnlocked ? OB.success : OB.fg)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(isUnlocked ? OB.success.opacity(0.16) : .white.opacity(0.08)))
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(minutesLabel), \(progress.filled) of \(progress.total)")
    }

    private var scaledFilled: Int {
        guard progress.total > 16 else { return progress.filled }
        return Int((Double(progress.filled) / Double(progress.total) * 16).rounded())
    }
}
