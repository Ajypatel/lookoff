import AppKit
import Observation
import SwiftUI

enum WellnessSoundCue {
    case enter, rise, blink, happy, exit
}

@MainActor
final class WellnessOverlayController {
    private var panels: [OverlayPanel] = []
    private var hideWork: DispatchWorkItem?
    private var live: WellnessLiveState?
    private var currentKind: WellnessEngine.Kind = .posture
    private(set) var isVisible = false
    var onCue: ((WellnessSoundCue, WellnessEngine.Kind) -> Void)?

    func show(
        kind: WellnessEngine.Kind,
        settings: AppSettings,
        recordingActive _: Bool,
        durationOverride: TimeInterval? = nil
    ) {
        hide(immediate: true)
        currentKind = kind
        isVisible = true

        let screens: [NSScreen] = {
            switch settings.wellnessPlacement {
            case .allScreens:
                return NSScreen.screens
            case .chosenDisplay:
                if let match = NSScreen.screens.first(where: { BreakOverlayController.displayID($0) == settings.wellnessDisplayID }) {
                    return [match]
                }
                fallthrough
            case .activeScreen:
                if let keyScreen = NSApp.keyWindow?.screen {
                    return [keyScreen]
                }
                return [NSScreen.screenUnderMouse ?? NSScreen.main ?? NSScreen.screens[0]]
            }
        }()

        let badge = settings.wellnessSize.pointSize
        let dim = settings.wellnessDim
        let live = WellnessLiveState()
        self.live = live
        let hideFromCapture = settings.hideFromRecordings
        let postureBase = badge * 0.78
        let postureSpan = postureBase * 1.18 + postureBase * 2.45

        for screen in screens {
            let frame: NSRect = {
                if dim {
                    return screen.frame
                }
                let extra: CGFloat = kind == .posture ? postureSpan + 48 : 80
                let size = NSSize(width: max(badge + 80, postureBase * 1.18 + 48), height: badge + extra)
                let origin = settings.wellnessScreenPosition.origin(in: screen.visibleFrame, size: size)
                return NSRect(
                    x: origin.x,
                    y: origin.y,
                    width: size.width,
                    height: size.height
                )
            }()

            let panel = OverlayPanel(frame: frame, allowsKey: false, sharingHidden: hideFromCapture)
            // Above apps, never modal — clicks/keys must reach whatever you are doing.
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 2)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.ignoresMouseEvents = true
            panel.acceptsMouseMovedEvents = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.sharingType = hideFromCapture ? .none : .readOnly
            let hosting = NSHostingView(
                rootView: WellnessView(
                    kind: kind,
                    dim: dim,
                    reduceMotion: settings.respectReduceMotion && Motion.reduceMotion,
                    badgeSize: badge,
                    position: settings.wellnessScreenPosition,
                    live: live
                )
                .allowsHitTesting(false)
                .frame(width: frame.width, height: frame.height)
            )
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = .clear
            panel.contentView = hosting
            panel.orderFrontRegardless()
            panels.append(panel)
        }

        live.onCue = { [weak self] cue in
            guard let self else { return }
            self.onCue?(cue, self.currentKind)
        }
        live.onSequenceComplete = { [weak self] in
            self?.hide(immediate: true)
        }
        live.present()
        onCue?(.enter, kind)

        // Fallback if sequence never signals (Reduce Motion / stuck)
        let visible = durationOverride ?? max(8.5, settings.wellnessDurationSeconds + 3.2)
        let work = DispatchWorkItem { [weak self] in
            self?.hide(immediate: false)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + visible, execute: work)
    }

    /// Dismiss only when forced (break screen / replace) or when the nudge finishes.
    /// Do not call this for casual clicks, typing, or brief smart-pause — animation must finish.
    func hide(immediate: Bool = true) {
        hideWork?.cancel()
        hideWork = nil
        if immediate || live == nil {
            tearDown()
            return
        }
        live?.dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in
            self?.tearDown()
        }
    }

    private func tearDown() {
        isVisible = false
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        live = nil
    }
}

@MainActor
@Observable
final class WellnessLiveState {
    var visible = false
    var dimShown = false
    var onSequenceComplete: (() -> Void)?
    var onCue: ((WellnessSoundCue) -> Void)?
    private var didFinish = false
    private var didBeginExit = false

    func present() {
        didFinish = false
        didBeginExit = false
        visible = false
        dimShown = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
            visible = true
            dimShown = true
        }
    }

    func beginExit() {
        guard !didBeginExit else { return }
        didBeginExit = true
        onCue?(.exit)
        withAnimation(.easeIn(duration: 0.58)) {
            dimShown = false
        }
    }

    func dismiss() {
        beginExit()
        withAnimation(.easeIn(duration: 0.36)) {
            visible = false
        }
    }

    func cue(_ cue: WellnessSoundCue) {
        onCue?(cue)
    }

    func sequenceFinished() {
        guard !didFinish else { return }
        didFinish = true
        onSequenceComplete?()
    }
}

private struct WellnessBadgeSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = Layout.wellnessSize
}

extension EnvironmentValues {
    var wellnessBadgeSize: CGFloat {
        get { self[WellnessBadgeSizeKey.self] }
        set { self[WellnessBadgeSizeKey.self] = newValue }
    }
}

struct WellnessView: View {
    let kind: WellnessEngine.Kind
    let dim: Bool
    let reduceMotion: Bool
    var badgeSize: CGFloat = Layout.wellnessSize
    var position: WellnessScreenPosition = .center
    /// Settings card: shorter posture travel so the orb fits the preview frame.
    var compactPreview: Bool = false
    var live: WellnessLiveState?
    @State private var appeared = false

    private var shown: Bool {
        live?.visible ?? appeared
    }

    private var dimOn: Bool {
        live?.dimShown ?? appeared
    }

    var body: some View {
        ZStack {
            if dim {
                EllipticalGradient(
                    colors: [
                        Color.black.opacity(dimOn ? 0.16 : 0),
                        Color.black.opacity(dimOn ? 0.42 : 0),
                        Color.black.opacity(dimOn ? 0.72 : 0)
                    ],
                    center: .center,
                    startRadiusFraction: 0.08,
                    endRadiusFraction: 0.95
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            }

            Group {
                switch kind {
                case .posture:
                    PostureLookAwayAnimation(reduceMotion: reduceMotion, live: live, compactPreview: compactPreview)
                        .opacity(shown ? 1 : 0)
                case .blink:
                    BlinkLookAwayAnimation(reduceMotion: reduceMotion, live: live)
                        .opacity(shown ? 1 : 0)
                }
            }
            .padding(dim ? position.overlayInsets : EdgeInsets())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: position.alignment)
        }
        .environment(\.wellnessBadgeSize, kind == .posture ? badgeSize * 0.78 : badgeSize)
        .onAppear {
            guard live == nil else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.78)) {
                appeared = true
            }
        }
    }
}

/// Settings card loop: circular badge like blink — posture skips tall rise so nothing clips.
struct WellnessPreviewLoop: View {
    let kind: WellnessEngine.Kind
    @State private var shown = false
    @State private var token = 0

    var body: some View {
        ZStack {
            if shown {
                Group {
                    switch kind {
                    case .posture:
                        PostureSettingsPreviewBadge(reduceMotion: Motion.reduceMotion)
                    case .blink:
                        BlinkLookAwayAnimation(reduceMotion: Motion.reduceMotion)
                            .environment(\.wellnessBadgeSize, 48)
                    }
                }
                .id(token)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.82).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task { await runLoop() }
    }

    @MainActor
    private func runLoop() async {
        if Motion.reduceMotion {
            shown = true
            return
        }
        while !Task.isCancelled {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.78)) {
                shown = true
            }
            try? await Task.sleep(nanoseconds: kind == .posture ? 3_600_000_000 : 3_800_000_000)
            if Task.isCancelled { return }

            withAnimation(.easeIn(duration: 0.28)) {
                shown = false
            }
            try? await Task.sleep(nanoseconds: 360_000_000)
            if Task.isCancelled { return }

            token += 1
            try? await Task.sleep(nanoseconds: 420_000_000)
        }
    }
}

/// Compact settings-only posture: same circular footprint as blink (no tall rise/stretch).
private struct PostureSettingsPreviewBadge: View {
    let reduceMotion: Bool
    @State private var shell: CGFloat = 0
    @State private var inner: CGFloat = 0
    @State private var bob: CGFloat = 0
    @State private var pulse: CGFloat = 1

    private let base: CGFloat = 48
    private var orb: CGFloat { base * 1.18 }

    var body: some View {
        ZStack {
            LiquidGlassShell(width: orb, height: orb)
                .scaleEffect(shell)

            ZStack {
                WellnessBadge(pulse: pulse)
                Image(systemName: "arrow.up")
                    .font(.system(size: base * 0.38, weight: .bold))
                    .foregroundStyle(.black.opacity(0.92))
            }
            .environment(\.wellnessBadgeSize, base)
            .scaleEffect(inner)
            .opacity(Double(inner))
            .offset(y: bob)
        }
        .frame(width: orb + 16, height: orb + 20)
        .task(id: reduceMotion) { await run() }
    }

    @MainActor
    private func run() async {
        if reduceMotion {
            shell = 1
            inner = 1
            return
        }
        while !Task.isCancelled {
            shell = 0
            inner = 0
            bob = 6
            pulse = 1

            withAnimation(.spring(response: 0.48, dampingFraction: 0.78)) {
                shell = 1
            }
            try? await Task.sleep(nanoseconds: 320_000_000)
            if Task.isCancelled { return }

            withAnimation(.spring(response: 0.42, dampingFraction: 0.76)) {
                inner = 1
            }
            try? await Task.sleep(nanoseconds: 280_000_000)
            if Task.isCancelled { return }

            withAnimation(.easeInOut(duration: 0.55)) {
                bob = -5
                pulse = 1.04
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }

            withAnimation(.easeInOut(duration: 0.55)) {
                bob = 0
                pulse = 1
            }
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if Task.isCancelled { return }

            withAnimation(.easeIn(duration: 0.26)) {
                inner = 0
                pulse = 0.92
            }
            try? await Task.sleep(nanoseconds: 260_000_000)
            if Task.isCancelled { return }

            withAnimation(.easeIn(duration: 0.3)) {
                shell = 0
            }
            try? await Task.sleep(nanoseconds: 320_000_000)
            if Task.isCancelled { return }

            try? await Task.sleep(nanoseconds: 280_000_000)
        }
    }
}

// MARK: - LookAway badge (pink→orange)

private struct WellnessBadge: View {
    var pulse: CGFloat = 1
    @Environment(\.wellnessBadgeSize) private var base

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.28, blue: 0.55),
                        Color(red: 1.0, green: 0.42, blue: 0.32),
                        Color(red: 1.0, green: 0.62, blue: 0.18)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: Color(red: 1.0, green: 0.35, blue: 0.45).opacity(0.55), radius: base * 0.22, y: 8)
            .frame(width: base, height: base)
            .scaleEffect(pulse)
    }
}

private struct LiquidGlassShell: View {
    var width: CGFloat
    var height: CGFloat

    var body: some View {
        Color.clear
            .frame(width: width, height: height)
            .lookOffGlass(in: Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
    }
}

// MARK: - Posture: glass orb → badge+arrow → stretch rise → round at top → reverse exit

struct PostureLookAwayAnimation: View {
    let reduceMotion: Bool
    var live: WellnessLiveState?
    var compactPreview: Bool = false
    @Environment(\.wellnessBadgeSize) private var base
    @State private var shell: CGFloat = 0
    @State private var inner: CGFloat = 0
    @State private var rise: CGFloat = 0
    @State private var stretch: CGFloat = 0
    @State private var pulse: CGFloat = 1

    /// Full-screen rise is tall; settings preview uses a short hop so nothing clips.
    private var travel: CGFloat { base * (compactPreview ? 0.42 : 2.45) }
    private var orb: CGFloat { base * 1.18 }

    var body: some View {
        let innerY = travel / 2 - rise * travel
        let shellH = orb + stretch * travel
        let shellY = innerY + (shellH - orb) / 2
        let totalH = orb + travel + (compactPreview ? 8 : 16)

        ZStack {
            LiquidGlassShell(width: orb, height: shellH)
                .scaleEffect(shell)
                .offset(y: shellY)

            ZStack {
                WellnessBadge(pulse: pulse)
                Image(systemName: "arrow.up")
                    .font(.system(size: base * 0.38, weight: .bold))
                    .foregroundStyle(.black.opacity(0.92))
            }
            .scaleEffect(inner)
            .opacity(Double(inner))
            .offset(y: innerY)
        }
        .frame(width: orb + 12, height: totalH)
        .shadow(color: .clear, radius: 0) // avoid soft shadow blowing past preview clip
        .task(id: "\(reduceMotion)-\(compactPreview)") { await run() }
    }

    @MainActor
    private func run() async {
        if reduceMotion {
            shell = 1
            inner = 1
            rise = 1
            stretch = 0
            live?.sequenceFinished()
            return
        }

        let loop = live == nil
        while !Task.isCancelled {
            shell = 0
            inner = 0
            rise = 0
            stretch = 0
            pulse = 1

            withAnimation(.spring(response: 0.48, dampingFraction: 0.78)) {
                shell = 1
            }
            try? await Task.sleep(nanoseconds: 380_000_000)
            if Task.isCancelled { return }

            withAnimation(.spring(response: 0.42, dampingFraction: 0.76)) {
                inner = 1
                pulse = 1.03
            }
            try? await Task.sleep(nanoseconds: 320_000_000)
            if Task.isCancelled { return }

            live?.cue(.rise)
            withAnimation(.easeInOut(duration: compactPreview ? 0.7 : 1.28)) {
                rise = 1
                stretch = compactPreview ? 0.35 : 1
                pulse = 1.02
            }
            try? await Task.sleep(nanoseconds: compactPreview ? 900_000_000 : 1_480_000_000)
            if Task.isCancelled { return }

            withAnimation(.easeInOut(duration: 0.48)) {
                stretch = 0
            }
            try? await Task.sleep(nanoseconds: 780_000_000)
            if Task.isCancelled { return }

            live?.beginExit()
            withAnimation(.easeIn(duration: 0.28)) {
                inner = 0
                pulse = 0.92
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }

            withAnimation(.easeIn(duration: 0.34)) {
                shell = 0
            }
            try? await Task.sleep(nanoseconds: 360_000_000)
            if Task.isCancelled { return }

            live?.sequenceFinished()
            if !loop { return }

            try? await Task.sleep(nanoseconds: 280_000_000)
        }
    }
}

// MARK: - Blink: blinks → happy eyes → exit

struct BlinkLookAwayAnimation: View {
    let reduceMotion: Bool
    var live: WellnessLiveState?
    @Environment(\.wellnessBadgeSize) private var base
    @State private var closed: CGFloat = 0.35
    @State private var happy: CGFloat = 0
    @State private var pulse: CGFloat = 1
    @State private var shell: CGFloat = 0
    @State private var inner: CGFloat = 0

    var body: some View {
        let orb = base * 1.18
        ZStack {
            LiquidGlassShell(width: orb, height: orb)
                .scaleEffect(shell)

            ZStack {
                WellnessBadge(pulse: pulse)

                HStack(spacing: base * 0.16) {
                    BlinkEye(closed: closed, happy: happy, width: base * 0.22)
                    BlinkEye(closed: closed, happy: happy, width: base * 0.22)
                }
            }
            .scaleEffect(inner)
            .opacity(Double(inner))
        }
        .frame(width: orb + 12, height: orb + 12)
        .task(id: reduceMotion) { await run() }
    }

    @MainActor
    private func run() async {
        if reduceMotion {
            shell = 1
            inner = 1
            closed = 0.4
            happy = 1
            live?.sequenceFinished()
            return
        }

        let loop = live == nil
        while !Task.isCancelled {
            happy = 0
            closed = 0.28
            pulse = 1
            shell = 0
            inner = 0

            withAnimation(.spring(response: 0.48, dampingFraction: 0.78)) {
                shell = 1
            }
            try? await Task.sleep(nanoseconds: 380_000_000)
            if Task.isCancelled { return }

            withAnimation(.spring(response: 0.42, dampingFraction: 0.76)) {
                inner = 1
            }
            try? await Task.sleep(nanoseconds: 320_000_000)
            if Task.isCancelled { return }

            await blinkOnce()
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 220_000_000)
            await blinkOnce()
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 160_000_000)
            await blinkOnce()
            if Task.isCancelled { return }

            live?.cue(.happy)
            withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) {
                happy = 1
                closed = 0
                pulse = 1.05
            }
            try? await Task.sleep(nanoseconds: 780_000_000)
            if Task.isCancelled { return }

            live?.beginExit()
            withAnimation(.easeIn(duration: 0.28)) {
                inner = 0
                pulse = 0.92
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }

            withAnimation(.easeIn(duration: 0.34)) {
                shell = 0
            }
            try? await Task.sleep(nanoseconds: 360_000_000)
            if Task.isCancelled { return }

            live?.sequenceFinished()
            if !loop { return }

            try? await Task.sleep(nanoseconds: 280_000_000)
        }
    }

    @MainActor
    private func blinkOnce() async {
        live?.cue(.blink)
        withAnimation(.easeIn(duration: 0.07)) {
            closed = 1
            pulse = 0.97
        }
        try? await Task.sleep(nanoseconds: 85_000_000)
        withAnimation(.easeOut(duration: 0.12)) {
            closed = 0.22
            pulse = 1.03
        }
    }
}

private struct BlinkEye: View {
    var closed: CGFloat
    var happy: CGFloat
    var width: CGFloat

    var body: some View {
        ZStack {
            let slitH = max(2.4, width * 0.4 * (1 - closed * 0.92))
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.92 * (1 - happy)))
                .frame(width: width, height: slitH)
                .opacity(Double(1 - happy))

            Image(systemName: "chevron.up")
                .font(.system(size: width * 0.85, weight: .black))
                .foregroundStyle(.black.opacity(0.92))
                .scaleEffect(0.7 + 0.3 * happy)
                .opacity(Double(happy))
                .offset(y: 1)
        }
        .frame(width: width + 4, height: width)
    }
}

typealias PostureStraightenAnimation = PostureLookAwayAnimation
typealias BlinkEyesAnimation = BlinkLookAwayAnimation
