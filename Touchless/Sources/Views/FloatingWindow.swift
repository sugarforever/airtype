import SwiftUI
import AppKit

/// A floating panel that stays on top of all windows
/// Styled like Raycast/Spotlight with dark minimal appearance
class FloatingPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        // Panel behavior
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true

        // Fully transparent appearance - critical for removing gray border
        isOpaque = false
        backgroundColor = NSColor.clear
        hasShadow = true

        // Hide any title bar elements
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        // Don't show in dock or app switcher
        hidesOnDeactivate = false

        // Allow clicking through to other apps
        becomesKeyOnlyIfNeeded = true
    }

    /// Position the panel in a corner of the screen
    func position(at corner: FloatingWindowPosition) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let padding: CGFloat = 20

        var origin: NSPoint

        switch corner {
        case .topRight:
            origin = NSPoint(
                x: screenFrame.maxX - frame.width - padding,
                y: screenFrame.maxY - frame.height - padding
            )
        case .bottomRight:
            origin = NSPoint(
                x: screenFrame.maxX - frame.width - padding,
                y: screenFrame.minY + padding
            )
        case .topLeft:
            origin = NSPoint(
                x: screenFrame.minX + padding,
                y: screenFrame.maxY - frame.height - padding
            )
        case .bottomLeft:
            origin = NSPoint(
                x: screenFrame.minX + padding,
                y: screenFrame.minY + padding
            )
        }

        setFrameOrigin(origin)
    }

    /// Animate size change for expand/collapse
    func animateResize(to newSize: NSSize, position: FloatingWindowPosition) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let padding: CGFloat = 20

        var newOrigin: NSPoint

        // Calculate new origin based on position to keep corner anchored
        switch position {
        case .topRight:
            newOrigin = NSPoint(
                x: screenFrame.maxX - newSize.width - padding,
                y: screenFrame.maxY - newSize.height - padding
            )
        case .bottomRight:
            newOrigin = NSPoint(
                x: screenFrame.maxX - newSize.width - padding,
                y: screenFrame.minY + padding
            )
        case .topLeft:
            newOrigin = NSPoint(
                x: screenFrame.minX + padding,
                y: screenFrame.maxY - newSize.height - padding
            )
        case .bottomLeft:
            newOrigin = NSPoint(
                x: screenFrame.minX + padding,
                y: screenFrame.minY + padding
            )
        }

        let newFrame = NSRect(origin: newOrigin, size: newSize)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(newFrame, display: true)
        }
    }

    // Allow the panel to become key for text selection, but not main
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Controller to manage the floating window lifecycle
@MainActor
class FloatingWindowController: ObservableObject {
    private var panel: FloatingPanel?
    @Published var isVisible = false

    private let settings: Settings

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    /// Show the floating window with the given content
    func show<Content: View>(content: Content) {
        if panel == nil {
            createPanel(with: content)
        }

        panel?.orderFront(nil)
        panel?.position(at: settings.floatingWindowPosition)
        isVisible = true
    }

    /// Hide the floating window
    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    /// Toggle visibility
    func toggle<Content: View>(content: Content) {
        if isVisible {
            hide()
        } else {
            show(content: content)
        }
    }

    /// Update the window size (for expand/collapse)
    func resize(to size: NSSize) {
        panel?.animateResize(to: size, position: settings.floatingWindowPosition)
    }

    /// Reposition the window (when settings change)
    func reposition() {
        panel?.position(at: settings.floatingWindowPosition)
    }

    private func createPanel<Content: View>(with content: Content) {
        // Initial size for pill mode
        let initialSize = NSSize(width: 280, height: 60)
        let contentRect = NSRect(origin: .zero, size: initialSize)

        panel = FloatingPanel(contentRect: contentRect)

        let hostingView = NSHostingView(rootView: content.ignoresSafeArea())
        hostingView.frame = contentRect

        // Make hosting view background fully transparent (fixes gray border)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.layer?.isOpaque = false

        panel?.contentView = hostingView
        panel?.backgroundColor = NSColor.clear
    }

    /// Update the content view
    func updateContent<Content: View>(_ content: Content) {
        guard let panel = panel else { return }

        let hostingView = NSHostingView(rootView: content.ignoresSafeArea())
        hostingView.frame = panel.frame

        // Make hosting view background fully transparent
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.layer?.isOpaque = false

        panel.contentView = hostingView
        panel.backgroundColor = NSColor.clear
    }
}
