//
//  HomeHillReportViews.swift
//  FocusUnlocksReport
//
//  Home "On the hill" pieces rendered inside the report sandbox.
//  Tile styling mirrors HomeView's native Protected tile.
//

import FamilyControls
import ManagedSettings
import SwiftUI

private enum HillTile {
    static let fill = Color(red: 0, green: 0.086, blue: 0.11).opacity(0.42)
    static let border = Color.white.opacity(0.07)
    static let label = Color.white.opacity(0.72)
    static let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    static func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int((seconds / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        return String(format: "%dh %02dm", hours, minutes)
    }
}

/// Two tiles: today's Screen time and Pickups.
struct HomeStatsTilesView: View {
    let configuration: FocusHomeDashboardConfiguration

    var body: some View {
        HStack(spacing: 10) {
            tile(.clock, value: HillTile.duration(configuration.totalSeconds), label: "Screen time")
            tile(.phone, value: "\(configuration.pickups)", label: "Pickups")
        }
    }

    private func tile(_ kind: StickerKind, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            StickerIcon(kind: kind, size: 40)
            Text(value)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(HillTile.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HillTile.fill, in: HillTile.shape)
        .overlay(HillTile.shape.strokeBorder(HillTile.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Up to three of today's biggest time sinks, with minutes.
struct HomeTopOffendersView: View {
    let configuration: FocusHomeDashboardConfiguration

    var body: some View {
        VStack(spacing: 0) {
            if configuration.offenders.isEmpty {
                Text("No app time yet today")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(HillTile.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 18)
            } else {
                ForEach(Array(configuration.offenders.prefix(3).enumerated()), id: \.element.id) { index, offender in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 1)
                            .padding(.leading, 64)
                    }
                    row(offender)
                }
            }
        }
        .background(HillTile.fill, in: HillTile.shape)
        .overlay(HillTile.shape.strokeBorder(HillTile.border, lineWidth: 1))
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func row(_ offender: FocusInsightsOffender) -> some View {
        HStack(spacing: 12) {
            icon(offender.icon)
            Text(offender.name)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(HillTile.duration(offender.seconds))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func icon(_ icon: FocusInsightsOffenderIcon) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        switch icon {
        case .application(let token):
            Label(token).labelStyle(.iconOnly).frame(width: 38, height: 38).clipShape(shape)
        case .category(let token):
            Label(token).labelStyle(.iconOnly).frame(width: 38, height: 38).clipShape(shape)
        case .webDomain(let token):
            Label(token).labelStyle(.iconOnly).frame(width: 38, height: 38).clipShape(shape)
        case .fallback:
            shape.fill(Color.white.opacity(0.12)).frame(width: 38, height: 38)
                .overlay(StickerIcon(kind: .phone, size: 26))
        }
    }
}
