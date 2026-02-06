# Touchless - Project Context

## Project Overview
Touchless is a macOS menu bar app for voice-to-text input using AI. It converts speech to polished text and inserts it at the cursor position.

## Important Files
- **PLAN.md** - Full project plan, architecture, MVP features, and future roadmap. ALWAYS reference this for understanding project scope and decisions.

## Tech Stack
- Swift 5.9+ / SwiftUI
- macOS 13.0+ (Ventura)
- OpenAI APIs (Whisper for transcription, GPT for enhancement)
- HotKey library for global shortcuts

## Key Architecture
```
Keyboard Shortcut → Audio Recording → Whisper API → GPT Enhancement → Paste at Cursor
```

## Directory Structure
```
Touchless/
├── Sources/
│   ├── Models/Settings.swift       # UserDefaults-backed settings
│   ├── Services/
│   │   ├── AudioRecorder.swift     # AVFoundation recording
│   │   ├── WhisperService.swift    # OpenAI Whisper API
│   │   ├── EnhancementService.swift# OpenAI GPT text cleanup
│   │   ├── TextInserter.swift      # Clipboard + Cmd+V paste
│   │   └── HotkeyManager.swift     # Global hotkeys (HotKey lib)
│   └── Views/
│       ├── MenuBarView.swift       # Menu bar popup UI
│       └── SettingsView.swift      # Settings window
└── Package.swift                   # SPM dependencies
```

## Default Shortcuts
- **Option + Space**: Push-to-talk (hold to record)
- **Option + Shift + Space**: Toggle mode (press to start/stop)

## Required Permissions
1. Microphone access
2. Accessibility (for text insertion)

## Development
```bash
cd Touchless
swift build
swift run
```

## Configuration
- API key stored in UserDefaults
- Default Whisper model: whisper-1
- Default enhancement model: gpt-4o-mini
