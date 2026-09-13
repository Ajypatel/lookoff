import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private let defaultsKey = "lookoff.settings.v1"
    var settings: AppSettings {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = Self.decode(data) {
            var settings = decoded
            Self.migrate(&settings)
            self.settings = settings
        } else {
            settings = AppSettings()
        }
    }

    func applyPreset(_ preset: BreakPreset) {
        var next = settings
        preset.apply(to: &next)
        settings = next
    }

    func resetMessages() {
        settings.overlayMessages = []
        settings.breakInstruction = ""
    }

    /// One-shot upgrades for defaults users never customized.
    private static func migrate(_ settings: inout AppSettings) {
        // Old default wait was 8s — nudge to 6 if still on that stock value.
        if settings.skipUnlockSeconds == 8 {
            settings.skipUnlockSeconds = 6
        }
        // LookAway-style idle: pause 1m (was 2m stock).
        if settings.idlePauseSeconds == 120 {
            settings.idlePauseSeconds = 60
        }
        // Expand quote pool if still on the original short list (or empty).
        let legacyMessages = [
            "Eyes to the horizon",
            "Time for a quick reset",
            "Look twenty feet out",
            "Soften the stare. Blink",
            "Unfocus. Let the room blur"
        ]
        let stockMessages = Set(AppSettings.defaultMessages + legacyMessages)
        settings.overlayMessages = settings.overlayMessages.filter {
            let line = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !line.isEmpty && !stockMessages.contains(line)
        }
        if settings.breakInstruction == AppSettings.defaultInstruction
            || AppSettings.defaultInstructions.contains(settings.breakInstruction) {
            settings.breakInstruction = ""
        }
    }

    /// Patch missing keys so additive settings don’t wipe the whole file.
    private static func decode(_ data: Data) -> AppSettings? {
        if let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return decoded
        }
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if json["idleResetSeconds"] == nil {
            json["idleResetSeconds"] = 300
        }
        if json["wellnessSize"] == nil {
            json["wellnessSize"] = "large"
        }
        if json["wellnessScreenPosition"] == nil {
            json["wellnessScreenPosition"] = "center"
        }
        if json["wellnessDuringSmartPause"] == nil {
            json["wellnessDuringSmartPause"] = false
        }
        if json["soundPair"] == nil { json["soundPair"] = "lookoffDefault" }
        if json["playBreakStart"] == nil { json["playBreakStart"] = true }
        if json["playBreakEnd"] == nil { json["playBreakEnd"] = true }
        if json["breakSoundVolume"] == nil { json["breakSoundVolume"] = 0.7 }
        if json["postureSoundEnabled"] == nil { json["postureSoundEnabled"] = true }
        if json["blinkSoundEnabled"] == nil { json["blinkSoundEnabled"] = true }
        if json["wellnessSoundVolume"] == nil { json["wellnessSoundVolume"] = 0.7 }
        if json["headsUpSoundEnabled"] == nil { json["headsUpSoundEnabled"] = true }
        if json["smartPauseSoundEnabled"] == nil { json["smartPauseSoundEnabled"] = true }
        if json["idleReturnSoundEnabled"] == nil { json["idleReturnSoundEnabled"] = false }
        if json["overtimeSoundEnabled"] == nil { json["overtimeSoundEnabled"] = true }
        if json["alertSoundVolume"] == nil { json["alertSoundVolume"] = 0.7 }
        if json["lockMacOnBreakStart"] == nil { json["lockMacOnBreakStart"] = false }
        if json["overtimeNudgeEnabled"] == nil { json["overtimeNudgeEnabled"] = true }
        if json["headsUpStaySeconds"] == nil { json["headsUpStaySeconds"] = 0 }
        if json["plannedBreaks"] == nil { json["plannedBreaks"] = [] }
        if json["automations"] == nil { json["automations"] = [] }
        guard let patched = try? JSONSerialization.data(withJSONObject: json),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: patched) else {
            return nil
        }
        return decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
