import SwiftUI
import AppKit
import Combine

/// Observable object that tracks system appearance (light/dark mode)
class GlassAppearanceObserver: ObservableObject {
    @Published var isDarkBackground: Bool = false

    init() {
        updateAppearance()

        // Observe system appearance changes
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    @objc private func appearanceChanged() {
        DispatchQueue.main.async {
            self.updateAppearance()
        }
    }

    private func updateAppearance() {
        let appearance = NSApp.effectiveAppearance
        isDarkBackground = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    func observe(_ view: NSView) {
        // Just update once when view is available
        updateAppearance()
    }

    deinit {
        DistributedNotificationCenter.default.removeObserver(self)
    }
}

/// Glass-style surface for the floating panel.
/// - macOS 13+: NSVisualEffectView fallback
/// - macOS 26+: NSGlassEffectView (Liquid Glass)
struct FloatingGlassBackgroundView: NSViewRepresentable {
    var cornerRadius: CGFloat
    var appearanceObserver: GlassAppearanceObserver?

    func makeNSView(context: Context) -> NSView {
        #if compiler(>=6.1)
        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.cornerRadius = cornerRadius
            glassView.wantsLayer = true
            appearanceObserver?.observe(glassView)
            return glassView
        }
        #endif

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.isEmphasized = false
        appearanceObserver?.observe(visualEffect)
        return visualEffect
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        #if compiler(>=6.1)
        if #available(macOS 26.0, *), let glassView = nsView as? NSGlassEffectView {
            glassView.cornerRadius = cornerRadius
            return
        }
        #endif

        guard let visualEffect = nsView as? NSVisualEffectView else { return }
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.isEmphasized = false
    }
}
