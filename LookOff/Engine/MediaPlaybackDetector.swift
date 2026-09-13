import AppKit

/// Permission-free media / video detection (no Screen Recording / Mic TCC).
/// Signal: system audio output active + frontmost/running is a browser or player.
/// (Zen Browser was missing before — that broke YouTube detection.)
@MainActor
enum MediaPlaybackDetector {
    static func isVideoPlaying(frontmostOnly: Bool, denyBundleIDs: [String]) -> Bool {
        let deny = Set(denyBundleIDs)

        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, deny.contains(front) {
            if frontmostOnly { return false }
        }

        guard AudioActivity.outputRunning() else { return false }

        if frontmostOnly {
            guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
            if deny.contains(id) { return false }
            return isMediaSurface(id)
        }

        return NSWorkspace.shared.runningApplications.contains { app in
            guard let id = app.bundleIdentifier else { return false }
            if deny.contains(id) { return false }
            return isMediaSurface(id)
        }
    }

    static func isMediaSurface(_ bundleID: String) -> Bool {
        if knownPlayers.contains(bundleID) || knownBrowsers.contains(bundleID) { return true }
        let id = bundleID.lowercased()
        return isLikelyBrowser(bundleID)
            || id.contains("vlc")
            || id.contains("iina")
            || id.contains("spotify")
            || id.contains("netflix")
            || id.contains("quicktime")
    }

    static func isLikelyBrowser(_ bundleID: String) -> Bool {
        if knownBrowsers.contains(bundleID) { return true }
        let id = bundleID.lowercased()
        return id.hasPrefix("app.zen-browser")
            || id.contains("firefox")
            || id.contains(".chrome")
            || id.contains("chromium")
            || id.contains("safari")
            || id.contains("edgemac")
            || id.contains("brave")
            || id.contains("vivaldi")
            || id.contains("opera")
            || (id.contains("browser") && !id.contains("lookoff"))
    }

    /// Native players only (not browsers) — for "playing anywhere" without sticky YouTube.
    static func isNativePlayer(_ bundleID: String) -> Bool {
        knownPlayers.contains(bundleID)
    }

    private static let knownBrowsers: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "company.thebrowser.Browser",
        "company.thebrowser.dia",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "app.zen-browser.zen",
        "app.zen-browser.zen.nightly",
        "com.kagi.kagimacOS",
        "com.apple.Safari.WebApp"
    ]

    private static let knownPlayers: Set<String> = [
        "com.apple.TV",
        "com.apple.Music",
        "com.apple.QuickTimePlayerX",
        "com.colliderli.iina",
        "org.videolan.vlc",
        "com.spotify.client",
        "com.netflix.Netflix",
        "com.amazon.aiv.AIVApp"
    ]
}
