import AppKit
import Foundation

@objc(StartNextBreakCommand)
final class StartNextBreakCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in AppController.shared.startBreakNow() }
        return nil
    }
}

@objc(StartLongBreakCommand)
final class StartLongBreakCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in AppController.shared.startLongBreak() }
        return nil
    }
}

@objc(StartCustomBreakCommand)
final class StartCustomBreakCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let seconds = intArg("durationSeconds", fallback: 20)
        let message = evaluatedArguments?["message"] as? String
        Task { @MainActor in
            AppController.shared.startCustomBreak(seconds: TimeInterval(seconds), message: message)
        }
        return nil
    }
}

@objc(PauseLookOffCommand)
final class PauseLookOffCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in AppController.shared.pauseFromScript() }
        return nil
    }
}

@objc(PauseTemporarilyCommand)
final class PauseTemporarilyCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let seconds = intArg("seconds", fallback: 60)
        Task { @MainActor in AppController.shared.pauseTemporarily(seconds: TimeInterval(seconds)) }
        return nil
    }
}

@objc(PostponeBreakCommand)
final class PostponeBreakCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let seconds = intArg("seconds", fallback: 300)
        Task { @MainActor in AppController.shared.postponeBreak(seconds: TimeInterval(seconds)) }
        return nil
    }
}

@objc(ResumeLookOffCommand)
final class ResumeLookOffCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in AppController.shared.resumeFromScript() }
        return nil
    }
}

@objc(OpenSettingsCommand)
final class OpenSettingsCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in AppController.shared.openSettings() }
        return nil
    }
}

private extension NSScriptCommand {
    func intArg(_ key: String, fallback: Int) -> Int {
        if let value = evaluatedArguments?[key] as? Int { return value }
        if let value = evaluatedArguments?[key] as? NSNumber { return value.intValue }
        return fallback
    }
}
