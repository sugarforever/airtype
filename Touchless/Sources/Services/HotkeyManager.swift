import Carbon.HIToolbox
import Cocoa
import HotKey

/// Manages global keyboard shortcuts for recording
@MainActor
class HotkeyManager: ObservableObject {
    @Published var isPushToTalkPressed = false
    @Published var isToggleActive = false

    private var pushToTalkHotKey: HotKey?
    private var toggleModeHotKey: HotKey?

    var onPushToTalkStart: (() -> Void)?
    var onPushToTalkEnd: (() -> Void)?
    var onToggle: (() -> Void)?

    init() {
        setupHotkeys()
    }

    func setupHotkeys() {
        // Push-to-talk: Option + Space
        pushToTalkHotKey = HotKey(key: .space, modifiers: [.option])
        pushToTalkHotKey?.keyDownHandler = { [weak self] in
            Task { @MainActor in
                self?.isPushToTalkPressed = true
                self?.onPushToTalkStart?()
            }
        }
        pushToTalkHotKey?.keyUpHandler = { [weak self] in
            Task { @MainActor in
                self?.isPushToTalkPressed = false
                self?.onPushToTalkEnd?()
            }
        }

        // Toggle mode: Option + Shift + Space
        toggleModeHotKey = HotKey(key: .space, modifiers: [.option, .shift])
        toggleModeHotKey?.keyDownHandler = { [weak self] in
            Task { @MainActor in
                self?.isToggleActive.toggle()
                self?.onToggle?()
            }
        }
    }

    func disable() {
        pushToTalkHotKey?.isPaused = true
        toggleModeHotKey?.isPaused = true
    }

    func enable() {
        pushToTalkHotKey?.isPaused = false
        toggleModeHotKey?.isPaused = false
    }
}
