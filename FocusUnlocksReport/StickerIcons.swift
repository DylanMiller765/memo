//
//  StickerIcons.swift
//  Shared by the MindRestore app and the FocusUnlocksReport extension.
//
//  Flat "sticker" icons: bright fills, a dark #0B1B22 outline, no gradients.
//  Drawn in a 40×40 space and scaled to `size`.
//

import SwiftUI
import UIKit

enum StickerKind: String, CaseIterable {
    case clock, phone, padlock, padlockOpen, flame, house, dumbbell, trophy, chart, person, hourglass
}

struct StickerIcon: View {
    let kind: StickerKind
    var size: CGFloat = 40
    /// Grey, desaturated version (unselected tab bar items).
    var muted = false

    var body: some View {
        Canvas { ctx, canvasSize in
            ctx.scaleBy(x: canvasSize.width / 40, y: canvasSize.height / 40)
            if muted { ctx.opacity = 0.6 }
            for layer in StickerArt.layers(for: kind) {
                if let fill = layer.fill {
                    ctx.fill(layer.path, with: .color(StickerArt.color(fill, muted: muted)))
                }
                if layer.stroke > 0 {
                    ctx.stroke(
                        layer.path,
                        with: .color(StickerArt.color(layer.strokeColor, muted: muted)),
                        style: StrokeStyle(lineWidth: layer.stroke, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Renders stickers to UIImages for places that need an image (the tab bar).
@MainActor
enum StickerIconRenderer {
    private static var cache: [String: UIImage] = [:]

    static func image(_ kind: StickerKind, size: CGFloat, muted: Bool) -> UIImage {
        let key = "\(kind.rawValue)-\(size)-\(muted)"
        if let cached = cache[key] { return cached }
        let renderer = ImageRenderer(content: StickerIcon(kind: kind, size: size, muted: muted))
        renderer.scale = 3
        let image = (renderer.uiImage ?? UIImage()).withRenderingMode(.alwaysOriginal)
        cache[key] = image
        return image
    }
}

// MARK: - Art

private struct StickerLayer {
    let path: Path
    /// 0xRRGGBB, or nil for stroke-only layers.
    var fill: UInt32?
    var stroke: CGFloat = 2.6
    var strokeColor: UInt32 = StickerArt.ink
}

private enum StickerArt {
    static let ink: UInt32 = 0x0B1B22

    /// The sticker color, or its grey (luminance) when muted.
    static func color(_ value: UInt32, muted: Bool) -> Color {
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        guard muted else { return Color(red: r, green: g, blue: b) }
        return Color(white: 0.2126 * r + 0.7152 * g + 0.0722 * b)
    }

    static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, r: CGFloat = 0) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
    }

    static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    static func layers(for kind: StickerKind) -> [StickerLayer] {
        switch kind {
        case .clock: return clock
        case .phone: return phone
        case .padlock: return padlock(open: false)
        case .padlockOpen: return padlock(open: true)
        case .flame: return flame
        case .house: return house
        case .dumbbell: return dumbbell
        case .trophy: return trophy
        case .chart: return chart
        case .person: return person
        case .hourglass: return hourglass
        }
    }

    static var clock: [StickerLayer] {
        let ears = Path { p in
            p.move(to: CGPoint(x: 11, y: 7)); p.addLine(to: CGPoint(x: 7, y: 11))
            p.move(to: CGPoint(x: 29, y: 7)); p.addLine(to: CGPoint(x: 33, y: 11))
        }
        let hands = Path { p in
            p.move(to: CGPoint(x: 20, y: 15)); p.addLine(to: CGPoint(x: 20, y: 22)); p.addLine(to: CGPoint(x: 25, y: 25))
        }
        return [
            StickerLayer(path: ears),
            StickerLayer(path: circle(20, 22, 14), fill: 0xFFD36B),
            StickerLayer(path: circle(20, 22, 10), fill: 0xFFF4D2, stroke: 1.6),
            StickerLayer(path: hands),
        ]
    }

    static var phone: [StickerLayer] {
        let arcs = Path { p in
            p.move(to: CGPoint(x: 6, y: 15))
            p.addCurve(to: CGPoint(x: 6, y: 26), control1: CGPoint(x: 4, y: 18), control2: CGPoint(x: 4, y: 23))
            p.move(to: CGPoint(x: 34, y: 15))
            p.addCurve(to: CGPoint(x: 34, y: 26), control1: CGPoint(x: 36, y: 18), control2: CGPoint(x: 36, y: 23))
        }
        return [
            StickerLayer(path: arcs, stroke: 2.4),
            StickerLayer(path: rect(12, 5, 16, 30, r: 4), fill: 0xC9B8FF),
            StickerLayer(path: rect(15, 9, 10, 19, r: 1.5), fill: 0x7BE3C6, stroke: 1.5),
            StickerLayer(path: circle(20, 31, 1.4), fill: ink, stroke: 0),
        ]
    }

    static func padlock(open: Bool) -> [StickerLayer] {
        var shackle = Path { p in
            p.move(to: CGPoint(x: 13, y: 18))
            p.addLine(to: CGPoint(x: 13, y: 13))
            p.addArc(center: CGPoint(x: 20, y: 13), radius: 7, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            p.addLine(to: CGPoint(x: 27, y: 18))
        }
        if open {
            // Swing the shackle up and to the left, pivoting on the right post.
            let pivot = CGAffineTransform(translationX: 27, y: 18)
                .rotated(by: .pi / 7)
                .translatedBy(x: -27, y: -20)
            shackle = shackle.applying(pivot)
        }
        let keyhole = Path { p in
            p.move(to: CGPoint(x: 20, y: 25)); p.addLine(to: CGPoint(x: 20, y: 29.5))
        }
        return [
            StickerLayer(path: shackle, stroke: 7),
            StickerLayer(path: shackle, stroke: 3, strokeColor: 0xD5DDE4),
            StickerLayer(path: rect(8.5, 17, 23, 18, r: 4.5), fill: 0xFFB84D),
            StickerLayer(path: circle(20, 24.5, 2.6), fill: ink, stroke: 0),
            StickerLayer(path: keyhole),
        ]
    }

    static var flame: [StickerLayer] {
        // Drawn in a 24-unit box, then scaled into the 40 box.
        let toSticker = CGAffineTransform(a: 1.6, b: 0, c: 0, d: 1.6, tx: 0.8, ty: 4.4)
        let outer = Path { p in
            p.move(to: CGPoint(x: 12, y: 2))
            p.addCurve(to: CGPoint(x: 17, y: 12), control1: CGPoint(x: 13, y: 5), control2: CGPoint(x: 17, y: 7.5))
            p.addArc(center: CGPoint(x: 12, y: 12), radius: 5, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            p.addCurve(to: CGPoint(x: 9, y: 7.5), control1: CGPoint(x: 7, y: 10), control2: CGPoint(x: 8, y: 8.5))
            p.addCurve(to: CGPoint(x: 11, y: 10.5), control1: CGPoint(x: 9, y: 9.5), control2: CGPoint(x: 10, y: 10.5))
            p.addCurve(to: CGPoint(x: 12, y: 2), control1: CGPoint(x: 11, y: 7.5), control2: CGPoint(x: 10, y: 5.5))
            p.closeSubpath()
        }.applying(toSticker)
        let inner = Path { p in
            p.move(to: CGPoint(x: 12, y: 10.5))
            p.addCurve(to: CGPoint(x: 14.5, y: 14.5), control1: CGPoint(x: 13, y: 12), control2: CGPoint(x: 14.5, y: 13))
            p.addArc(center: CGPoint(x: 12, y: 14.5), radius: 2.5, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            p.addCurve(to: CGPoint(x: 12, y: 10.5), control1: CGPoint(x: 9.5, y: 13), control2: CGPoint(x: 11, y: 12))
            p.closeSubpath()
        }.applying(toSticker)
        return [
            StickerLayer(path: outer, fill: 0xFF8A3D),
            StickerLayer(path: inner, fill: 0xFFD36B, stroke: 0),
        ]
    }

    static var house: [StickerLayer] {
        let roof = Path { p in
            p.move(to: CGPoint(x: 5, y: 20)); p.addLine(to: CGPoint(x: 20, y: 6.5)); p.addLine(to: CGPoint(x: 35, y: 20))
            p.closeSubpath()
        }
        return [
            StickerLayer(path: rect(9.5, 16, 21, 18.5, r: 2), fill: 0xFFE3B3),
            StickerLayer(path: roof, fill: 0xFF7A59),
            StickerLayer(path: rect(16.5, 23.5, 7, 11, r: 1.5), fill: 0x7A4B2A, stroke: 2),
        ]
    }

    static var dumbbell: [StickerLayer] {
        [
            StickerLayer(path: rect(13, 18.2, 14, 3.6, r: 1.4), fill: 0xD5DDE4, stroke: 2),
            StickerLayer(path: rect(4.5, 13.5, 5.5, 13, r: 2), fill: 0x8FB0FF),
            StickerLayer(path: rect(30, 13.5, 5.5, 13, r: 2), fill: 0x8FB0FF),
            StickerLayer(path: rect(9, 9, 6, 22, r: 2.2), fill: 0x8FB0FF),
            StickerLayer(path: rect(25, 9, 6, 22, r: 2.2), fill: 0x8FB0FF),
        ]
    }

    static var trophy: [StickerLayer] {
        let handles = Path { p in
            p.move(to: CGPoint(x: 11, y: 10)); p.addLine(to: CGPoint(x: 6.5, y: 10))
            p.addCurve(to: CGPoint(x: 12.5, y: 20), control1: CGPoint(x: 6.5, y: 16), control2: CGPoint(x: 9, y: 19))
            p.move(to: CGPoint(x: 29, y: 10)); p.addLine(to: CGPoint(x: 33.5, y: 10))
            p.addCurve(to: CGPoint(x: 27.5, y: 20), control1: CGPoint(x: 33.5, y: 16), control2: CGPoint(x: 31, y: 19))
        }
        let cup = Path { p in
            p.move(to: CGPoint(x: 11, y: 6.5))
            p.addLine(to: CGPoint(x: 29, y: 6.5))
            p.addLine(to: CGPoint(x: 29, y: 15))
            p.addArc(center: CGPoint(x: 20, y: 15), radius: 9, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            p.closeSubpath()
        }
        return [
            StickerLayer(path: handles),
            StickerLayer(path: rect(17.5, 23, 5, 6.5), fill: 0xE39A1F),
            StickerLayer(path: rect(11.5, 28.5, 17, 5.5, r: 2), fill: 0xE39A1F),
            StickerLayer(path: cup, fill: 0xFFD36B),
            StickerLayer(path: rect(14.5, 9.5, 2.6, 7, r: 1.3), fill: 0xFFF6D8, stroke: 0),
        ]
    }

    static var chart: [StickerLayer] {
        let base = Path { p in
            p.move(to: CGPoint(x: 5, y: 34)); p.addLine(to: CGPoint(x: 35, y: 34))
        }
        return [
            StickerLayer(path: rect(7, 20, 7, 14, r: 2), fill: 0x7BE3C6),
            StickerLayer(path: rect(16.5, 8, 7, 26, r: 2), fill: 0x8FB0FF),
            StickerLayer(path: rect(26, 14.5, 7, 19.5, r: 2), fill: 0xFFB84D),
            StickerLayer(path: base),
        ]
    }

    /// Screen Time's own symbol, as a sticker: purple caps, glass bulbs, amber sand.
    static var hourglass: [StickerLayer] {
        let glass = Path { p in
            p.move(to: CGPoint(x: 12, y: 8))
            p.addLine(to: CGPoint(x: 28, y: 8))
            p.addCurve(to: CGPoint(x: 21.4, y: 20), control1: CGPoint(x: 28, y: 14.5), control2: CGPoint(x: 23.5, y: 17.5))
            p.addCurve(to: CGPoint(x: 28, y: 32), control1: CGPoint(x: 23.5, y: 22.5), control2: CGPoint(x: 28, y: 25.5))
            p.addLine(to: CGPoint(x: 12, y: 32))
            p.addCurve(to: CGPoint(x: 18.6, y: 20), control1: CGPoint(x: 12, y: 25.5), control2: CGPoint(x: 16.5, y: 22.5))
            p.addCurve(to: CGPoint(x: 12, y: 8), control1: CGPoint(x: 16.5, y: 17.5), control2: CGPoint(x: 12, y: 14.5))
            p.closeSubpath()
        }
        let topSand = Path { p in
            p.move(to: CGPoint(x: 15.2, y: 12.5))
            p.addLine(to: CGPoint(x: 24.8, y: 12.5))
            p.addCurve(to: CGPoint(x: 20, y: 18.8), control1: CGPoint(x: 24, y: 15.5), control2: CGPoint(x: 21.5, y: 17.3))
            p.addCurve(to: CGPoint(x: 15.2, y: 12.5), control1: CGPoint(x: 18.5, y: 17.3), control2: CGPoint(x: 16, y: 15.5))
            p.closeSubpath()
        }
        let bottomSand = Path { p in
            p.move(to: CGPoint(x: 13.8, y: 31))
            p.addCurve(to: CGPoint(x: 20, y: 25.2), control1: CGPoint(x: 14.5, y: 27.5), control2: CGPoint(x: 17.5, y: 25.6))
            p.addCurve(to: CGPoint(x: 26.2, y: 31), control1: CGPoint(x: 22.5, y: 25.6), control2: CGPoint(x: 25.5, y: 27.5))
            p.closeSubpath()
        }
        let stream = Path { p in
            p.move(to: CGPoint(x: 20, y: 19)); p.addLine(to: CGPoint(x: 20, y: 26))
        }
        return [
            StickerLayer(path: glass, fill: 0xE6F4FF),
            StickerLayer(path: topSand, fill: 0xFFB84D, stroke: 0),
            StickerLayer(path: bottomSand, fill: 0xFFB84D, stroke: 0),
            StickerLayer(path: stream, stroke: 1.4, strokeColor: 0xF2A93B),
            StickerLayer(path: rect(8.5, 4, 23, 5, r: 2.2), fill: 0xB98CFF),
            StickerLayer(path: rect(8.5, 31, 23, 5, r: 2.2), fill: 0xB98CFF),
        ]
    }

    static var person: [StickerLayer] {
        let body = Path { p in
            p.move(to: CGPoint(x: 8, y: 34))
            p.addCurve(to: CGPoint(x: 20, y: 22.5), control1: CGPoint(x: 8, y: 26.5), control2: CGPoint(x: 13, y: 22.5))
            p.addCurve(to: CGPoint(x: 32, y: 34), control1: CGPoint(x: 27, y: 22.5), control2: CGPoint(x: 32, y: 26.5))
            p.closeSubpath()
        }
        return [
            StickerLayer(path: body, fill: 0xB98CFF),
            StickerLayer(path: circle(20, 13, 6.5), fill: 0xB98CFF),
        ]
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 12) {
            ForEach(StickerKind.allCases, id: \.self) { StickerIcon(kind: $0, size: 30) }
        }
        HStack(spacing: 12) {
            ForEach(StickerKind.allCases, id: \.self) { StickerIcon(kind: $0, size: 30, muted: true) }
        }
    }
    .padding()
    .background(Color(red: 0, green: 0.17, blue: 0.2))
}
