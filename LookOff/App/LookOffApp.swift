import AppKit
import SwiftUI

@main
struct LookOffApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsRootView()
                .environment(AppController.shared)
                .frame(minWidth: 840, minHeight: 560)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppController.shared.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            AppController.shared.openSettings()
        } else {
            AppDockPolicy.showInDock()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppController.shared.persistStatsNow()
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsRootView()
                    .environment(AppController.shared)
                    .frame(minWidth: 840, minHeight: 560)
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = "LookOff"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 880, height: 700))
            window.contentMinSize = NSSize(width: 840, height: 560)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        AppDockPolicy.showInDock()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // isReleasedWhenClosed = false → orderOut path; still fire willClose on close button
        DispatchQueue.main.async {
            AppDockPolicy.hideFromDockIfNoUserWindows()
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        AppDockPolicy.showInDock()
    }
}
