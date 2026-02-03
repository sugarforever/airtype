# Touchless - Voice-to-Text Input for macOS

## Overview
Touchless is a macOS menu bar app that converts speech to polished text using AI. It captures audio via keyboard shortcuts, transcribes using OpenAI Whisper, enhances text with GPT, and inserts the result at the cursor position.

## MVP Features

### Core Functionality
- [x] Audio recording with microphone access
- [x] Push-to-talk mode (hold key to record, release to transcribe)
- [x] Toggle mode (press to start/stop recording)
- [x] OpenAI Whisper API integration for transcription
- [x] OpenAI GPT integration for text enhancement
- [x] Text insertion at cursor position (system-wide)
- [x] Menu bar app with status indicator

### Configuration
- [x] Configurable OpenAI API key
- [x] Configurable transcription model (default: whisper-1)
- [x] Configurable enhancement model (default: gpt-4o-mini)
- [x] Configurable keyboard shortcuts
- [x] Enable/disable text enhancement toggle

### Text Enhancement Features
- [x] Remove filler words (um, uh, like, you know)
- [x] Fix repetitions and self-corrections
- [x] Proper punctuation and capitalization
- [x] Clean, natural formatting

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Menu Bar App (SwiftUI)                   │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  Settings   │  │   Status    │  │  Keyboard Shortcut  │  │
│  │   Manager   │  │  Indicator  │  │      Handler        │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                      Core Services                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Audio     │  │  Whisper    │  │    LLM Enhancement  │  │
│  │  Recorder   │  │  Service    │  │       Service       │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                    System Integration                       │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Text Insertion (Accessibility API)         ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Technical Stack
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Audio**: AVFoundation
- **Shortcuts**: Carbon/HotKey library
- **Networking**: URLSession (async/await)
- **Storage**: UserDefaults for settings

## File Structure
```
Touchless/
├── TouchlessApp.swift          # App entry point
├── Models/
│   └── Settings.swift          # App settings model
├── Services/
│   ├── AudioRecorder.swift     # Microphone recording
│   ├── WhisperService.swift    # OpenAI Whisper API
│   ├── EnhancementService.swift# OpenAI GPT text enhancement
│   ├── TextInserter.swift      # Cursor text insertion
│   └── HotkeyManager.swift     # Global keyboard shortcuts
├── Views/
│   ├── MenuBarView.swift       # Menu bar popup
│   └── SettingsView.swift      # Settings window
└── Resources/
    └── Info.plist              # App permissions
```

## Long Recording UX Improvements (v1.1)

### Design Research Sources
- [Typeless](https://www.typeless.com/) - AI voice dictation with clean UI, wave animation recording indicator
- [Speakly AI](https://apps.apple.com/app/speakly-ai-voice-2-text-notes/id6744898967) - Long audio support, AI-powered formatting
- [Amazon Transcribe Streaming](https://docs.aws.amazon.com/transcribe/latest/dg/streaming-partial-results.html) - Partial results patterns
- [OpenAI Whisper Chunking](https://github.com/ufal/whisper_streaming) - Long audio chunking strategies

### Key UX Patterns Implemented

#### 1. Visual Feedback During Recording
- **Audio Level Meter**: Real-time visualization showing input volume (normalized 0-1 scale)
- **Peak Level Indicator**: Shows maximum recent audio level for visual feedback
- **Duration Display**: MM:SS format timer showing recording length
- **Long Recording Warning**: Notifies user when recording exceeds 5 minutes

#### 2. Chunked Transcription for Long Recordings
- **Problem**: OpenAI Whisper API has 25MB file limit, ~30s optimal chunk size
- **Solution**: Automatic audio splitting using AVFoundation
- **Chunk Duration**: 2 minutes per chunk (conservative for quality)
- **Progress Feedback**: Shows "Transcribing (2/5)" during multi-chunk processing

#### 3. Progressive Transcription Display
- **Accumulated Text Preview**: Shows partial transcription as chunks complete
- **Progress Bar**: Visual progress indicator with percentage
- **Stage Indicators**: Clear labels for each processing phase

#### 4. Error Handling & Edge Cases
| Scenario | Detection | User Message |
|----------|-----------|--------------|
| Empty recording | File size < 1KB | "Recording too short. Please speak for longer." |
| Network timeout | URLError.timedOut | "Network request timed out. Please try again." |
| Invalid API key | HTTP 401 / error message | "Invalid API key. Please check Settings." |
| Rate limit | HTTP 429 / error message | "Rate limit exceeded. Please wait a moment." |
| No internet | URLError.notConnectedToInternet | "No internet connection." |
| Server error | HTTP 5xx | "OpenAI server error. Please try again." |
| Microphone in use | Recording setup fails | "Microphone is in use by another app." |

### Architecture Changes

```
AudioRecorder.swift
├── Audio level monitoring (50ms interval)
├── Duration tracking (1s interval)
├── File size estimation
└── Level normalization (dB to 0-1)

WhisperService.swift
├── TranscriptionProgress struct
├── Automatic chunking decision (>24MB or >4min)
├── AVFoundation audio splitting
├── Progressive transcription accumulation
└── Enhanced error handling with recovery suggestions

MenuBarView.swift
├── AudioLevelMeter component (20-bar visualization)
├── Duration display in recording banner
├── Progress bar during processing
├── Partial transcription preview
└── Long recording warning
```

### Configuration Constants
```swift
maxFileSizeBytes = 24MB     // Buffer below 25MB API limit
targetChunkDuration = 120s  // 2 minutes per chunk
levelUpdateInterval = 50ms  // Smooth level animation
requestTimeout = 120s       // 2 minute API timeout
```

## Future Features (Not in MVP)

### Local Processing
- [ ] WhisperKit for on-device transcription (privacy)
- [ ] Local LLM option (Ollama/llama.cpp)

### Enhanced Text Processing
- [ ] Context-aware tone adaptation (email, chat, code)
- [ ] Custom vocabulary/terminology dictionary
- [ ] Multi-language support with auto-detection
- [ ] Translation mode

### UX Improvements
- [x] Audio waveform visualization during recording
- [ ] History of recent transcriptions
- [ ] Quick edit before insertion
- [ ] Sound effects for start/stop recording

### Integrations
- [ ] App-specific formatting rules
- [ ] Clipboard mode (copy instead of paste)
- [ ] Multiple output formats (markdown, plain text)

### System
- [ ] Launch at login
- [x] Menubar icon animation states
- [ ] Automatic updates
- [ ] Usage statistics (local only)

## Required Permissions
1. **Microphone Access** - For audio recording
2. **Accessibility** - For text insertion and global shortcuts

## Default Configuration
- Push-to-talk shortcut: `Option + Space`
- Toggle mode shortcut: `Option + Shift + Space`
- Transcription model: `whisper-1`
- Enhancement model: `gpt-4o-mini`
- Text enhancement: Enabled

## Development Notes
- Minimum macOS version: 13.0 (Ventura)
- Xcode 15+ required
- OpenAI API key required for operation
