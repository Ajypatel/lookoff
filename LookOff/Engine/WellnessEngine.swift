import Foundation

@MainActor
final class WellnessEngine {
    enum Kind: String {
        case blink
        case posture
    }

    private var timer: DispatchSourceTimer?
    private var lastBlink = Date()
    private var lastPosture = Date()
    private var settings = AppSettings()
    private var paused = false
    var onFire: ((Kind) -> Void)?

    func start(settings: AppSettings, onFire: @escaping (Kind) -> Void) {
        self.settings = settings
        self.onFire = onFire
        lastBlink = Date()
        lastPosture = Date()
        stop()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        self.timer = timer
    }

    func update(settings: AppSettings) {
        self.settings = settings
    }

    func setPaused(_ paused: Bool) {
        self.paused = paused
        if paused == false, settings.resetWellnessAfterBreak {
            reset()
        }
    }

    func reset() {
        lastBlink = Date()
        lastPosture = Date()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        guard !paused else { return }
        let now = Date()
        if settings.blinkEnabled, now.timeIntervalSince(lastBlink) >= settings.blinkIntervalSeconds {
            lastBlink = now
            onFire?(.blink)
        }
        if settings.postureEnabled, now.timeIntervalSince(lastPosture) >= settings.postureIntervalMinutes * 60 {
            lastPosture = now
            onFire?(.posture)
        }
    }
}
