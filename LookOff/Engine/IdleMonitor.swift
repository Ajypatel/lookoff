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
    private var lastIdleBucket: Int = -1
    private var lastSpoofScan: Date = .distantPast
    private var cachedSpoof = false

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
        let wasTyping = isTyping
        let wasDragging = isDragging
        if let lastKeyAt {
            isTyping = Date().timeIntervalSince(lastKeyAt) < typingDebounce
        } else {
            isTyping = false
        }
        isDragging = mouseIsDown

        let now = Date()
        if now.timeIntervalSince(lastSpoofScan) >= 5 {
            cachedSpoof = Self.knownIdleSpoofersRunning()
            lastSpoofScan = now
        }
        let wasSpoof = spoofWarning
        spoofWarning = idleSeconds < 0.4 && cachedSpoof

        let idleBucket = Int(idleSeconds / 5)
        let crossed = wasIdle != isIdle
            || wasTyping != isTyping
            || wasDragging != isDragging
            || wasSpoof != spoofWarning
        if crossed {
            lastIdleBucket = idleBucket
            onChange?()
            return
        }
        // While idle, only refresh engine every ~5s — not every poll.
        if isIdle, idleBucket != lastIdleBucket {
            lastIdleBucket = idleBucket
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
