import AppKit
import Foundation

@MainActor
enum AutomationRunner {
    static func run(_ items: [BreakAutomation], trigger: AutomationTrigger) {
        let jobs = items.filter { $0.enabled && $0.trigger == trigger && !$0.payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for job in jobs {
            switch job.kind {
            case .shortcut:
                runProcess("/usr/bin/shortcuts", arguments: ["run", job.payload])
            case .appleScript:
                runAppleScript(job.payload)
            case .shell:
                runProcess("/bin/zsh", arguments: ["-lc", job.payload])
            }
        }
    }

    private static func runAppleScript(_ source: String) {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        _ = script?.executeAndReturnError(&error)
        if let error {
            NSLog("LookOff automation AppleScript: \(error)")
        }
    }

    private static func runProcess(_ launch: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("LookOff automation failed: \(error.localizedDescription)")
        }
    }
}
