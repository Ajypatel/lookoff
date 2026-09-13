import SwiftUI

struct AnimatedBackground: View {
    let style: BackgroundStyle
    let wallpaper: NSImage?
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Palette.canvas
                switch style {
                case .desktop:
                    GradientWash(t: t, reduceMotion: reduceMotion)
                case .wallpaper:
                    if let wallpaper {
                        Image(nsImage: wallpaper)
                            .resizable()
                            .scaledToFill()
                            .overlay(Color.black.opacity(0.28))
                    } else {
                        GradientWash(t: t, reduceMotion: reduceMotion)
                    }
                case .gradient:
                    GradientWash(t: t, reduceMotion: reduceMotion)
                case .orbs:
                    GradientWash(t: t, reduceMotion: reduceMotion)
                    SoftOrbs(t: t, reduceMotion: reduceMotion)
                case .particles:
                    GradientWash(t: t, reduceMotion: reduceMotion)
                    DriftParticles(t: t, reduceMotion: reduceMotion)
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

struct GradientWash: View {
    var t: TimeInterval
    var reduceMotion: Bool

    var body: some View {
        let phase = reduceMotion ? 0.0 : t * 0.05
        LinearGradient(
            colors: [
                Palette.canvas,
                Palette.purple.opacity(0.35),
                Palette.magenta.opacity(0.22),
                Palette.gold.opacity(0.12),
                Palette.canvas
            ],
            startPoint: .init(x: 0.2 + 0.1 * sin(phase), y: 0),
            endPoint: .init(x: 0.8 + 0.1 * cos(phase), y: 1)
        )
        .blur(radius: 18)
    }
}

struct SoftOrbs: View {
    var t: TimeInterval
    var reduceMotion: Bool

    var body: some View {
        Canvas { context, size in
            let orbs: [(Color, CGFloat, CGPoint)] = [
                (Palette.magenta, 0.42, unit(0.22, 0.28, t, 0.11)),
                (Palette.purple, 0.50, unit(0.72, 0.35, t, 0.08)),
                (Palette.gold, 0.32, unit(0.48, 0.72, t, 0.13))
            ]
            for (color, scale, point) in orbs {
                let radius = min(size.width, size.height) * scale
                let rect = CGRect(
                    x: point.x * size.width - radius / 2,
                    y: point.y * size.height - radius / 2,
                    width: radius,
                    height: radius
                )
                context.fill(Circle().path(in: rect), with: .color(color.opacity(0.28)))
            }
        }
        .blur(radius: 48)
        .blendMode(.plusLighter)
    }

    private func unit(_ x: CGFloat, _ y: CGFloat, _ t: TimeInterval, _ speed: Double) -> CGPoint {
        guard !reduceMotion else { return CGPoint(x: x, y: y) }
        return CGPoint(
            x: x + 0.06 * CGFloat(sin(t * speed)),
            y: y + 0.05 * CGFloat(cos(t * speed * 0.9))
        )
    }
}

struct DriftParticles: View {
    var t: TimeInterval
    var reduceMotion: Bool

    var body: some View {
        Canvas { context, size in
            for i in 0..<28 {
                let seed = Double(i) * 1.37
                let x = (seed * 0.17 + (reduceMotion ? 0 : t * 0.012 * (0.4 + seed.truncatingRemainder(dividingBy: 0.6)))).truncatingRemainder(dividingBy: 1)
                let y = (0.12 + seed * 0.05 + (reduceMotion ? 0 : sin(t * 0.07 + seed) * 0.04)).truncatingRemainder(dividingBy: 1)
                let rect = CGRect(
                    x: x * size.width,
                    y: abs(y) * size.height,
                    width: 3,
                    height: 3
                )
                context.fill(Circle().path(in: rect), with: .color(Color.white.opacity(0.22)))
            }
        }
    }
}
