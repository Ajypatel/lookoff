import AppKit
import SwiftUI

struct BreakOverlayRoot: View {
    @Bindable var live: OverlayLiveState
    /// Frozen at break start — wallpaper file. Never live glass.
    let frozenBackdrop: NSImage?
    let safeTop: CGFloat
    let fadeDuration: TimeInterval
    let onSkip: () -> Void
    let onEnd: () -> Void
    let onLock: () -> Void
    var onExtend: ((Int) -> Void)? = nil
    var onSecondTick: ((Int) -> Void)? = nil
    var onStage: ((BreakSoundStage) -> Void)? = nil

    @State private var backdropOpacity: Double = 0
    @State private var clockOpacity: Double = 0
    @State private var clockOffset: CGFloat = -8
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 18
    @State private var instructionOpacity: Double = 0
    @State private var timerOpacity: Double = 0
    @State private var timerOffset: CGFloat = 16
    @State private var timerScale: CGFloat = 0.94
    @State private var buttonsOpacity: Double = 0
    @State private var buttonsOffset: CGFloat = 22
    @State private var lastEscAt: Date?
    @State private var lastAnnouncedSecond: Int = -1
    @State private var didPlayUnlock = false

    private var snapshot: EngineSnapshot { live.snapshot }
    private var settings: AppSettings { live.settings }
    private var reduce: Bool { live.reduceMotion }
    private var topPad: CGFloat { max(safeTop, 28) + 12 }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color.black
                    .opacity(backdropOpacity)
                    .allowsHitTesting(false)

                backdrop(size: size)
                    .opacity(backdropOpacity)
                    .allowsHitTesting(false)

                // Soft vignette — depth without crushing the photo
                RadialGradient(
                    colors: [.clear, .black.opacity(0.42)],
                    center: .center,
                    startRadius: min(size.width, size.height) * 0.22,
                    endRadius: max(size.width, size.height) * 0.72
                )
                .opacity(backdropOpacity)
                .allowsHitTesting(false)

                Color.black.opacity(0.22 * backdropOpacity)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    clockBar
                        .opacity(clockOpacity)
                        .offset(y: clockOffset)
                        .padding(.top, topPad)

                    Spacer(minLength: 0)

                    centerBlock
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: 0)

                    bottomControls
                        .opacity(buttonsOpacity)
                        .offset(y: buttonsOffset)
                        .padding(.bottom, max(geo.safeAreaInsets.bottom, 28) + 18)
                }
                .frame(width: size.width, height: size.height)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .focusable()
        .onKeyPress(.escape) {
            handleEscape()
            return .handled
        }
        .onAppear { runEnter() }
        .onChange(of: live.showGeneration) { _, _ in
            resetMotion()
            lastAnnouncedSecond = -1
            didPlayUnlock = false
            runEnter()
        }
        .onChange(of: live.isDismissing) { _, dismissing in
            if dismissing { runExit() }
        }
        .onChange(of: Int(ceil(snapshot.remaining))) { _, second in
            guard snapshot.phase == .onBreak, second != lastAnnouncedSecond else { return }
            lastAnnouncedSecond = second
            if second > 0, second <= 5 {
                onSecondTick?(second)
            }
        }
        .onChange(of: snapshot.skipAllowed) { _, allowed in
            guard allowed, settings.skipMode == .balanced, !didPlayUnlock else { return }
            didPlayUnlock = true
            onStage?(.skipUnlocked)
        }
        .animation(.spring(response: 0.48, dampingFraction: 0.82), value: snapshot.skipAllowed)
    }

    // MARK: - Backdrop

    @ViewBuilder
    private func backdrop(size: CGSize) -> some View {
        ZStack {
            switch settings.backgroundStyle {
            case .desktop, .wallpaper:
                if let frozenBackdrop {
                    frozenBlur(frozenBackdrop, size: size)
                } else {
                    LinearGradient(
                        colors: [Palette.canvas, Palette.purple.opacity(0.35), Palette.canvas],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            case .gradient, .orbs, .particles:
                AnimatedBackground(
                    style: settings.backgroundStyle,
                    wallpaper: frozenBackdrop ?? live.customWallpaper,
                    reduceMotion: true
                )
                .frame(width: size.width, height: size.height)
                .clipped()
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func frozenBlur(_ image: NSImage, size: CGSize) -> some View {
        Color.clear
            .frame(width: size.width, height: size.height)
            .overlay {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
            .blur(radius: 32, opaque: true)
            .scaleEffect(1.08)
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    // MARK: - Chrome

    private var clockBar: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .medium))
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text(context.date, style: .time)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    }
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                    }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var centerBlock: some View {
        VStack(spacing: 0) {
            Text(headline)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .shadow(color: .black.opacity(0.4), radius: 14, y: 3)
                .opacity(titleOpacity)
                .offset(y: titleOffset)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)

            Text(instructionLine)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 440)
                .padding(.top, 12)
                .opacity(instructionOpacity)
                .offset(y: titleOffset * 0.5)
                .frame(maxWidth: .infinity)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.35),
                            Color.white.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 72, height: 1.5)
                .padding(.top, 26)
                .opacity(timerOpacity)

            CountdownDigitsView(
                totalSeconds: max(0, Int(ceil(snapshot.remaining))),
                reduceMotion: reduce
            )
            .padding(.top, 22)
            .opacity(timerOpacity)
            .offset(y: timerOffset)
            .scaleEffect(timerScale)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 36)
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            // Secondary: extend — quieter than primary actions below
            HStack(spacing: 10) {
                BreakExtendPill(minutes: 1, action: { onExtend?(1) })
                    .frame(maxWidth: .infinity)
                BreakExtendPill(minutes: 5, action: { onExtend?(5) })
                    .frame(maxWidth: .infinity)
            }

            // Primary: skip / end / lock
            HStack(spacing: 12) {
                if settings.skipMode != .hardcore {
                    skipControl
                        .frame(maxWidth: .infinity)
                }
                if snapshot.endEarlyAllowed {
                    BreakActionPill(title: "End Break", systemImage: "checkmark", action: onEnd)
                        .frame(maxWidth: .infinity)
                }
                BreakActionPill(title: "Lock Screen", systemImage: "lock.fill", action: onLock)
                    .frame(maxWidth: .infinity)
            }

            if settings.skipMode != .hardcore {
                HStack(spacing: 6) {
                    Text("Press")
                    Text("Esc")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.white.opacity(0.14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8)
                                }
                        }
                    Text("twice to skip the break.")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
            }
        }
        .frame(maxWidth: actionClusterWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private var actionClusterWidth: CGFloat {
        snapshot.endEarlyAllowed ? 460 : 340
    }

    @ViewBuilder
    private var skipControl: some View {
        switch settings.skipMode {
        case .hardcore:
            EmptyView()
        case .casual:
            BreakActionPill(title: "Skip Break", systemImage: "forward.end.fill", action: onSkip)
        case .balanced:
            MorphingSkipPill(
                progress: snapshot.skipUnlockProgress,
                unlocked: snapshot.skipAllowed,
                onSkip: onSkip
            )
        }
    }

    private var headline: String {
        let msg = snapshot.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return msg.isEmpty ? "Eyes to the horizon" : msg
    }

    private var instructionLine: String {
        let line = snapshot.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !line.isEmpty { return line }
        let fallback = settings.breakInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? AppSettings.defaultInstruction : fallback
    }

    // MARK: - Motion

    private func resetMotion() {
        backdropOpacity = 0
        clockOpacity = 0
        clockOffset = -8
        titleOpacity = 0
        titleOffset = 18
        instructionOpacity = 0
        timerOpacity = 0
        timerOffset = 16
        timerScale = 0.94
        buttonsOpacity = 0
        buttonsOffset = 22
    }

    private func revealAllInstant() {
        backdropOpacity = 1
        clockOpacity = 1
        clockOffset = 0
        titleOpacity = 1
        titleOffset = 0
        instructionOpacity = 1
        timerOpacity = 1
        timerOffset = 0
        timerScale = 1
        buttonsOpacity = 1
        buttonsOffset = 0
    }

    private func runEnter() {
        resetMotion()
        if reduce {
            revealAllInstant()
            onStage?(.enterBlur)
            onStage?(.enterTitle)
            return
        }

        // 1) Blur fills the world
        onStage?(.enterBlur)
        withAnimation(.easeOut(duration: 0.7)) {
            backdropOpacity = 1
        }

        // 2) Clock
        schedule(at: 0.58, stage: .enterClock) {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
                clockOpacity = 1
                clockOffset = 0
            }
        }

        // 3) Headline
        schedule(at: 0.78, stage: .enterTitle) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
                titleOpacity = 1
                titleOffset = 0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.08)) {
                instructionOpacity = 1
            }
        }

        // 4) Timer
        schedule(at: 1.08, stage: .enterTimer) {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.84)) {
                timerOpacity = 1
                timerOffset = 0
                timerScale = 1
            }
        }

        // 5) Controls
        schedule(at: 1.32, stage: .enterControls) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) {
                buttonsOpacity = 1
                buttonsOffset = 0
            }
        }
    }

    private func schedule(at delay: TimeInterval, stage: BreakSoundStage, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard !live.isDismissing else { return }
            onStage?(stage)
            work()
        }
    }

    /// Exit sound only — visual fade is panel alpha (smooth, no material flicker).
    private func runExit() {
        onStage?(.exitFast)
    }

    private func handleEscape() {
        guard settings.skipMode != .hardcore else { return }
        let now = Date()
        if let lastEscAt, now.timeIntervalSince(lastEscAt) < 0.85 {
            if snapshot.skipAllowed { onSkip() }
            else if snapshot.endEarlyAllowed { onEnd() }
            self.lastEscAt = nil
        } else {
            lastEscAt = now
        }
    }
}

// MARK: - Morph Wait → Skip

struct MorphingSkipPill: View {
    let progress: Double
    let unlocked: Bool
    let onSkip: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: { if unlocked { onSkip() } }) {
            HStack(spacing: 10) {
                ZStack {
                    if unlocked {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 2)
                            Circle()
                                .trim(from: 0, to: max(0.02, min(1, progress)))
                                .stroke(Color.white.opacity(0.95), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 16, height: 16)
                .animation(.spring(response: 0.42, dampingFraction: 0.78), value: unlocked)

                Text(unlocked ? "Skip Break" : "Wait for skip")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .contentTransition(.interpolate)
                    .animation(.spring(response: 0.42, dampingFraction: 0.8), value: unlocked)
            }
            .foregroundStyle(.white.opacity(unlocked ? 1 : 0.72))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                LiquidGlassCapsule(hovering: unlocked && hovering, dimmed: !unlocked)
            }
            .scaleEffect(unlocked && hovering ? 1.02 : 1)
        }
        .buttonStyle(BreakPillPressStyle())
        .disabled(!unlocked)
        .allowsHitTesting(unlocked)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: unlocked)
        .animation(.linear(duration: 0.2), value: progress)
        .accessibilityLabel(unlocked ? "Skip Break" : "Wait for skip")
    }
}

// MARK: - Countdown

struct CountdownDigitsView: View {
    let totalSeconds: Int
    let reduceMotion: Bool

    private var chars: [Character] {
        Array(String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60))
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(chars.enumerated()), id: \.offset) { _, ch in
                if ch == ":" {
                    Text(":")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 20)
                } else {
                    RollingDigit(digit: ch, reduceMotion: reduceMotion)
                }
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 16, y: 4)
        .accessibilityLabel(Text(String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)))
    }
}

private struct RollingDigit: View {
    let digit: Character
    let reduceMotion: Bool

    var body: some View {
        Text(String(digit))
            .font(.system(size: 64, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: 40, height: 76)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: digit)
    }
}

// MARK: - Pills

struct BreakActionPill: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                LiquidGlassCapsule(hovering: hovering, dimmed: false)
            }
            .scaleEffect(hovering ? 1.02 : 1)
        }
        .buttonStyle(BreakPillPressStyle())
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hovering)
    }
}

struct BreakExtendPill: View {
    let minutes: Int
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "zzz")
                    .font(.system(size: 10, weight: .medium))
                Text("+ \(minutes) min")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.white.opacity(hovering ? 0.88 : 0.62))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                LiquidGlassCapsule(hovering: hovering, dimmed: true, compact: true)
            }
            .scaleEffect(hovering ? 1.015 : 1)
        }
        .buttonStyle(BreakPillPressStyle())
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hovering)
        .accessibilityLabel("Add \(minutes) minute\(minutes == 1 ? "" : "s") to break")
    }
}

/// Liquid glass over frozen backdrop (SwiftUI material — no desktop bleed).
private struct LiquidGlassCapsule: View {
    var hovering: Bool
    var dimmed: Bool
    var compact: Bool = false

    var body: some View {
        Capsule()
            .fill(.clear)
            .lookOffGlass(in: Capsule())
            .opacity(dimmed ? (compact ? 0.7 : 0.88) : 1)
            .brightness(hovering ? 0.04 : 0)
            .shadow(
                color: .black.opacity(dimmed ? 0.08 : (hovering ? 0.28 : 0.16)),
                radius: dimmed ? (hovering ? 8 : 4) : (hovering ? 14 : 8),
                y: dimmed ? 2 : 4
            )
    }
}

private struct BreakPillPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
