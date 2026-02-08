import Carbon.HIToolbox
import Cocoa
import HotKey

/// Manages global keyboard shortcuts for recording
@MainActor
class HotkeyManager: ObservableObject {
    @Published var isPushToTalkPressed = false
    @Published var isToggleActive = false

    @Published var pushToTalkDisplay: String = ""
    @Published var toggleModeDisplay: String = ""

    private var pushToTalkHotKey: HotKey?
    private var toggleModeHotKey: HotKey?

    var onPushToTalkStart: (() -> Void)?
    var onPushToTalkEnd: (() -> Void)?
    var onToggle: (() -> Void)?

    init() {
        setupHotkeys()
    }

    func setupHotkeys() {
        let settings = Settings.shared

        // Push-to-talk
        pushToTalkHotKey = HotKey(
            carbonKeyCode: settings.pushToTalkKeyCode,
            carbonModifiers: settings.pushToTalkModifiers
        )
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

        // Toggle mode
        toggleModeHotKey = HotKey(
            carbonKeyCode: settings.toggleModeKeyCode,
            carbonModifiers: settings.toggleModeModifiers
        )
        toggleModeHotKey?.keyDownHandler = { [weak self] in
            Task { @MainActor in
                self?.isToggleActive.toggle()
                self?.onToggle?()
            }
        }

        updateDisplayStrings()
    }

    func rebindHotkeys() {
        pushToTalkHotKey = nil
        toggleModeHotKey = nil
        setupHotkeys()
    }

    func disable() {
        pushToTalkHotKey?.isPaused = true
        toggleModeHotKey?.isPaused = true
    }

    func enable() {
        pushToTalkHotKey?.isPaused = false
        toggleModeHotKey?.isPaused = false
    }

    private func updateDisplayStrings() {
        let settings = Settings.shared
        pushToTalkDisplay = Settings.shortcutDisplayString(
            keyCode: settings.pushToTalkKeyCode,
            modifiers: settings.pushToTalkModifiers
        )
        toggleModeDisplay = Settings.shortcutDisplayString(
            keyCode: settings.toggleModeKeyCode,
            modifiers: settings.toggleModeModifiers
        )
    }
}
