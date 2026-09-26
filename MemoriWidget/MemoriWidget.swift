import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct MemoriWidgetEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let exercisesToday: Int
    let trainedToday: Bool
}

// MARK: - Timeline Provider

struct MemoriTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> MemoriWidgetEntry {
        MemoriWidgetEntry(date: .now, streak: 7, exercisesToday: 2, trainedToday: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (MemoriWidgetEntry) -> Void) {
        completion(entry(from: WidgetDataService.currentSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MemoriWidgetEntry>) -> Void) {
        let current = entry(from: WidgetDataService.currentSnapshot())
        // Refresh once per hour or when the app calls reloadAllTimelines
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [current], policy: .after(nextUpdate)))
    }

    private func entry(from snap: WidgetDataService.Snapshot) -> MemoriWidgetEntry {
        MemoriWidgetEntry(date: .now, streak: snap.streak, exercisesToday: snap.exercisesToday, trainedToday: snap.trainedToday)
    }
}

// MARK: - Widget Colors (standalone, no dependency on main app DesignSystem)

private enum WidgetColors {
    static let bg = Color(red: 0.039, green: 0.039, blue: 0.059)
    static let flameTop = Color(red: 1.0, green: 0.76, blue: 0.28)
    static let flameBottom = Color(red: 0.98, green: 0.42, blue: 0.35)
    static let success = Color(red: 0.0, green: 0.82, blue: 0.62)
    static let muted = Color.white.opacity(0.45)
}

private struct StreakFlame: View {
    let streak: Int
    let size: CGFloat
    var body: some View {
        Image(systemName: streak > 0 ? "flame.fill" : "flame")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(
                streak > 0
                    ? LinearGradient(colors: [WidgetColors.flameTop, WidgetColors.flameBottom], startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [WidgetColors.muted, WidgetColors.muted], startPoint: .top, endPoint: .bottom)
            )
    }
}

private struct TodayLine: View {
    let entry: MemoriWidgetEntry
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: entry.trainedToday ? "checkmark.circle.fill" : "circle")
            Text(entry.trainedToday ? "\(entry.exercisesToday) today" : "Train today")
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(entry.trainedToday ? WidgetColors.success : WidgetColors.muted)
    }
}

// MARK: - Small Widget View

struct MemoriSmallWidgetView: View {
    let entry: MemoriWidgetEntry

    var body: some View {
        VStack(spacing: 4) {
            StreakFlame(streak: entry.streak, size: 28)
            Text("\(entry.streak)")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
            Text("day streak")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetColors.muted)
            TodayLine(entry: entry)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(WidgetColors.bg, for: .widget)
        .widgetURL(URL(string: "memori://train")!)
    }
}

// MARK: - Medium Widget View

struct MemoriMediumWidgetView: View {
    let entry: MemoriWidgetEntry

    var body: some View {
        HStack(spacing: 18) {
            VStack(spacing: 2) {
                StreakFlame(streak: entry.streak, size: 34)
                Text("\(entry.streak)")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                Text("day streak")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetColors.muted)
            }
            .frame(width: 104)

            VStack(alignment: .leading, spacing: 10) {
                Text(entry.trainedToday ? "Brain trained today." : "No feed til you train.")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                TodayLine(entry: entry)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(WidgetColors.bg, for: .widget)
        .widgetURL(URL(string: "memori://train")!)
    }
}

// MARK: - Widget Entry View

struct MemoriWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: MemoriWidgetEntry

    var body: some View {
        switch family {
        case .systemMedium:
            MemoriMediumWidgetView(entry: entry)
        default:
            MemoriSmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Widget Configuration

struct MemoriWidget: Widget {
    let kind = "MemoriWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MemoriTimelineProvider()) { entry in
            MemoriWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Memo")
        .description("Your streak and today's brain training.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview

#Preview("Small", as: .systemSmall) {
    MemoriWidget()
} timeline: {
    MemoriWidgetEntry(date: .now, streak: 12, exercisesToday: 2, trainedToday: true)
    MemoriWidgetEntry(date: .now, streak: 0, exercisesToday: 0, trainedToday: false)
}

#Preview("Medium", as: .systemMedium) {
    MemoriWidget()
} timeline: {
    MemoriWidgetEntry(date: .now, streak: 12, exercisesToday: 2, trainedToday: true)
}
