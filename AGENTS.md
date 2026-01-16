# VoiceInk - Agent Context Guide

This document provides comprehensive information about the VoiceInk project for AI agents, LLMs, and developers who need to understand the codebase quickly.

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture & Design Patterns](#architecture--design-patterns)
3. [Core Components](#core-components)
4. [Key Services](#key-services)
5. [Data Flow](#data-flow)
6. [Directory Structure](#directory-structure)
7. [External Dependencies](#external-dependencies)
8. [Build System](#build-system)
9. [Configuration & Settings](#configuration--settings)
10. [Development Guidelines](#development-guidelines)

---

## Project Overview

**VoiceInk** is a native macOS application that transcribes voice to text almost instantly, with privacy-first, offline-capable processing.

### Key Facts
- **Platform:** macOS 14.0+
- **Language:** Swift + SwiftUI
- **License:** GPL v3.0 (Open Source)
- **Repository:** https://github.com/Beingpax/VoiceInk
- **Website:** https://tryvoiceink.com
- **Total Files:** 164 Swift files

### Core Value Propositions
1. **Privacy-First:** 100% offline processing with local AI models
2. **Multi-Model Support:** Local (Whisper.cpp), Cloud (OpenAI, Anthropic, etc.), Native (Apple), and Parakeet models
3. **Context-Aware:** Smart AI that understands screen content and adapts to context
4. **PowerMode:** Automatic app/URL-specific settings
5. **Personal Dictionary:** Custom word replacements and vocabulary training
6. **Global Shortcuts:** Configurable hotkeys for recording

---

## Architecture & Design Patterns

### 1. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        User Interface                        │
│  (SwiftUI Views: Recorder, Settings, Dictionary, History)   │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│                      WhisperState                            │
│         (Central State Manager - @MainActor)                 │
│  • Recording state machine                                   │
│  • Model lifecycle management                                │
│  • UI coordination                                           │
└──┬────────────┬─────────────┬──────────────┬────────────────┘
   │            │             │              │
   ▼            ▼             ▼              ▼
┌──────┐  ┌──────────┐  ┌─────────┐  ┌──────────────┐
│Audio │  │Transcribe│  │AI Enhance│ │System Services│
│System│  │Services  │  │Service   │  │(Hotkey, Menu)│
└──────┘  └──────────┘  └─────────┘  └──────────────┘
   │            │             │              │
   └────────────┴─────────────┴──────────────┘
                      │
         ┌────────────▼────────────┐
         │   SwiftData Persistence  │
         │  (Transcription History) │
         └─────────────────────────┘
```

### 2. Design Patterns Used

#### **Protocol-Oriented Design**
- `TranscriptionModel` protocol abstracts different model types
- `CloudTranscriptionService` protocol defines transcription interface
- Enables easy addition of new providers without modifying existing code

#### **State Management Pattern**
- `WhisperState` as single source of truth
- SwiftUI's `@Published` + `@StateObject` for reactivity
- Finite state machine for recording lifecycle:
  ```swift
  enum RecordingState {
    case idle
    case recording
    case transcribing
    case enhancing
    case busy
  }
  ```

#### **Service Layer Pattern**
- Clear separation: Audio → Transcription → Enhancement → Output
- Dependency injection via app initialization
- Lazy loading for expensive services (Whisper models)

#### **Actor Pattern**
- `WhisperContext` as actor for thread-safe Whisper.cpp access
- `@MainActor` for UI state updates
- Prevents race conditions in C++ interop

#### **Observer Pattern**
- `NotificationCenter` for cross-component communication
- Custom notifications: `.AppSettingsDidChange`, `.navigateToDestination`
- Decouples components and enables reactive updates

#### **Factory Pattern**
- Model creation based on user selection
- SwiftData container strategies (persistent → in-memory → fallback)

---

## Core Components

### 1. WhisperState (`/Whisper/WhisperState.swift`)

**Purpose:** Central coordinator for the entire application

**Key Responsibilities:**
- Manages recording state machine (idle → recording → transcribing → enhancing)
- Loads and unloads transcription models
- Coordinates between audio, transcription, and enhancement services
- Controls UI visibility (mini recorder, notch recorder)

**Critical Properties:**
```swift
@Published var recordingState: RecordingState
@Published var transcribedText: String
@Published var enhancedText: String?
@Published var selectedTranscriptionModel: TranscriptionModel
@Published var isAIEnhancementEnabled: Bool
```

**Key Methods:**
- `toggleRecord()` - Main recording trigger
- `startRecording()` / `stopRecording()` - Audio lifecycle
- `transcribeAudio(_:)` - Routes to appropriate transcription service
- `enhanceText(_:)` - AI enhancement pipeline

### 2. AudioEngineRecorder (`/Whisper/AudioEngineRecorder.swift`)

**Purpose:** Low-level audio recording using AVAudioEngine

**Key Features:**
- 16-bit PCM format at 16000Hz (Whisper requirement)
- Real-time audio level monitoring for UI
- Thread-safe file writing
- Automatic device switching on error

**Critical Methods:**
```swift
func startRecording(to url: URL) throws
func stopRecording() -> URL?
func getCurrentAudioLevel() -> Float
```

### 3. Transcription Services

**Architecture:** Protocol-based with multiple implementations

#### **LocalTranscriptionService** (`/Services/LocalTranscriptionService.swift`)
- Integrates whisper.cpp via `LibWhisper.swift`
- Loads `.coremlmodel` files from app bundle
- Manages WhisperContext actor for thread safety
- Supports multiple model sizes (base, small, medium, large)

#### **Cloud Services** (`/Services/CloudTranscription/`)
Each service implements a common pattern:
1. Format audio for API (base64 encoding, multipart upload)
2. Send HTTP request with API key
3. Parse JSON response
4. Return transcribed text

Supported providers:
- OpenAI Whisper API
- Groq
- Deepgram
- Google Gemini
- ElevenLabs
- Soniox
- Mistral
- Custom OpenAI-compatible endpoints

#### **NativeAppleTranscriptionService** (`/Services/NativeAppleTranscriptionService.swift`)
- Uses Apple's `SFSpeechRecognizer`
- Zero-cost option for basic transcription
- Supports language binding and offline recognition

#### **ParakeetTranscriptionService** (`/Services/ParakeetTranscriptionService.swift`)
- FluidAudio framework integration
- Lightweight alternative to Whisper
- Fast inference with lower resource usage

### 4. AIEnhancementService (`/Services/AIEnhancement/AIEnhancementService.swift`)

**Purpose:** Post-process transcriptions with AI models

**Workflow:**
```
Raw Transcript
    ↓
Gather Context:
  ├─ Clipboard content (if enabled)
  ├─ Screenshot (if enabled)
  ├─ Active app name
  └─ Custom vocabulary
    ↓
Format Messages:
  ├─ System: Custom prompt template
  └─ User: Text + context
    ↓
Route to AI Provider
    ↓
Enhanced Text
```

**Key Features:**
- Multi-provider support (OpenAI, Anthropic, Groq, Gemini, etc.)
- Rate limiting (1 request/second)
- Configurable timeouts (default 30s)
- Extended reasoning support for o1/o3 models
- Automatic retry on failure

**Configuration:**
```swift
@AppStorage("selectedAIProvider") var selectedProvider: String
@AppStorage("selectedAIModel") var selectedModel: String
@AppStorage("useClipboardContext") var useClipboard: Bool
@AppStorage("useScreenCaptureContext") var useScreenCapture: Bool
```

### 5. PowerMode System (`/PowerMode/`)

**Purpose:** Automatic context-aware settings based on active app/URL

**Components:**

#### **PowerModeSessionManager**
- Monitors active window changes
- Matches against saved configurations
- Applies settings automatically (model, language, prompt)

#### **ActiveWindowService**
- Uses Accessibility APIs to detect foreground app
- Extracts app name and window title

#### **BrowserURLService**
- AppleScript-based URL extraction for Safari, Chrome, Arc
- Handles URL pattern matching (wildcards)

#### **PowerModeConfig**
- Codable struct for per-app/URL settings
- Stored as JSON array in UserDefaults
- Fields: app bundle ID, URL pattern, model, language, prompt

**Data Flow:**
```
User switches to Safari (on github.com)
    ↓
ActiveWindowService detects change
    ↓
BrowserURLService extracts URL
    ↓
PowerModeSessionManager finds matching config
    ↓
WhisperState updates selectedModel, selectedLanguage, etc.
    ↓
Next recording uses these settings
```

### 6. Dictionary System (`/Views/Dictionary/`, `/Services/`)

**Purpose:** Personal vocabulary and text replacements

**Components:**

#### **WordReplacementService**
- In-memory dictionary of old → new text mappings
- Applied during transcription output
- Case-sensitive matching

#### **CustomVocabularyService**
- Tracks frequently used custom terms
- Adds context to AI enhancement requests

#### **DictionaryImportExportService**
- JSON import/export for backups
- Sharable vocabulary lists

**Data Model:**
```swift
struct WordReplacement: Codable, Identifiable {
    var id: UUID
    var oldWord: String
    var newWord: String
    var createdDate: Date
}
```

### 7. Hotkey System (`/HotkeyManager.swift`)

**Purpose:** Global keyboard shortcuts for recording

**Features:**
- Multiple hotkey support (Fn, Option, Control, Command keys)
- Push-to-talk mode (hold to record, release to stop)
- Middle-click toggle with configurable delay
- Language binding: Temporary language override per hotkey
- Works system-wide (requires Accessibility permissions)

**Implementation:**
```swift
// Monitor global events
NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
    // Detect modifier key press/release
    self.handleModifierKey(event)
}
```

**Language Binding:**
- Hotkey1 → Language A (e.g., English)
- Hotkey2 → Language B (e.g., Spanish)
- Override persists only during recording session

---

## Key Services

### Audio Services

#### **AudioDeviceManager** (`/Services/AudioDeviceManager.swift`)
- Enumerates audio input devices
- Tracks device changes (plug/unplug)
- Automatic fallback to system default on device removal

#### **AudioDeviceConfiguration** (`/Services/AudioDeviceConfiguration.swift`)
- User preferences for device selection
- Persisted in UserDefaults

#### **MediaController** (`/MediaController.swift`)
- Pauses media playback during recording
- Uses MediaRemoteAdapter framework
- Resumes playback after recording stops

### Transcription Services

#### **TranscriptionService** (`/Services/TranscriptionService.swift`)
- Abstract protocol for all transcription providers
- Defines common interface: `transcribe(audioURL:) async throws -> String`

#### **AudioFileTranscriptionService** (`/Services/AudioFileTranscriptionService.swift`)
- Manages file upload transcription workflow
- Progress tracking for long files
- Cleanup temporary files

### Persistence Services

#### **TranscriptionAutoCleanupService** (`/Services/TranscriptionAutoCleanupService.swift`)
- Automatic deletion of old transcriptions
- Configurable retention period (7/30/60/90 days, or never)
- Runs on app launch and background

#### **LastTranscriptionService** (`/Services/LastTranscriptionService.swift`)
- Quick access to most recent transcription
- Used for "Copy Last" and "Redo" features

### System Services

#### **SystemInfoService** (`/Services/SystemInfoService.swift`)
- Collects system information for support requests
- macOS version, hardware specs, app version

#### **AnnouncementsService** (`/Services/AnnouncementsService.swift`)
- Fetches in-app announcements from remote JSON
- Displays update notifications and news

#### **ScreenCaptureService** (referenced in enhancement flow)
- Takes screenshots for AI context
- Base64 encodes images for API requests
- Requires Screen Recording permission

#### **ClipboardManager** (`/ClipboardManager.swift`)
- Reads clipboard content for AI context
- Formats plain text and rich text

---

## Data Flow

### 1. Recording → Transcription → Output Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. USER TRIGGER                                                 │
│    - Press hotkey (Fn, Option, etc.)                            │
│    - Click "Record" in UI                                       │
│    - Siri Shortcut                                              │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. HOTKEY MANAGER                                               │
│    - Detects global event                                       │
│    - Calls WhisperState.toggleRecord()                          │
│    - Sets temporary language if configured                      │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. WHISPER STATE (Recording Start)                             │
│    - Check recording state (idle/busy)                          │
│    - Load transcription model if needed                         │
│    - Show recorder UI (mini or notch)                           │
│    - Call Recorder.startRecording()                             │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. AUDIO ENGINE RECORDER                                        │
│    - Configure AVAudioEngine (16kHz mono PCM)                   │
│    - Start audio capture                                        │
│    - Write to temporary file                                    │
│    - Update real-time audio levels                             │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼ (User stops recording)
┌─────────────────────────────────────────────────────────────────┐
│ 5. RECORDING STOP                                               │
│    - Stop audio engine                                          │
│    - Finalize audio file                                        │
│    - Return file URL                                            │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. TRANSCRIPTION ROUTING (WhisperState)                        │
│    - Check selected model type                                  │
│    - Route to appropriate service:                              │
│      • Local → LocalTranscriptionService                        │
│      • Cloud → CloudTranscriptionService                        │
│      • Native → NativeAppleTranscriptionService                 │
│      • Parakeet → ParakeetTranscriptionService                  │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 7. TRANSCRIPTION EXECUTION                                      │
│    [Example: LocalTranscriptionService]                         │
│    - Load Whisper model (if not cached)                         │
│    - Read audio file → PCM buffer                               │
│    - Call whisper.cpp: whisper_full()                           │
│    - Extract segments → concatenate text                        │
│    - Return raw transcript                                      │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 8. AI ENHANCEMENT (Optional)                                    │
│    If isAIEnhancementEnabled:                                   │
│    - Gather context:                                            │
│      • Clipboard (if enabled)                                   │
│      • Screenshot (if enabled)                                  │
│      • Active app name                                          │
│      • Custom vocabulary                                        │
│    - Format messages:                                           │
│      • System: Custom prompt                                    │
│      • User: Transcript + context                               │
│    - Call AI provider API (OpenAI/Anthropic/etc.)               │
│    - Return enhanced text                                       │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 9. TEXT PROCESSING                                              │
│    - Apply word replacements (Dictionary)                       │
│    - Format text (trim, spacing)                                │
│    - Store in WhisperState.transcribedText/enhancedText         │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 10. OUTPUT                                                      │
│     - CursorPaster: Paste to active application                 │
│     - Save Transcription to SwiftData                           │
│     - Update UI (history, notification)                         │
│     - Cleanup audio file (if auto-delete enabled)               │
└─────────────────────────────────────────────────────────────────┘
```

### 2. Settings Update Flow

```
User changes setting in UI
    ↓
SwiftUI View updates @AppStorage or @Published property
    ↓
Property observer triggers willSet/didSet
    ↓
Save to UserDefaults (or Keychain for API keys)
    ↓
Post NotificationCenter notification (.AppSettingsDidChange)
    ↓
Services observe notification and react:
  - HotkeyManager reregisters hotkeys
  - WhisperState reloads model
  - AIEnhancementService updates provider
    ↓
UI automatically updates via @Published bindings
```

### 3. PowerMode Activation Flow

```
User switches to application (e.g., Notion)
    ↓
ActiveWindowService detects via Accessibility API
    ↓
Extracts bundle ID: "notion.id"
    ↓
PowerModeSessionManager.checkForPowerMode()
    ↓
Match against saved configs in UserDefaults
    ↓
Found match: "Notion" config
    ↓
Apply settings:
  - WhisperState.selectedTranscriptionModel = config.model
  - WhisperState.selectedLanguage = config.language
  - WhisperState.selectedPrompt = config.prompt
    ↓
Show PowerMode indicator in UI
    ↓
Next recording uses Notion-specific settings
```

---

## Directory Structure

```
VoiceInk/
├── VoiceInk/                           # Main source directory
│   ├── VoiceInk.swift                  # App entry point (@main)
│   ├── AppDelegate.swift               # App lifecycle, menu bar setup
│   │
│   ├── Models/                         # Data models (8 files)
│   │   ├── Transcription.swift         # SwiftData model for history
│   │   ├── TranscriptionModel.swift    # Protocol for transcription models
│   │   ├── PredefinedModels.swift      # Default model configurations
│   │   ├── PredefinedPrompts.swift     # Default AI prompts
│   │   ├── CustomPrompt.swift          # User-created prompts
│   │   ├── AIPrompts.swift             # Prompt templates
│   │   ├── PromptTemplates.swift       # System prompt definitions
│   │   └── LicenseViewModel.swift      # License validation
│   │
│   ├── Services/                       # Business logic (32 files)
│   │   ├── TranscriptionService.swift  # Base transcription protocol
│   │   ├── LocalTranscriptionService.swift
│   │   ├── NativeAppleTranscriptionService.swift
│   │   ├── ParakeetTranscriptionService.swift
│   │   │
│   │   ├── CloudTranscription/         # Cloud providers
│   │   │   ├── CloudTranscriptionService.swift
│   │   │   ├── OpenAICompatibleTranscriptionService.swift
│   │   │   ├── GroqTranscriptionService.swift
│   │   │   ├── DeepgramTranscriptionService.swift
│   │   │   ├── GeminiTranscriptionService.swift
│   │   │   ├── ElevenLabsTranscriptionService.swift
│   │   │   ├── SonioxTranscriptionService.swift
│   │   │   ├── MistralTranscriptionService.swift
│   │   │   └── CustomModelManager.swift
│   │   │
│   │   ├── AIEnhancement/              # AI post-processing
│   │   │   ├── AIEnhancementService.swift
│   │   │   └── AIEnhancementOutputFilter.swift
│   │   │
│   │   ├── OllamaService.swift         # Local LLM inference
│   │   ├── PolarService.swift          # API service
│   │   │
│   │   ├── AudioDeviceManager.swift    # Device enumeration
│   │   ├── AudioDeviceConfiguration.swift
│   │   ├── AudioFileProcessor.swift    # File format handling
│   │   ├── AudioFileTranscriptionManager.swift
│   │   ├── AudioFileTranscriptionService.swift
│   │   │
│   │   ├── WordReplacementService.swift
│   │   ├── CustomVocabularyService.swift
│   │   ├── DictionaryImportExportService.swift
│   │   │
│   │   ├── PromptDetectionService.swift
│   │   ├── SelectedTextService.swift   # Get selected text (SelectedTextKit)
│   │   ├── ScreenCaptureService.swift  # Screenshots for context
│   │   ├── LastTranscriptionService.swift
│   │   ├── TranscriptionAutoCleanupService.swift
│   │   ├── TranscriptionOutputFilter.swift
│   │   ├── VoiceInkCSVExportService.swift
│   │   ├── SystemInfoService.swift
│   │   ├── AnnouncementsService.swift
│   │   ├── Obfuscator.swift            # String obfuscation
│   │   ├── SupportedMedia.swift        # Media file type detection
│   │   └── EnhancementShortcutSettings.swift
│   │
│   ├── Whisper/                        # Whisper.cpp integration (12 files)
│   │   ├── WhisperState.swift          # Central state manager
│   │   ├── LibWhisper.swift            # C++ bridge
│   │   ├── WhisperContext.swift        # Actor wrapper
│   │   ├── Recorder.swift              # High-level recording
│   │   ├── AudioEngineRecorder.swift   # AVAudioEngine implementation
│   │   ├── WhisperPrompt.swift         # Prompt management
│   │   ├── CursorPaster.swift          # Text pasting via CGEvent
│   │   ├── AIService.swift             # Multi-provider AI
│   │   ├── ReasoningConfig.swift       # Extended reasoning
│   │   └── ...
│   │
│   ├── PowerMode/                      # Context-aware settings (12 files)
│   │   ├── PowerModeSessionManager.swift
│   │   ├── PowerModeConfig.swift       # Configuration model
│   │   ├── PowerModeValidator.swift
│   │   ├── ActiveWindowService.swift   # App detection
│   │   ├── BrowserURLService.swift     # URL extraction
│   │   ├── EmojiManager.swift          # Icon management
│   │   └── PowerModeView.swift         # UI
│   │
│   ├── Views/                          # SwiftUI views (67 files)
│   │   ├── ContentView.swift           # Main container
│   │   │
│   │   ├── Recorder/                   # Recording UI
│   │   │   ├── MiniRecorderView.swift
│   │   │   ├── NotchRecorderView.swift
│   │   │   └── EnhancingView.swift
│   │   │
│   │   ├── Settings/                   # Settings panels
│   │   │   ├── SettingsView.swift
│   │   │   ├── GeneralSettingsView.swift
│   │   │   ├── AudioSettingsView.swift
│   │   │   ├── EnhancementSettingsView.swift
│   │   │   ├── PromptCreationSheet.swift
│   │   │   └── ...
│   │   │
│   │   ├── Dictionary/                 # Word replacement UI
│   │   │   ├── DictionaryView.swift
│   │   │   ├── WordReplacementView.swift
│   │   │   ├── DictionarySettingsView.swift
│   │   │   └── EditReplacementSheet.swift
│   │   │
│   │   ├── AI Models/                  # Model management
│   │   │   ├── ModelManagementView.swift
│   │   │   ├── LocalModelCardRowView.swift
│   │   │   ├── CloudModelCardRowView.swift
│   │   │   ├── NativeModelCardRowView.swift
│   │   │   ├── ParakeetModelCardRowView.swift
│   │   │   ├── CustomModelCardRowView.swift
│   │   │   ├── AddCustomModelView.swift
│   │   │   ├── APIKeyManagementView.swift
│   │   │   └── LanguageSelectionView.swift
│   │   │
│   │   ├── Onboarding/                 # First-run experience
│   │   │   ├── OnboardingView.swift
│   │   │   ├── PermissionsView.swift
│   │   │   └── ModelDownloadView.swift
│   │   │
│   │   ├── Metrics/                    # Dashboard/analytics
│   │   │   ├── MetricsDashboardView.swift
│   │   │   ├── ChartsView.swift
│   │   │   └── StatsCardsView.swift
│   │   │
│   │   ├── Common/                     # Reusable components
│   │   │   ├── AnimatedCopyButton.swift
│   │   │   ├── AnimatedSaveButton.swift
│   │   │   ├── AppIconView.swift
│   │   │   └── CardBackground.swift
│   │   │
│   │   ├── Components/                 # UI building blocks
│   │   │   ├── InfoTip.swift
│   │   │   ├── ProBadge.swift
│   │   │   ├── PromptSelectionGrid.swift
│   │   │   └── TrialMessageView.swift
│   │   │
│   │   ├── LicenseView.swift
│   │   ├── LicenseManagementView.swift
│   │   ├── KeyboardShortcutView.swift
│   │   ├── AudioTranscribeView.swift
│   │   ├── AudioPlayerView.swift
│   │   └── ...
│   │
│   ├── Notifications/                  # Alerts & announcements (3 files)
│   │   ├── AppNotifications.swift
│   │   ├── AnnouncementManager.swift
│   │   └── AnnouncementView.swift
│   │
│   ├── AppIntents/                     # Siri Shortcuts (3 files)
│   │   ├── AppShortcuts.swift
│   │   ├── ToggleMiniRecorderIntent.swift
│   │   └── DismissMiniRecorderIntent.swift
│   │
│   ├── Utils/                          # Utilities
│   │   └── TextFormatter.swift
│   │
│   ├── HotkeyManager.swift             # Global shortcuts
│   ├── MenuBarManager.swift            # Menu bar icon
│   ├── WindowManager.swift             # Window management
│   ├── MediaController.swift           # Media playback control
│   ├── PlaybackController.swift
│   ├── ClipboardManager.swift
│   ├── SoundManager.swift              # UI sounds
│   ├── CustomSoundManager.swift
│   ├── EmailSupport.swift              # Support email
│   ├── MiniRecorderShortcutManager.swift
│   │
│   ├── Resources/                      # Assets
│   │   ├── Assets.xcassets/            # Images, icons
│   │   ├── Sounds/                     # Audio files
│   │   └── Localizable.xcstrings       # Localization
│   │
│   └── Info.plist                      # App configuration
│
├── VoiceInkTests/                      # Unit tests
├── VoiceInkUITests/                    # UI tests
│
├── VoiceInk.xcodeproj/                 # Xcode project
│   └── project.pbxproj
│
├── Makefile                            # Build automation
├── README.md                           # Project overview
├── BUILDING.md                         # Build instructions
├── CONTRIBUTING.md                     # Contribution guidelines
├── CODE_OF_CONDUCT.md                  # Community standards
├── LICENSE                             # GPL v3.0
└── AGENTS.md                           # This file
```

---

## External Dependencies

### Core Frameworks (Linked)

1. **whisper.xcframework** (Required)
   - Source: https://github.com/ggerganov/whisper.cpp
   - Purpose: Local speech-to-text via OpenAI Whisper models
   - Location: `~/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework`
   - Build: `./build-xcframework.sh` in whisper.cpp repo
   - Critical: Must be properly linked in Xcode project settings

2. **FluidAudio** (Swift Package)
   - Source: https://github.com/FluidInference/FluidAudio
   - Purpose: Parakeet model runtime
   - Lightweight alternative to Whisper

### System Frameworks (Apple)

- **AVFoundation** - Audio recording, playback
- **SwiftUI** - UI framework
- **SwiftData** - Data persistence
- **Accessibility** - Window/app detection
- **CoreGraphics** - Text pasting via CGEvent
- **Speech** - Native Apple transcription (SFSpeechRecognizer)
- **ScreenCaptureKit** - Screenshots (macOS 12.3+)
- **UniformTypeIdentifiers** - File type detection

### Swift Package Dependencies

3. **Sparkle** - Automatic updates
   - Source: https://github.com/sparkle-project/Sparkle
   - Purpose: In-app updates for distributed builds

4. **KeyboardShortcuts** - Hotkey management
   - Source: https://github.com/sindresorhus/KeyboardShortcuts
   - Purpose: User-configurable global shortcuts

5. **LaunchAtLogin** - Startup behavior
   - Source: https://github.com/sindresorhus/LaunchAtLogin
   - Purpose: Launch at login toggle

6. **MediaRemoteAdapter** - Media control
   - Source: https://github.com/ejbills/mediaremote-adapter
   - Purpose: Pause/resume media during recording

7. **Zip** - Archive utilities
   - Source: https://github.com/marmelroy/Zip
   - Purpose: File compression for model downloads

8. **SelectedTextKit** - Selected text retrieval
   - Source: https://github.com/tisfeng/SelectedTextKit
   - Purpose: Get highlighted text from any app

9. **Swift Atomics** - Thread-safe operations
   - Source: https://github.com/apple/swift-atomics
   - Purpose: Lock-free concurrent data structures

### Cloud API Integrations

**AI Enhancement Providers:**
- OpenAI (GPT-4o, GPT-4, GPT-3.5, o1)
- Anthropic (Claude 3.5 Sonnet, Claude 3 Opus/Sonnet/Haiku)
- Groq (Llama 3, Mixtral)
- Google Gemini (Gemini Pro, Gemini Flash)
- Mistral AI
- Custom OpenAI-compatible endpoints

**Transcription Providers:**
- OpenAI Whisper API
- Groq Whisper
- Deepgram
- ElevenLabs
- Soniox
- Assembly AI
- Mistral

**Local Inference:**
- Ollama (HTTP API for local LLMs)

### System Permissions Required

Declared in `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>VoiceInk needs microphone access to record your voice for transcription.</string>

<key>NSScreenCaptureUsageDescription</key>
<string>VoiceInk uses screen capture to provide context-aware AI enhancements.</string>

<key>NSAppleEventsUsageDescription</key>
<string>VoiceInk needs permission to detect your active browser tab for PowerMode.</string>
```

### Entitlements (`VoiceInk.entitlements`)

```xml
<key>com.apple.security.automation.apple-events</key>
<true/>  <!-- AppleScript for browser URL detection -->

<key>com.apple.security.device.audio-input</key>
<true/>  <!-- Microphone access -->

<key>com.apple.security.screen-capture</key>
<true/>  <!-- Screenshots for AI context -->

<key>com.apple.security.network.client</key>
<true/>  <!-- API calls to cloud services -->

<key>com.apple.security.files.user-selected.read-only</key>
<true/>  <!-- File picker for audio file transcription -->

<key>com.apple.security.app-sandbox</key>
<false/>  <!-- Sandbox disabled for full system access -->
```

---

## Build System

### Quick Start with Makefile

```bash
# Clone repository
git clone https://github.com/Beingpax/VoiceInk.git
cd VoiceInk

# Build everything (recommended)
make all

# Or for development (build + run)
make dev
```

### Makefile Commands

| Command | Description |
|---------|-------------|
| `make check` | Verify tools installed (git, xcodebuild, swift) |
| `make whisper` | Clone and build whisper.cpp XCFramework |
| `make setup` | Prepare whisper framework for linking |
| `make build` | Build VoiceInk Xcode project |
| `make run` | Launch built app |
| `make dev` | Build and run (ideal for development) |
| `make all` | Complete build (default target) |
| `make clean` | Remove build artifacts and dependencies |
| `make help` | Show all commands |

### Build Process Details

#### 1. Dependency Management

Dependencies stored in: `~/VoiceInk-Dependencies/`

```bash
~/VoiceInk-Dependencies/
└── whisper.cpp/                    # Whisper.cpp repo
    └── build-apple/
        └── whisper.xcframework/    # Built framework
```

#### 2. Whisper.cpp Build

Automated by `make whisper`:

```bash
# Clone whisper.cpp
git clone https://github.com/ggerganov/whisper.cpp.git ~/VoiceInk-Dependencies/whisper.cpp

# Build XCFramework
cd ~/VoiceInk-Dependencies/whisper.cpp
./build-xcframework.sh

# Result: whisper.xcframework at build-apple/whisper.xcframework
```

#### 3. Xcode Project Build

```bash
# Build command
xcodebuild \
  -project VoiceInk.xcodeproj \
  -scheme VoiceInk \
  -configuration Debug \
  build

# Output: Build/Products/Debug/VoiceInk.app
```

### Manual Build (Alternative)

If you prefer manual control:

```bash
# 1. Build whisper.cpp
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
./build-xcframework.sh

# 2. Clone VoiceInk
git clone https://github.com/Beingpax/VoiceInk.git
cd VoiceInk

# 3. Add whisper.xcframework to project
# Drag and drop in Xcode, or add in "Frameworks, Libraries, and Embedded Content"

# 4. Build in Xcode
# Cmd+B or Product > Build
```

### Troubleshooting Build Issues

**Problem:** "Framework not found whisper"
**Solution:**
```bash
# Ensure framework is built
make whisper

# Verify framework exists
ls ~/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework

# Re-link in Xcode
# Project Settings → General → Frameworks, Libraries, and Embedded Content
```

**Problem:** "Command line tools not found"
**Solution:**
```bash
xcode-select --install
```

**Problem:** "Build failed with code signing error"
**Solution:**
- Open Xcode → Signing & Capabilities
- Change Team to your Apple ID
- Or disable signing for local development

---

## Configuration & Settings

### Storage Locations

#### UserDefaults (`com.prakashjoshipax.VoiceInk`)

Key settings stored in UserDefaults:

| Key | Type | Purpose |
|-----|------|---------|
| `recorderType` | String | "mini" or "notch" |
| `selectedLanguage` | String | Language code or "auto" |
| `temporaryLanguageOverride` | String | Hotkey-bound language |
| `selectedTranscriptionModel` | Data | Encoded TranscriptionModel |
| `selectedAIProvider` | String | "openai", "anthropic", etc. |
| `selectedAIModel` | String | Model identifier |
| `isAIEnhancementEnabled` | Bool | Enhancement toggle |
| `useClipboardContext` | Bool | Include clipboard in AI context |
| `useScreenCaptureContext` | Bool | Include screenshot in AI context |
| `powerModeConfigs` | Data | JSON array of PowerModeConfig |
| `customPrompts` | Data | JSON array of CustomPrompt |
| `wordReplacements` | Data | JSON array of WordReplacement |
| `autoDeleteRecordings` | Bool | Cleanup audio files |
| `transcriptionRetentionDays` | Int | 7/30/60/90/0 (never) |
| `selectedHotkey` | String | "fn", "option", "control", etc. |
| `middleClickEnabled` | Bool | Middle-click toggle |
| `middleClickDelay` | Double | Delay in seconds |
| `languageBindings` | Data | JSON {hotkey1: "en", hotkey2: "es"} |

#### Keychain (Secure Storage)

API keys stored in macOS Keychain:
- `service: "com.prakashjoshipax.VoiceInk"`
- `account: "<provider>-api-key"` (e.g., "openai-api-key")

Accessed via:
```swift
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.prakashjoshipax.VoiceInk",
    kSecAttrAccount as String: "\(provider)-api-key",
    kSecReturnData as String: true
]
SecItemCopyMatching(query as CFDictionary, &result)
```

#### SwiftData Database

Location: `~/Library/Application Support/com.prakashjoshipax.VoiceInk/default.store`

**Schema:**
```swift
@Model final class Transcription {
    @Attribute(.unique) var id: UUID
    var text: String
    var enhancedText: String?
    var timestamp: Date
    var duration: TimeInterval
    var audioFileURL: String?
    var transcriptionModelName: String?
    var aiEnhancementModelName: String?
    var promptName: String?
    var aiRequestSystemMessage: String?
    var aiRequestUserMessage: String?
    var powerModeName: String?
    var transcriptionStatus: String  // "pending", "completed", "failed"
}
```

**Container Initialization:**
```swift
// Priority: Persistent → In-Memory → Minimal → Dummy
let container = try ModelContainer(
    for: Transcription.self,
    configurations: ModelConfiguration(isStoredInMemoryOnly: false)
)
```

#### Audio Files

Temporary recordings: `/tmp/VoiceInk_<UUID>.wav`

**Format:** 16-bit PCM, 16000 Hz, mono

**Cleanup:**
- Automatic: After transcription (if `autoDeleteRecordings` enabled)
- Manual: Via AudioCleanupManager
- Retention: Controlled by `transcriptionRetentionDays`

### Configuration Files

#### Info.plist

Key configurations:

```xml
<key>CFBundleIdentifier</key>
<string>com.prakashjoshipax.VoiceInk</string>

<key>LSMinimumSystemVersion</key>
<string>14.0</string>

<key>LSUIElement</key>
<true/>  <!-- Run as menu bar app (no dock icon) -->

<key>NSSupportsAutomaticTermination</key>
<true/>

<key>NSSupportsAutomaticGraphicsSwitching</key>
<true/>
```

#### VoiceInk.entitlements

Already covered in [External Dependencies](#external-dependencies) section.

### Default Configuration

On first launch, VoiceInk initializes with:

- **Recorder Type:** Mini Recorder
- **Language:** Auto-detect
- **Transcription Model:** Whisper Base (English)
- **AI Enhancement:** Disabled
- **Hotkey:** Fn key
- **PowerMode:** Disabled
- **Audio Cleanup:** Enabled
- **Retention:** 30 days

---

## Development Guidelines

### Code Style

#### Swift Conventions
- Use Swift standard naming (camelCase for properties/functions, PascalCase for types)
- Prefer `let` over `var` when possible
- Use explicit types for public APIs, type inference for internal logic
- Organize code with `// MARK: - Section Name`

#### SwiftUI Best Practices
- Use `@State` for local view state
- Use `@StateObject` for owned ObservableObject instances
- Use `@ObservedObject` for passed ObservableObject instances
- Use `@EnvironmentObject` for shared app-wide state
- Extract complex views into separate structs

#### Async/Await
- Use `async/await` for asynchronous operations
- Use `Task` for concurrent work
- Use `@MainActor` for UI updates
- Avoid `DispatchQueue` except for legacy code

### Architecture Patterns to Follow

#### 1. Service Layer Pattern
When adding new functionality:
```swift
// Create a dedicated service class
class MyNewService {
    // Singleton or dependency-injected
    static let shared = MyNewService()

    // Clear interface
    func performAction() async throws -> Result {
        // Implementation
    }
}
```

#### 2. Protocol-Oriented Design
For extensibility:
```swift
protocol TranscriptionProvider {
    func transcribe(_ audioURL: URL) async throws -> String
}

// Implement for each provider
class GroqTranscriptionService: TranscriptionProvider {
    func transcribe(_ audioURL: URL) async throws -> String {
        // Groq-specific implementation
    }
}
```

#### 3. State Management
Centralize related state:
```swift
@MainActor
class FeatureState: ObservableObject {
    @Published var isLoading = false
    @Published var error: Error?
    @Published var data: [Item] = []

    func loadData() async {
        isLoading = true
        defer { isLoading = false }
        // Load data
    }
}
```

### Adding New Features

#### A. New Transcription Provider

1. Create service file: `/Services/CloudTranscription/MyProviderTranscriptionService.swift`
2. Implement `CloudTranscriptionService` protocol
3. Add provider enum case in `TranscriptionModel.swift`
4. Update UI in `ModelManagementView.swift`
5. Add API key management in `APIKeyManagementView.swift`
6. Test with sample audio

Example:
```swift
class MyProviderTranscriptionService: CloudTranscriptionService {
    func transcribe(_ audioURL: URL) async throws -> String {
        // 1. Read audio file
        let audioData = try Data(contentsOf: audioURL)

        // 2. Format request (multipart, JSON, etc.)
        var request = URLRequest(url: URL(string: "https://api.myprovider.com/v1/transcribe")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // 3. Send request
        let (data, response) = try await URLSession.shared.data(for: request)

        // 4. Parse response
        let result = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return result.text
    }
}
```

#### B. New AI Enhancement Provider

1. Add enum case in `AIService.swift` → `AIProvider`
2. Implement provider-specific logic in `enhanceText()`
3. Add API key field in `APIKeyManagementView.swift`
4. Update `selectedAIProvider` handling in `EnhancementSettingsView.swift`

#### C. New PowerMode Feature

1. Update `PowerModeConfig` model with new property
2. Add UI field in `PowerModeConfigView.swift`
3. Update `PowerModeSessionManager.applyConfig()` to use new setting
4. Test with app switching

### Testing

#### Unit Tests
Located in `VoiceInkTests/`:
```swift
@testable import VoiceInk
import XCTest

final class TranscriptionServiceTests: XCTestCase {
    func testLocalTranscription() async throws {
        let service = LocalTranscriptionService()
        let audioURL = Bundle.main.url(forResource: "test", withExtension: "wav")!
        let result = try await service.transcribe(audioURL)
        XCTAssertFalse(result.isEmpty)
    }
}
```

#### UI Tests
Located in `VoiceInkUITests/`:
```swift
final class VoiceInkUITests: XCTestCase {
    func testRecordingFlow() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Record"].tap()
        sleep(3)
        app.buttons["Stop"].tap()

        XCTAssertTrue(app.staticTexts["Transcription"].exists)
    }
}
```

### Debugging Tips

#### Common Issues

**Problem:** Whisper.cpp crash or "context not loaded"
**Debug:**
```swift
// Check if model is loaded
guard let context = WhisperContext.shared.context else {
    print("❌ Whisper context not initialized")
    return
}

// Check model file exists
let modelURL = Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin")
print("Model path: \(modelURL?.path ?? "not found")")
```

**Problem:** Audio not recording
**Debug:**
```swift
// Check audio permissions
let status = AVCaptureDevice.authorizationStatus(for: .audio)
print("Audio permission: \(status.rawValue)")  // 3 = authorized

// Check audio engine state
print("Engine running: \(audioEngine.isRunning)")
print("Input node: \(audioEngine.inputNode)")
```

**Problem:** AI enhancement not working
**Debug:**
```swift
// Check API key
let apiKey = KeychainHelper.retrieve(for: "openai-api-key")
print("API key present: \(apiKey != nil)")

// Check network request
do {
    let result = try await AIService.shared.enhanceText(...)
    print("✅ Enhancement succeeded")
} catch {
    print("❌ Enhancement failed: \(error)")
}
```

#### Logging

Use structured logging:
```swift
import os.log

let logger = Logger(subsystem: "com.prakashjoshipax.VoiceInk", category: "Transcription")

logger.info("Starting transcription with model: \(modelName)")
logger.error("Failed to transcribe: \(error.localizedDescription)")
logger.debug("Audio buffer size: \(buffer.count) bytes")
```

### Performance Optimization

#### Whisper.cpp
- Use smaller models for real-time (base, small)
- Use larger models for accuracy (medium, large)
- Enable CoreML for 2-3x speedup (already enabled in build)

#### SwiftUI
- Use `.task()` for view lifecycle async work
- Use `.onChange()` sparingly (can cause re-renders)
- Extract large view bodies into subviews
- Use `@StateObject` instead of `@ObservedObject` when creating objects

#### Memory Management
- Clean up audio files promptly
- Unload Whisper models when not in use (already implemented)
- Use weak references for delegates
- Avoid retain cycles with `[weak self]` in closures

### Contributing Workflow

1. **Fork the repository** on GitHub
2. **Clone your fork:**
   ```bash
   git clone https://github.com/YOUR_USERNAME/VoiceInk.git
   ```
3. **Create a feature branch:**
   ```bash
   git checkout -b feature/my-new-feature
   ```
4. **Make changes** and commit:
   ```bash
   git commit -m "Add: New transcription provider for XYZ"
   ```
5. **Push to your fork:**
   ```bash
   git push origin feature/my-new-feature
   ```
6. **Open a Pull Request** on the main repository
7. **Discuss** with maintainers and iterate

**Important:** Read [CONTRIBUTING.md](CONTRIBUTING.md) before starting work.

### Documentation Standards

When adding new code:

1. **Public APIs:** Add doc comments
   ```swift
   /// Transcribes audio from the given file URL.
   /// - Parameter audioURL: Local file URL of audio file
   /// - Returns: Transcribed text
   /// - Throws: TranscriptionError if transcription fails
   func transcribe(_ audioURL: URL) async throws -> String
   ```

2. **Complex Logic:** Add inline comments
   ```swift
   // Whisper.cpp requires 16-bit PCM at 16kHz mono
   // Convert from recording format (48kHz stereo) to required format
   let converter = AVAudioConverter(from: inputFormat, to: whisperFormat)
   ```

3. **Update This File:** If adding major features, update AGENTS.md

---

## Quick Reference

### Key Files for Common Tasks

| Task | Primary Files |
|------|---------------|
| **Add transcription provider** | `Services/CloudTranscription/<Provider>Service.swift`, `Models/TranscriptionModel.swift` |
| **Modify recording logic** | `Whisper/Recorder.swift`, `Whisper/AudioEngineRecorder.swift` |
| **Change UI layout** | `Views/ContentView.swift`, relevant view files |
| **Add AI enhancement** | `Services/AIEnhancement/AIEnhancementService.swift`, `Whisper/AIService.swift` |
| **Modify hotkeys** | `HotkeyManager.swift` |
| **Update PowerMode** | `PowerMode/PowerModeSessionManager.swift`, `PowerMode/PowerModeConfig.swift` |
| **Add settings** | `Views/Settings/`, use `@AppStorage` |
| **Modify data model** | `Models/Transcription.swift` (SwiftData) |
| **Add notifications** | `Notifications/AppNotifications.swift` |

### Common Commands

```bash
# Build and run
make dev

# Clean build
make clean && make all

# Run tests
xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk

# Check for updates in dependencies
# (Currently manual - check GitHub releases)

# Format code (if using SwiftFormat)
swiftformat VoiceInk/

# Lint code (if using SwiftLint)
swiftlint lint
```

### Environment Variables

For development, you can override settings:

```bash
# Use different UserDefaults suite for testing
defaults write com.prakashjoshipax.VoiceInk.debug selectedLanguage "es"

# Reset all settings
defaults delete com.prakashjoshipax.VoiceInk

# Check current settings
defaults read com.prakashjoshipax.VoiceInk
```

---

## Additional Resources

- **Repository:** https://github.com/Beingpax/VoiceInk
- **Website:** https://tryvoiceink.com
- **YouTube:** https://www.youtube.com/@tryvoiceink
- **Issues:** https://github.com/Beingpax/VoiceInk/issues
- **Whisper.cpp:** https://github.com/ggerganov/whisper.cpp
- **FluidAudio:** https://github.com/FluidInference/FluidAudio

---

## License

VoiceInk is licensed under the GNU General Public License v3.0.

This means:
- ✅ You can use, modify, and distribute the code
- ✅ You can use it for commercial purposes
- ❌ You must disclose source code of modifications
- ❌ You must license derivatives under GPL v3.0
- ❌ You cannot sublicense or hold the author liable

See [LICENSE](LICENSE) file for full details.

---

**Document Version:** 1.0
**Last Updated:** 2026-01-13
**Maintainer:** VoiceInk Contributors

---

*This document is intended for AI agents, LLMs, and developers who need to quickly understand the VoiceInk codebase. For user-facing documentation, see README.md and BUILDING.md.*
