import AppKit

/// Back-compat wrapper around `StatusMark`.
enum MenuBarMark {
    static func image(
        size: CGFloat = 18,
        accessibilityDescription: String = "LookOff"
    ) -> NSImage {
        StatusMark.image(.rest, size: size, accessibilityDescription: accessibilityDescription)
    }

    static func badged(
        symbolName: String,
        size: CGFloat = 18,
        accessibilityDescription: String
    ) -> NSImage {
        StatusMark.symbolImage(symbolName, size: size, accessibilityDescription: accessibilityDescription)
    }
}
