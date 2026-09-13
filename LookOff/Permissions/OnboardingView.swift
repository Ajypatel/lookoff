import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView().environment(AppController.shared))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Welcome to LookOff"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.isMovableByWindowBackground = true
            window.setContentSize(NSSize(width: 760, height: 540))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        AppDockPolicy.showInDock()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
        AppDockPolicy.hideFromDockIfNoUserWindows()
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            AppDockPolicy.hideFromDockIfNoUserWindows()
        }
    }
}

private enum OnboardingPage: Int, CaseIterable {
    case welcome
    case routine
    case wellness
    case ready
}

struct OnboardingView: View {
    @Environment(AppController.self) private var app
    @State private var page: OnboardingPage = .welcome
    @State private var wellnessTab: WellnessEngine.Kind = .posture

    private let workOptions: [Double] = [10, 20, 30, 45]
    private let breakOptions: [Double] = [15, 30, 45, 60]
    private let postureOptions: [Double?] = [nil, 10, 20, 30]
    private let blinkOptions: [Double?] = [nil, 5, 10, 15]

    var body: some View {
        ZStack {
            OnboardingBackdrop(page: page)
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if page != .welcome {
                    footer
                }
            }
            .padding(.top, 28)
        }
        .frame(width: 760, height: 540)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .welcome: welcomePage
        case .routine: routinePage
        case .wellness: wellnessPage
        case .ready: readyPage
        }
    }

    private var footer: some View {
        HStack {
            Button("Back") {
                withAnimation(Motion.spring) {
                    page = OnboardingPage(rawValue: max(0, page.rawValue - 1)) ?? .welcome
                }
            }
            .buttonStyle(OnboardingGhostButton())

            Spacer()

            PageDots(count: 3, index: max(0, page.rawValue - 1))

            Spacer()

            Button(page == .ready ? "Close" : "Next") {
                if page == .ready {
                    finish(startBreak: false)
                } else {
                    withAnimation(Motion.spring) {
                        page = OnboardingPage(rawValue: page.rawValue + 1) ?? .ready
                    }
                }
            }
            .buttonStyle(OnboardingPrimaryButton())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
        .padding(.top, 8)
    }

    // MARK: - Welcome

    private var welcomePage: some View {
        VStack(spacing: 28) {
            Spacer()
            LookOffMark(size: 108)
            Text("Build healthier screen habits, gently.")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
            Button("Let’s begin") {
                withAnimation(Motion.spring) { page = .routine }
            }
            .buttonStyle(OnboardingPrimaryButton(wide: true))
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 48)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Routine

    private var routinePage: some View {
        @Bindable var store = app.settingsStore
        return VStack(spacing: 22) {
            OnboardingHeader(
                symbol: "leaf.fill",
                title: "Set Your Break Routine"
            )

            HStack(alignment: .top, spacing: 18) {
                OnboardingCard(
                    title: "Time between breaks",
                    subtitle: "How long you work before LookOff starts a break. You can delay it if needed."
                ) {
                    OptionGrid(
                        options: workOptions.map { OptionItem(id: $0, title: "\(Int($0)) mins") },
                        selection: store.settings.workMinutes
                    ) { value in
                        store.settings.workMinutes = value
                        store.settings.preset = nearestPreset(work: value, breakSeconds: store.settings.shortBreakSeconds)
                    }
                }

                OnboardingCard(
                    title: "Break length",
                    subtitle: "How long the break lasts while your screen gently rests."
                ) {
                    OptionGrid(
                        options: breakOptions.map {
                            OptionItem(id: $0, title: $0 < 60 ? "\(Int($0)) secs" : "1 min")
                        },
                        selection: store.settings.shortBreakSeconds
                    ) { value in
                        store.settings.shortBreakSeconds = value
                        store.settings.preset = nearestPreset(work: store.settings.workMinutes, breakSeconds: value)
                    }
                }
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Wellness

    private var wellnessPage: some View {
        @Bindable var store = app.settingsStore
        return VStack(spacing: 18) {
            OnboardingHeader(
                symbol: "heart.fill",
                title: "Set Up Wellness Reminders"
            )

            Picker("", selection: $wellnessTab) {
                Text("Posture").tag(WellnessEngine.Kind.posture)
                Text("Blink").tag(WellnessEngine.Kind.blink)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .tint(Palette.magenta)

            HStack(alignment: .top, spacing: 18) {
                OnboardingCard(
                    title: nil,
                    subtitle: wellnessTab == .posture
                        ? "Helps maintain good posture by gently alerting you to sit upright and avoid strain."
                        : "Prevents dry eyes by gently nudging you to blink at healthy intervals."
                ) {
                    if wellnessTab == .posture {
                        OptionGrid(
                            options: postureOptions.map { opt in
                                OptionItem(id: opt ?? -1, title: opt.map { "Every \(Int($0)) mins" } ?? "Disabled")
                            },
                            selection: store.settings.postureEnabled ? store.settings.postureIntervalMinutes : -1
                        ) { value in
                            if value < 0 {
                                store.settings.postureEnabled = false
                            } else {
                                store.settings.postureEnabled = true
                                store.settings.postureIntervalMinutes = value
                            }
                        }
                    } else {
                        OptionGrid(
                            options: blinkOptions.map { opt in
                                OptionItem(id: opt ?? -1, title: opt.map { "Every \(Int($0)) mins" } ?? "Disabled")
                            },
                            selection: store.settings.blinkEnabled ? store.settings.blinkIntervalSeconds / 60 : -1
                        ) { value in
                            if value < 0 {
                                store.settings.blinkEnabled = false
                            } else {
                                store.settings.blinkEnabled = true
                                store.settings.blinkIntervalSeconds = value * 60
                            }
                        }
                    }

                    Label("You can adjust these anytime in Settings", systemImage: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }

                WellnessPreviewCard(kind: wellnessTab)
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Ready

    private var readyPage: some View {
        @Bindable var store = app.settingsStore
        return VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "hand.thumbsup.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Palette.gold)
                Text("You’re All Set!")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .padding(.top, 8)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("LookOff is now active")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(TimeFormat.overlay(store.settings.workDuration))
                        .font(.system(size: 44, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text("We’ll nudge you a minute before the break.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button {
                        finish(startBreak: true)
                    } label: {
                        Label("Start break now", systemImage: "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.gold)
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground)

                VStack(spacing: 12) {
                    MenuBarHintView()
                    Text("Control LookOff from the menu bar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Don’t see it? Check the menu bar extras overflow (‹).")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(cardBackground)

                VStack(spacing: 0) {
                    ReadyRow(
                        symbol: "power",
                        title: "Start at login",
                        subtitle: "LookOff will be ready when you are."
                    ) {
                        Toggle("", isOn: $store.settings.launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: store.settings.launchAtLogin) { _, value in
                                LoginItem.setEnabled(value)
                            }
                    }
                    Divider().opacity(0.2)
                    ReadyRow(
                        symbol: "gearshape",
                        title: "View settings",
                        subtitle: "Tune Smart Pause, sounds, and shortcuts."
                    ) {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        finish(startBreak: false)
                        app.openSettings()
                    }
                    Divider().opacity(0.2)
                    ReadyRow(
                        symbol: "lock.shield",
                        title: "Optional permissions",
                        subtitle: "Skip all. Schedule still runs. Accessibility / Calendar / Focus only if you want extras."
                    ) {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        finish(startBreak: false)
                        app.openSettings()
                    }
                }
                .frame(maxWidth: .infinity)
                .background(cardBackground)
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 0)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.clear)
            .lookOffGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func finish(startBreak: Bool) {
        LoginItem.setEnabled(app.settings.launchAtLogin)
        app.finishOnboarding()
        OnboardingWindowController.shared.close()
        if startBreak {
            app.startBreakNow()
        }
    }

    private func nearestPreset(work: Double, breakSeconds: Double) -> BreakPreset {
        if work == 20, breakSeconds == 20 { return .balanced }
        if work == 45, breakSeconds == 30 { return .deepFocus }
        if work == 15, breakSeconds == 15 { return .eyeCare }
        if work == 25, breakSeconds == 45 { return .wellness }
        return .balanced
    }
}

// MARK: - Shared chrome

private struct OnboardingBackdrop: View {
    let page: OnboardingPage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LookOffWindowBackdrop()
            LinearGradient(
                colors: [
                    Palette.purple.opacity(page == .welcome ? 0.18 : 0.08),
                    Palette.accent.opacity(0.08),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            if page == .welcome, colorScheme == .dark {
                StarField()
                    .opacity(0.55)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

private struct StarField: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: Motion.reduceMotion ? 1 : 1.0 / 20.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for i in 0..<60 {
                    let seed = Double(i) * 1.618
                    let x = (seed * 73).truncatingRemainder(dividingBy: 1) * size.width
                    let y = (seed * 29).truncatingRemainder(dividingBy: 1) * size.height
                    let twinkle = 0.25 + 0.55 * abs(sin(t * 0.6 + seed))
                    let r: CGFloat = i.isMultiple(of: 7) ? 1.8 : 1.0
                    let rect = CGRect(x: x, y: y, width: r, height: r)
                    context.fill(Circle().path(in: rect), with: .color(.white.opacity(twinkle)))
                }
            }
        }
    }
}

private struct LookOffMark: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Palette.magenta, Palette.purple, Palette.gold.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: Palette.magenta.opacity(0.35), radius: 24, y: 10)
            Image(systemName: "moon.haze.fill")
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

private struct OnboardingHeader: View {
    let symbol: String
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Palette.magenta, Palette.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: symbol)
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
    }
}

private struct OnboardingCard<Content: View>: View {
    let title: String?
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Palette.caption)
                .fixedSize(horizontal: false, vertical: true)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookOffGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct OptionItem: Hashable {
    let id: Double
    let title: String
}

private struct OptionGrid: View {
    let options: [OptionItem]
    let selection: Double
    let onSelect: (Double) -> Void

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(options, id: \.id) { item in
                let selected = abs(item.id - selection) < 0.01
                Button {
                    onSelect(item.id)
                } label: {
                    HStack {
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        Spacer(minLength: 4)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(selected ? 0.10 : 0.04))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(
                                        selected ? Palette.accent : Color.primary.opacity(0.12),
                                        lineWidth: selected ? 1.5 : 1
                                    )
                            }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct WellnessPreviewCard: View {
    let kind: WellnessEngine.Kind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.15, green: 0.22, blue: 0.28),
                            Color(red: 0.08, green: 0.12, blue: 0.18),
                            Palette.purple.opacity(0.35)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            SoftOrbs(t: 0, reduceMotion: true)
                .opacity(0.5)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            WellnessView(kind: kind, dim: false, reduceMotion: Motion.reduceMotion)
                .scaleEffect(0.92)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.glassStroke, lineWidth: 1)
        }
        .clipped()
    }
}

private struct MenuBarHintView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.haze.fill")
                .foregroundStyle(Palette.gold)
            Text("20m")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.clear)
        .lookOffGlass(in: Capsule())
    }
}

private struct ReadyRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(Palette.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == index ? Color.primary : Color.primary.opacity(0.22))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

private struct OnboardingPrimaryButton: ButtonStyle {
    var wide: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, wide ? 36 : 22)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(Palette.accent.opacity(configuration.isPressed ? 0.82 : 1))
            )
    }
}

private struct OnboardingGhostButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.06))
            )
    }
}
