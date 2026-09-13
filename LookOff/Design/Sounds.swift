import AVFoundation
import AppKit

enum BreakSoundStage: String {
    case enterBlur
    case enterClock
    case enterTitle
    case enterTimer
    case enterControls
    case exitFast
    case skipUnlocked
    case tick
}

@MainActor
final class SoundPlayer {
    private var players: [AVAudioPlayer] = []

    func playStart(_ settings: AppSettings) {
        guard settings.soundEnabled, settings.playBreakStart else { return }
        let vol = Float(settings.breakSoundVolume)
        if settings.soundPair == .custom, settings.customStartBookmark != nil {
            play(named: settings.startSoundName, bookmark: settings.customStartBookmark, enabled: true, volume: vol * 0.8)
            return
        }
        playPaired(settings, enter: true, volume: vol)
    }

    func playEnd(_ settings: AppSettings) {
        guard settings.soundEnabled, settings.playBreakEnd else { return }
        let vol = Float(settings.breakSoundVolume)
        if settings.soundPair == .custom, settings.customEndBookmark != nil {
            play(named: settings.endSoundName, bookmark: settings.customEndBookmark, enabled: true, volume: vol * 0.75)
            return
        }
        playPaired(settings, enter: false, volume: vol)
    }

    func playWellnessEnter(_ settings: AppSettings, kind: WellnessEngine.Kind) {
        guard wellnessOn(settings, kind: kind) else { return }
        play(named: "enter-content", bookmark: nil, enabled: true, volume: Float(settings.wellnessSoundVolume) * 0.9)
    }

    func playWellnessTick(_ settings: AppSettings, kind: WellnessEngine.Kind) {
        guard wellnessOn(settings, kind: kind) else { return }
        play(named: "tick", bookmark: nil, enabled: true, volume: Float(settings.wellnessSoundVolume) * 0.45)
    }

    func playWellnessRise(_ settings: AppSettings, kind: WellnessEngine.Kind) {
        guard wellnessOn(settings, kind: kind) else { return }
        play(named: "unlock", bookmark: nil, enabled: true, volume: Float(settings.wellnessSoundVolume) * 0.6)
    }

    func playWellnessHappy(_ settings: AppSettings, kind: WellnessEngine.Kind) {
        guard wellnessOn(settings, kind: kind) else { return }
        play(named: "nudge", bookmark: nil, enabled: true, volume: Float(settings.wellnessSoundVolume) * 0.75)
    }

    func playWellnessExit(_ settings: AppSettings, kind: WellnessEngine.Kind) {
        guard wellnessOn(settings, kind: kind) else { return }
        play(named: "exit-content", bookmark: nil, enabled: true, volume: Float(settings.wellnessSoundVolume) * 0.7)
    }

    func playNudge(_ settings: AppSettings) {
        guard settings.soundEnabled, settings.headsUpSoundEnabled else { return }
        play(named: "nudge", bookmark: nil, enabled: true, volume: Float(settings.alertSoundVolume) * 0.7)
    }

    func playSmartPauseAlert(_ settings: AppSettings) {
        guard settings.soundEnabled, settings.smartPauseSoundEnabled else { return }
        play(named: "nudge", bookmark: nil, enabled: true, volume: Float(settings.alertSoundVolume) * 0.65)
    }

    func playIdleReturn(_ settings: AppSettings) {
        guard settings.soundEnabled, settings.idleReturnSoundEnabled else { return }
        play(named: "unlock", bookmark: nil, enabled: true, volume: Float(settings.alertSoundVolume) * 0.55)
    }

    func playOvertime(_ settings: AppSettings) {
        guard settings.soundEnabled, settings.overtimeSoundEnabled else { return }
        play(named: "tick", bookmark: nil, enabled: true, volume: Float(settings.alertSoundVolume) * 0.5)
    }

    func playStage(_ stage: BreakSoundStage, settings: AppSettings) {
        guard settings.soundEnabled else { return }
        let vol = Float(settings.breakSoundVolume)
        switch stage {
        case .enterBlur:
            play(named: "enter-blur", bookmark: nil, enabled: true, volume: vol * 0.63)
        case .enterClock:
            play(named: "tick", bookmark: nil, enabled: true, volume: vol * 0.31)
        case .enterTitle:
            play(named: "enter-content", bookmark: nil, enabled: true, volume: vol * 0.83)
        case .enterTimer:
            play(named: "unlock", bookmark: nil, enabled: true, volume: vol * 0.4)
        case .enterControls:
            play(named: "nudge", bookmark: nil, enabled: true, volume: vol * 0.43)
        case .exitFast:
            play(named: "exit-content", bookmark: nil, enabled: true, volume: vol * 0.57)
        case .skipUnlocked:
            play(named: "unlock", bookmark: nil, enabled: true, volume: vol * 0.51)
        case .tick:
            play(named: "tick", bookmark: nil, enabled: true, volume: vol * 0.26)
        }
    }

    func playTick(_ settings: AppSettings, second: Int) {
        guard settings.soundEnabled else { return }
        let vol: Float = second <= 2 ? 0.26 : 0.14
        play(named: "tick", bookmark: nil, enabled: true, volume: vol * Float(settings.breakSoundVolume))
    }

    func previewPair(_ settings: AppSettings, enter: Bool) {
        guard settings.soundEnabled else { return }
        playPaired(settings, enter: enter, volume: Float(settings.breakSoundVolume))
    }

    private func wellnessOn(_ settings: AppSettings, kind: WellnessEngine.Kind) -> Bool {
        guard settings.soundEnabled else { return false }
        switch kind {
        case .posture: return settings.postureSoundEnabled
        case .blink: return settings.blinkSoundEnabled
        }
    }

    private func playPaired(_ settings: AppSettings, enter: Bool, volume: Float) {
        if settings.soundPair == .lookoffDefault {
            play(named: enter ? "enter-content" : "exit-content", bookmark: nil, enabled: true, volume: volume * 0.7)
            return
        }
        let name = enter ? settings.soundPair.enterSystemSound : settings.soundPair.exitSystemSound
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = volume
        sound.play()
    }

    private func play(named: String, bookmark: Data?, enabled: Bool, volume: Float) {
        guard enabled else { return }
        let url: URL? = {
            if let bookmark, let resolved = resolve(bookmark) { return resolved }
            return Bundle.main.url(forResource: named, withExtension: "wav")
        }()
        if let url {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = volume
                player.prepareToPlay()
                player.play()
                players.append(player)
                players = players.filter(\.isPlaying).suffix(6).map { $0 }
                return
            } catch {
                NSLog("LookOff sound failed: \(error.localizedDescription)")
            }
        }
        let systemName: String = {
            switch named {
            case "nudge", "enter-content", "enter-blur": return "Glass"
            case "tick": return "Tink"
            case "unlock": return "Pop"
            case "exit-content": return "Purr"
            default: return "Tink"
            }
        }()
        guard let sound = NSSound(named: NSSound.Name(systemName)) else { return }
        sound.volume = volume
        sound.play()
    }

    private func resolve(_ bookmark: Data) -> URL? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }
}
