import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private var item: NSStatusItem?
    private weak var app: AppController?
    private var snapshot = EngineSnapshot.idle
    private let model = MenuBarPopoverModel()
    private var panel: OverlayPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    private let titleFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
    private let panelGap: CGFloat = 5

    func install(_ app: AppController) {
        self.app = app
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageLeading
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.imageHugsTitle = true
        item.button?.font = titleFont
        item.button?.setButtonType(.momentaryPushIn)
        item.button?.target = self
        item.button?.action = #selector(togglePanel(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        self.item = item
        apply(app.snapshot)
    }

    func apply(_ snapshot: EngineSnapshot) {
        self.snapshot = snapshot
        model.snapshot = snapshot
        if let settings = app?.settings {
            model.shortBreakSeconds = settings.shortBreakDuration
            model.longBreakSeconds = settings.longBreakDuration
            model.workMinutes = settings.workMinutes
        }
        if let stats = app?.stats {
            model.today = stats.today()
            model.currentFocusSeconds = stats.currentFocusSeconds
        }

        guard let button = item?.button else { return }
        let icon = StatusIcon.forSnapshot(snapshot)
        button.image = StatusMark.menuBarImage(icon, accessibilityDescription: statusAccessibility(snapshot))
        button.toolTip = tooltip(snapshot)
        button.appearsDisabled = false
        button.title = snapshot.menuTitle
        button.font = titleFont
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton?) {
        if panel?.isVisible == true {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard item?.button != nil else { return }
        refreshModel()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        positionPanel(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
        startDismissMonitoring()
    }

    private func closePanel() {
        stopDismissMonitoring()
        panel?.orderOut(nil)
    }

    private func refreshModel() {
        model.snapshot = snapshot
        if let settings = app?.settings {
            model.shortBreakSeconds = settings.shortBreakDuration
            model.longBreakSeconds = settings.longBreakDuration
            model.workMinutes = settings.workMinutes
        }
        if let stats = app?.stats {
            model.today = stats.today()
            model.currentFocusSeconds = stats.currentFocusSeconds
        }
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel(
            frame: NSRect(x: 0, y: 0, width: 400, height: 480),
            allowsKey: true,
            sharingHidden: false
        )
        panel.level = .popUpMenu
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .utilityWindow

        let root = MenuBarPopoverView(
            model: model,
            onStartBreak: { [weak self] in
                self?.app?.startBreakNow()
                self?.closePanel()
            },
            onSnooze: { [weak self] minutes in
                self?.app?.snooze(minutes: minutes)
                self?.closePanel()
            },
            onTogglePause: { [weak self] in
                self?.app?.togglePause()
            },
            onToggleSchedule: { [weak self] in
                guard let self, let app = self.app else { return }
                if self.model.isRunning {
                    app.stopSchedule()
                } else {
                    app.startSchedule()
                }
            },
            onEndBreak: { [weak self] in
                self?.app?.endBreak()
                self?.closePanel()
            },
            onSkip: { [weak self] in
                self?.app?.skip()
                self?.closePanel()
            },
            onSettings: { [weak self] in
                self?.closePanel()
                self?.app?.openSettings()
            },
            onStats: { [weak self] in
                self?.closePanel()
                self?.app?.openSettings(tab: .stats)
            },
            onQuit: {
                NSApp.terminate(nil)
            },
            onSizeChange: { [weak self] size in
                self?.resizePanel(to: size)
            }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
        return panel
    }

    private func resizePanel(to size: CGSize) {
        guard let panel else { return }
        let width = ceil(size.width)
        let height = ceil(size.height)
        guard width > 1, height > 1 else { return }
        var frame = panel.frame
        if abs(frame.width - width) < 0.5, abs(frame.height - height) < 0.5 {
            return
        }
        frame.size = NSSize(width: width, height: height)
        panel.setFrame(frame, display: true)
        if panel.isVisible {
            positionPanel(panel)
        }
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let button = item?.button, let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        var x = buttonRect.midX - size.width / 2
        var y = buttonRect.minY - size.height - panelGap
        let screen = buttonWindow.screen ?? NSScreen.main
        if let vis = screen?.visibleFrame {
            x = min(max(x, vis.minX + 8), vis.maxX - size.width - 8)
            if y < vis.minY {
                y = vis.minY + 8
            }
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func startDismissMonitoring() {
        stopDismissMonitoring()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            Task { @MainActor in
                self?.dismissIfClickOutside(event)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.closePanel()
                return nil
            }
            if event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown {
                self.dismissIfClickOutside(event)
            }
            return event
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closePanel()
            }
        }
    }

    private func stopDismissMonitoring() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
    }

    private func dismissIfClickOutside(_ event: NSEvent) {
        guard panel?.isVisible == true else { return }

        let screenPoint: NSPoint = {
            if event.window == nil {
                return event.locationInWindow
            }
            return event.window!.convertPoint(toScreen: event.locationInWindow)
        }()

        if let panel, panel.frame.contains(screenPoint) {
            return
        }

        if let button = item?.button, let buttonWindow = button.window {
            let rectInWindow = button.convert(button.bounds, to: nil)
            let screenRect = buttonWindow.convertToScreen(rectInWindow)
            if screenRect.contains(screenPoint) {
                return
            }
        }

        closePanel()
    }

    private func statusAccessibility(_ snapshot: EngineSnapshot) -> String {
        if let reason = snapshot.pauseReason, snapshot.phase != .onBreak {
            return reason.statusBarTitle
        }
        return "LookOff"
    }

    private func tooltip(_ snapshot: EngineSnapshot) -> String {
        let today = app?.stats.today() ?? DayStats(day: "")
        let score = min(max(today.screenScore(workMinutes: app?.settings.workMinutes ?? 20), 0), 100)
        let statsLine = "Score \(score) · \(TimeFormat.compact(today.screenSeconds)) · \(today.breaksTaken) breaks"
        if !snapshot.scheduleEnabled || snapshot.phase == .stopped {
            return "LookOff is off — click to open\n\(statsLine)"
        }
        if let reason = snapshot.pauseReason {
            switch reason {
            case .idle:
                return "LookOff paused while you’re away · \(TimeFormat.overlay(snapshot.remaining)) remaining\n\(statsLine)"
            case .video:
                return "LookOff paused for video playback · \(TimeFormat.overlay(snapshot.remaining)) remaining\n\(statsLine)"
            default:
                return "\(reason.statusBarTitle) · \(TimeFormat.overlay(snapshot.remaining)) remaining\n\(statsLine)"
            }
        }
        return "LookOff · \(snapshot.menuTitle)\n\(statsLine)"
    }
}
