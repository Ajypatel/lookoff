import AppKit
import CoreGraphics
import Observation
import SwiftUI

@MainActor
final class OverlayPanel: NSPanel {
    var allowsKey = true

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    convenience init(frame: NSRect, allowsKey: Bool = true, sharingHidden: Bool) {
        self.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.allowsKey = allowsKey
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        sharingType = sharingHidden ? .none : .readOnly
        isReleasedWhenClosed = false
        animationBehavior = .none
        alphaValue = 1
        appearance = NSApp.effectiveAppearance
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.appearance = NSApp.effectiveAppearance
            }
        }
    }

    private var appearanceObserver: NSKeyValueObservation?

    /// Break screens stay capturable (LookAway default). Wellness can opt out via `.none`.
    func applyCapturePolicy(hiddenFromCapture: Bool) {
        sharingType = hiddenFromCapture ? .none : .readOnly
    }
}

@MainActor
@Observable
final class OverlayLiveState {
    var snapshot = EngineSnapshot.idle
    var settings = AppSettings()
    var customWallpaper: NSImage?
    var reduceMotion = false
    /// Bumped each show so SwiftUI restarts fade-in.
    var showGeneration: Int = 0
    var isDismissing = false
}

@MainActor
final class BreakOverlayController {
    private var panels: [CGDirectDisplayID: OverlayPanel] = [:]
    private var visible = false
    private var hideWork: DispatchWorkItem?
    private let live = OverlayLiveState()
    private let fadeDuration: TimeInterval = 0.32

    var onSkip: (() -> Void)?
    var onEnd: (() -> Void)?
    var onLock: (() -> Void)?
    var onExtend: ((Int) -> Void)?
    var onSecondTick: ((Int) -> Void)?
    var onStage: ((BreakSoundStage) -> Void)?

    func apply(snapshot: EngineSnapshot, settings: AppSettings) {
        let onBreak = snapshot.phase == .onBreak
        let bookmarkChanged = live.settings.wallpaperBookmark != settings.wallpaperBookmark
        live.reduceMotion = settings.respectReduceMotion && Motion.reduceMotion

        if bookmarkChanged || (live.customWallpaper == nil && settings.wallpaperBookmark != nil) {
            live.settings = settings
            live.customWallpaper = WallpaperLoader.image(from: settings.wallpaperBookmark)
        }

        // Skip Observation churn when overlay is not involved.
        if onBreak || visible {
            live.snapshot = snapshot
            live.settings = settings
        }

        if onBreak {
            if !visible {
                show()
            }
        } else if visible {
            hideAnimated()
        }
    }

    func show() {
        hideWork?.cancel()
        hideWork = nil
        live.isDismissing = false
        recreateIfNeeded()
        visible = true
        live.showGeneration &+= 1

        for (displayID, panel) in panels {
            guard let screen = screen(for: displayID) else { continue }
            // Use full screen frame; hosting fills panel bounds exactly (no right shift)
            panel.setFrame(screen.frame, display: true)
            installContent(on: panel, screen: screen)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
        panels.values.first?.makeKey()
    }

    func hideAnimated() {
        guard visible else { return }
        hideWork?.cancel()
        live.isDismissing = true

        let duration = live.reduceMotion ? 0.15 : fadeDuration
        // Single AppKit fade of whole panel — avoids SwiftUI material opacity flicker
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            for panel in panels.values {
                panel.animator().alphaValue = 0
            }
        }, completionHandler: { [weak self] in
            self?.finishHide()
        })
    }

    func hide() {
        hideWork?.cancel()
        finishHide()
    }

    private func finishHide() {
        visible = false
        live.isDismissing = false
        for panel in panels.values {
            panel.orderOut(nil)
            // Keep hosting — next break reuses tree; only refresh backdrop.
        }
    }

    func handleScreenChange() {
        let wasOnBreak = visible && live.snapshot.phase == .onBreak
        destroy()
        if wasOnBreak {
            show()
        }
    }

    private func destroy() {
        hideWork?.cancel()
        for panel in panels.values {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panels.removeAll()
        visible = false
        live.isDismissing = false
    }

    private func recreateIfNeeded() {
        let screens = NSScreen.screens
        let ids = Set(screens.map(Self.displayID))
        for stale in panels.keys where !ids.contains(stale) {
            panels[stale]?.orderOut(nil)
            panels.removeValue(forKey: stale)
        }
        for screen in screens {
            let id = Self.displayID(screen)
            if panels[id] == nil {
                // Break overlay always capturable — screenshots / OBS see the rest screen
                panels[id] = OverlayPanel(
                    frame: screen.frame,
                    allowsKey: true,
                    sharingHidden: false
                )
            } else {
                panels[id]?.applyCapturePolicy(hiddenFromCapture: false)
            }
        }
        // Absolute fallback — never leave user with zero panels
        if panels.isEmpty, let screen = screens.first ?? NSScreen.main {
            panels[0] = OverlayPanel(
                frame: screen.frame,
                allowsKey: true,
                sharingHidden: false
            )
        }
    }

    private func installContent(on panel: OverlayPanel, screen: NSScreen) {
        // Freeze pixels BEFORE ordering front — Cmd+Tab must not refresh backdrop.
        let displayID = Self.displayID(screen)
        let frozen = FrozenBackdrop.capture(screen: screen, displayID: displayID)
            ?? live.customWallpaper
            ?? DesktopWallpaper.image(for: screen)
        let safeTop = screen.safeAreaInsets.top
        let bounds = CGRect(origin: .zero, size: panel.frame.size)

        if let existing = panel.contentView as? NSHostingView<BreakOverlayRoot> {
            existing.rootView = BreakOverlayRoot(
                live: live,
                frozenBackdrop: frozen,
                safeTop: safeTop,
                fadeDuration: fadeDuration,
                onSkip: { [weak self] in self?.onSkip?() },
                onEnd: { [weak self] in self?.onEnd?() },
                onLock: { [weak self] in self?.onLock?() },
                onExtend: { [weak self] minutes in self?.onExtend?(minutes) },
                onSecondTick: { [weak self] second in self?.onSecondTick?(second) },
                onStage: { [weak self] stage in self?.onStage?(stage) }
            )
            existing.frame = bounds
            return
        }

        let root = BreakOverlayRoot(
            live: live,
            frozenBackdrop: frozen,
            safeTop: safeTop,
            fadeDuration: fadeDuration,
            onSkip: { [weak self] in self?.onSkip?() },
            onEnd: { [weak self] in self?.onEnd?() },
            onLock: { [weak self] in self?.onLock?() },
            onExtend: { [weak self] minutes in self?.onExtend?(minutes) },
            onSecondTick: { [weak self] second in self?.onSecondTick?(second) },
            onStage: { [weak self] stage in self?.onStage?(stage) }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        // Must stay clear — opaque layer survives SwiftUI fade and blacks out screen on exit
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        panel.contentView = hosting
        panel.contentView?.frame = bounds
    }

    private func screen(for id: CGDirectDisplayID) -> NSScreen? {
        if let match = NSScreen.screens.first(where: { Self.displayID($0) == id }) {
            return match
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return num.uint32Value
        }
        return CGDirectDisplayID(abs(ObjectIdentifier(screen).hashValue) % Int(UInt32.max - 1) + 1)
    }
}

enum FrozenBackdrop {
    /// Wallpaper / custom image only — never CGDisplayCreateImage (that triggers
    /// Screen & System Audio Recording TCC). Static file = Cmd+Tab safe too.
    static func capture(screen: NSScreen, displayID: CGDirectDisplayID) -> NSImage? {
        _ = displayID
        return DesktopWallpaper.image(for: screen)
    }
}

enum DesktopWallpaper {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [CGDirectDisplayID: (path: String, image: NSImage)] = [:]

    static func image(for screen: NSScreen) -> NSImage? {
        let displayID: CGDirectDisplayID = {
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                return num.uint32Value
            }
            return 0
        }()
        let url = NSWorkspace.shared.desktopImageURL(for: screen)
        let path = url?.path ?? ""
        lock.lock()
        let hit = cache[displayID]
        lock.unlock()
        if let hit, hit.path == path {
            return hit.image
        }
        guard let url else { return nil }
        // Dynamic wallpapers may be .heic packages — try direct load, then first image rep.
        let loaded: NSImage? = {
            if let image = NSImage(contentsOf: url), image.size.width > 0 {
                return image
            }
            if let reps = NSBitmapImageRep.imageReps(withContentsOf: url), let first = reps.first {
                let image = NSImage(size: first.size)
                image.addRepresentation(first)
                return image
            }
            return nil
        }()
        if let loaded {
            lock.lock()
            cache[displayID] = (path, loaded)
            lock.unlock()
        }
        return loaded
    }
}

enum WallpaperLoader {
    static func image(from bookmark: Data?) -> NSImage? {
        guard let bookmark else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return NSImage(contentsOf: url)
    }
}

enum ScreenLocker {
    static func lock() {
        let session = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        if FileManager.default.isExecutableFile(atPath: session) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: session)
            process.arguments = ["-suspend"]
            try? process.run()
            return
        }
        if lockViaLoginFramework() { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        try? task.run()
    }

    private static func lockViaLoginFramework() -> Bool {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY) else {
            return false
        }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "SACLockScreenImmediate") else { return false }
        typealias LockFn = @convention(c) () -> Void
        unsafeBitCast(symbol, to: LockFn.self)()
        return true
    }
}
