import SwiftUI
import AppKit

/// Glass-style surface for the floating panel.
/// - macOS 13+: NSVisualEffectView fallback
/// - macOS 26+: NSGlassEffectView (Liquid Glass)
struct FloatingGlassBackgroundView: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.cornerRadius = cornerRadius
            glassView.wantsLayer = true
            return glassView
        }

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.isEmphasized = false
        visualEffect.appearance = NSAppearance(named: .darkAqua)
        return visualEffect
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *), let glassView = nsView as? NSGlassEffectView {
            glassView.cornerRadius = cornerRadius
            return
        }

        guard let visualEffect = nsView as? NSVisualEffectView else { return }
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.isEmphasized = false
        visualEffect.appearance = NSAppearance(named: .darkAqua)
    }
}
