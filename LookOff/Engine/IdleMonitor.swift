import AppKit
import CoreGraphics

@MainActor
final class IdleMonitor {
    var idleSeconds: TimeInterval = 0
    var isIdle = false
    var isTyping = false
    var isDragging = false
    var spoofWarning = false

    private var poll: DispatchSourceTimer?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var lastKeyAt: Date?
    private var mouseIsDown = false
    private var threshold: TimeInterval = 120
    private var typingDebounce: TimeInterval = 1.5
    private var onChange: (() -> Void)?

    func start(threshold: TimeInterval, onChange: @escaping () -> Void) {
        self.threshold = threshold
        self.onChange = onChange
        stop()

        startIdlePoll()
        rebindInputMonitors()
    }

    func rebindInputMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        keyMonitor = nil
        mouseMonitor = nil

        guard PermissionManager.accessibilityTrusted() else {
            isTyping = false
            isDragging = false
            mouseIsDown = false
            return
        }

        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] _ in
            Task { @MainActor in
                self?.lastKeyAt = Date()
                self?.isTyping = true
                self?.onChange?()
            }
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            Task { @MainActor in
                switch event.type {
                case .leftMouseDown, .leftMouseDragged:
                    self?.mouseIsDown = true
                    self?.isDragging = true
                case .leftMouseUp:
                    self?.mouseIsDown = false
                    self?.isDragging = false
                default:
                    break
                }
                self?.onChange?()
            }
        }
    }

    func updateThreshold(_ threshold: TimeInterval) {
        self.threshold = threshold
    }

    func stop() {
        poll?.cancel()
        poll = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        keyMonitor = nil
        mouseMonitor = nil
    }

    private func startIdlePoll() {
        poll?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            self?.pollTick()
        }
        timer.resume()
        poll = timer
    }

    private func pollTick() {
        idleSeconds = Self.secondsSinceLastInput()
        let wasIdle = isIdle
        isIdle = idleSeconds >= threshold
        if let lastKeyAt {
            isTyping = Date().timeIntervalSince(lastKeyAt) < typingDebounce
        }
        isDragging = mouseIsDown
        spoofWarning = idleSeconds < 0.4 && Self.knownIdleSpoofersRunning()
        if wasIdle != isIdle || isTyping || isDragging || spoofWarning {
            onChange?()
        } else if isIdle {
            onChange?()
        }
    }

    static func secondsSinceLastInput() -> TimeInterval {
        let types: [CGEventType] = [.mouseMoved, .keyDown, .scrollWheel, .leftMouseDown, .rightMouseDown, .flagsChanged]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    static func knownIdleSpoofersRunning() -> Bool {
        let ids: Set<String> = [
            "com.if.Amphetamine",
            "com.lightheadsw.Caffeine",
            "net.nickolasdewing.KeepingYouAwake",
            "com.intelliscapesolutions.caffeine"
        ]
        return NSWorkspace.shared.runningApplications.contains { app in
            guard let id = app.bundleIdentifier else { return false }
            return ids.contains(id)
        }
    }
}
