import SwiftUI

struct StreakFreezeToast: View {
    let message: String

    @State private var isShowing = false
    @State private var iconScale: CGFloat = 0.3

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppColors.sky)
                        .frame(width: 40, height: 40)

                    Image(systemName: "shield.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(iconScale)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Streak Freeze")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)

                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppColors.cardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        AppColors.sky.opacity(0.3),
                        lineWidth: 1
                    )
            )
            .padding(.horizontal, 16)
            .offset(y: isShowing ? 0 : -120)

            Spacer()
        }
        .padding(.top, 8)
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isShowing = true
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.4).delay(0.2)) {
                iconScale = 1.0
            }
        }
    }
}
