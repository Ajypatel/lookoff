import AppKit
import SwiftUI

/// Tahoe Liquid Glass with a material fallback on macOS 14–15.
enum LookOffGlass {
    static var isLiquid: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

struct LookOffGlassContainer<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

extension View {
    /// Glass fill behind this view, clipped to `shape`.
    @ViewBuilder
    func lookOffGlass<S: InsettableShape>(
        in shape: S,
        interactive: Bool = false,
        clear: Bool = false
    ) -> some View {
        if #available(macOS 26.0, *) {
            modifier(LookOffLiquidGlassModifier(shape: shape, interactive: interactive, clear: clear))
        } else {
            background {
                shape.fill(.ultraThinMaterial)
            }
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.8)
            }
        }
    }

    /// Popover / HUD: let Tahoe chrome supply glass. Older macOS paints material.
    @ViewBuilder
    func lookOffPopoverBackdrop() -> some View {
        if #available(macOS 26.0, *) {
            background(.clear)
        } else {
            background(.ultraThinMaterial)
        }
    }
}

@available(macOS 26.0, *)
private struct LookOffLiquidGlassModifier<S: InsettableShape>: ViewModifier {
    var shape: S
    var interactive: Bool
    var clear: Bool

    func body(content: Content) -> some View {
        let base = clear ? Glass.clear : Glass.regular
        content.glassEffect(interactive ? base.interactive() : base, in: shape)
    }
}

/// System liquid-glass buttons on Tahoe. Manual `glassEffect` + opacity looks like a solid pill.
struct LookOffGlassButtonStyle: PrimitiveButtonStyle {
    var prominent: Bool = false
    var compact: Bool = false
    var circle: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            tahoe(configuration)
        } else {
            legacy(configuration)
        }
    }

    @available(macOS 26.0, *)
    @ViewBuilder
    private func tahoe(_ configuration: Configuration) -> some View {
        if prominent {
            Button(action: configuration.trigger) {
                chipLabel(configuration)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(circle ? .circle : .capsule)
            .controlSize(compact ? .small : .regular)
        } else {
            Button(action: configuration.trigger) {
                chipLabel(configuration)
            }
            .buttonStyle(.glass(.clear))
            .buttonBorderShape(circle ? .circle : .capsule)
            .controlSize(compact ? .small : .regular)
        }
    }

    private func legacy(_ configuration: Configuration) -> some View {
        Button(action: configuration.trigger) {
            chipLabel(configuration)
                .padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, compact ? 7 : 8)
                .background {
                    Capsule(style: .continuous).fill(.ultraThinMaterial)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .opacity(0.96)
    }

    private func chipLabel(_ configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold, design: .rounded))
    }
}

struct LookOffWindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct LookOffSidebarBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
