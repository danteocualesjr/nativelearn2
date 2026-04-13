# Vibecademy - Agent Instructions

<!-- This is the single source of truth for all AI coding agents. CLAUDE.md is a symlink to this file. -->
<!-- AGENTS.md spec: https://github.com/agentsmd/agents.md — supported by Claude Code, Cursor, Copilot, Gemini CLI, and others. -->

## Overview

Vibecademy is a macOS AI tutor that helps users become AI-native. It places a companion cursor called **Sparkle** (an orange sparkle shape) next to the user's mouse pointer. Sparkle can see the user's screen, respond to voice commands, and walk them through how to use AI tools like Replit, Cursor, Claude Code, and Codex — step by step, conversationally.

The app has two main surfaces:
1. **Desktop window** — A full-size window with sidebar navigation, conversation history, and a Sparkle on/off toggle. This is what the user sees on launch.
2. **Cursor overlay** — A transparent full-screen overlay hosting Sparkle's sparkle icon, which follows the user's mouse and can fly to and point at UI elements.

Push-to-talk (Control+Option) captures voice, transcribes it, sends it with a screenshot to Claude, and Sparkle responds with voice (ElevenLabs TTS) while pointing at relevant screen elements.

All API keys live on a Cloudflare Worker proxy — nothing sensitive ships in the app binary.

### Forked From

Built on top of [Clicky](https://github.com/farzaa/clicky) by Farza. Major changes from the original:

- Rebranded from "Clicky" to "Vibecademy" with AI tutor persona "Sparkle"
- Changed companion icon from blue triangle to orange sparkle
- Changed from menu-bar-only app to full desktop app with main window (`LSUIElement=false`)
- Added persistent conversation storage (JSON files in Application Support)
- Added desktop window with sidebar navigation (Home, Chat, Spaces) and conversation history
- Added Sparkle on/off toggle — Sparkle is off by default, user activates from the desktop app
- Changed TTS voice to young British female (ElevenLabs "Charlotte" voice: `XB0fDUnXU5powFXDhCwa`)
- Removed Sparkle auto-update framework
- Removed onboarding video, replaced with text-based instructions
- Made menu bar panel draggable
- Updated system prompts for Sparkle's AI tutor persona

## Architecture

- **App Type**: Desktop app with main window + menu bar status item (`LSUIElement=false` in Info.plist)
- **Framework**: SwiftUI (macOS native) with AppKit bridging for menu bar panel and cursor overlay
- **Pattern**: MVVM with `@StateObject` / `@ObservedObject` / `@Published` state management
- **AI Chat**: Claude (Sonnet 4.6 default, Opus 4.6 optional) via Cloudflare Worker proxy with SSE streaming
- **Speech-to-Text**: AssemblyAI real-time streaming (`u3-rt-pro` model) via websocket, with OpenAI and Apple Speech as fallbacks
- **Text-to-Speech**: ElevenLabs (`eleven_flash_v2_5` model, female "Charlotte" voice) via Cloudflare Worker proxy
- **Screen Capture**: ScreenCaptureKit (macOS 14.2+), multi-monitor support
- **Voice Input**: Push-to-talk (Control+Option) via `AVAudioEngine` + pluggable transcription-provider layer. System-wide keyboard shortcut via listen-only CGEvent tap.
- **Companion Icon**: Orange sparkle (`sparkle` SF Symbol) — used in cursor overlay, menu bar, and transcript UI
- **Element Pointing**: Claude embeds `[POINT:x,y:label:screenN]` tags in responses. The overlay parses these, maps coordinates to the correct monitor, and animates the circle along a bezier arc to the target.
- **Conversation Persistence**: JSON files in `~/Library/Application Support/Vibecademy/`. Conversations are auto-saved during voice interactions and grouped by date in the UI.
- **Concurrency**: `@MainActor` isolation, async/await throughout
- **Analytics**: PostHog via `ClickyAnalytics.swift`

### API Proxy (Cloudflare Worker)

The app never calls external APIs directly. All requests go through a Cloudflare Worker (`worker/src/index.ts`) that holds the real API keys as secrets.

| Route | Upstream | Purpose |
|-------|----------|---------|
| `POST /chat` | `api.anthropic.com/v1/messages` | Claude vision + streaming chat |
| `POST /tts` | `api.elevenlabs.io/v1/text-to-speech/{voiceId}` | ElevenLabs TTS audio |
| `POST /transcribe-token` | `streaming.assemblyai.com/v3/token` | Fetches a short-lived (480s) AssemblyAI websocket token |

Worker secrets: `ANTHROPIC_API_KEY`, `ASSEMBLYAI_API_KEY`, `ELEVENLABS_API_KEY`
Worker vars: `ELEVENLABS_VOICE_ID` (set to `XB0fDUnXU5powFXDhCwa` — Charlotte female voice)

### Key Architecture Decisions

**Desktop Window + Menu Bar**: The app launches with a full `WindowGroup` containing `MainWindowView` (sidebar + detail). The menu bar status item with circle icon remains as a secondary access point. `LSUIElement` is `false` so the app starts as a regular Dock app — this ensures Xcode properly terminates the previous instance on re-run.

**Sparkle Toggle**: `CompanionManager.isSparkleCursorEnabled` controls whether the cursor overlay is visible. Defaults to `false` — the desktop app shows first, and the user activates Sparkle via a toggle in the sidebar or a hero card on the Home view. The preference is persisted to `UserDefaults`. Even when Sparkle is off, pressing Control+Option temporarily brings the overlay back for that interaction (transient cursor mode).

**Conversation Storage**: `ConversationStore` saves conversations as JSON to `~/Library/Application Support/Vibecademy/`. Each voice interaction (user transcript + Sparkle response) is appended to the active conversation. Conversations have titles (auto-generated from the first user message), summaries, and can be organized into Spaces (folders). The store is injected into both `MainWindowView` and `CompanionManager` from the app delegate.

**Menu Bar Panel Pattern**: The companion panel uses `NSStatusItem` for the menu bar icon and a custom borderless `NSPanel` for the floating control panel. The panel is non-activating so it doesn't steal focus. A global event monitor auto-dismisses it on outside clicks. The panel is draggable (`isMovableByWindowBackground = true`).

**Cursor Overlay**: A full-screen transparent `NSPanel` hosts the circle companion. It's non-activating, joins all Spaces, and never steals focus. The cursor position, response text, waveform, and pointing animations all render in this overlay via SwiftUI through `NSHostingView`.

**Global Push-To-Talk Shortcut**: Background push-to-talk uses a listen-only `CGEvent` tap instead of an AppKit global monitor so modifier-based shortcuts like `ctrl + option` are detected more reliably while the app is running in the background.

**Shared URLSession for AssemblyAI**: A single long-lived `URLSession` is shared across all AssemblyAI streaming sessions (owned by the provider, not the session). Creating and invalidating a URLSession per session corrupts the OS connection pool and causes "Socket is not connected" errors after a few rapid reconnections.

## Key Files

| File | Lines | Purpose |
|------|-------|---------|
| `leanring_buddyApp.swift` | ~70 | App entry point. `WindowGroup` displays `MainWindowView`. `CompanionAppDelegate` creates `CompanionManager`, `ConversationStore`, and `MenuBarPanelManager`, then starts the companion pipeline on launch. |
| `CompanionManager.swift` | ~992 | Central state machine. Owns dictation, shortcut monitoring, screen capture, Claude API, ElevenLabs TTS, overlay management, and Sparkle on/off toggle (`isSparkleCursorEnabled`). Coordinates the full push-to-talk → screenshot → Claude → TTS → pointing pipeline. Auto-saves voice exchanges to `ConversationStore`. |
| `MainWindowView.swift` | ~859 | Primary desktop window UI. Granola-style layout with sidebar (search, Home, Chat, Spaces) and detail pane (conversation list grouped by date, or conversation detail view). Sidebar footer has icon toolbar (Sparkle toggle, model picker, settings), status row, and brand row. Hero card at top of Home view adapts to Sparkle state (setup needed, Meet Sparkle activation, or push-to-talk instructions). |
| `ConversationStore.swift` | ~248 | Persistent conversation storage. Data models: `ConversationExchange`, `Conversation`, `Space`. Saves/loads JSON in `~/Library/Application Support/Vibecademy/`. Groups conversations by date. Supports Spaces (folders) for organizing conversations. |
| `MenuBarPanelManager.swift` | ~243 | NSStatusItem + custom NSPanel lifecycle. Creates the circle menu bar icon, manages the floating companion panel (show/hide/position), installs click-outside-to-dismiss monitor. Panel is draggable. |
| `CompanionPanelView.swift` | ~761 | SwiftUI panel content for the menu bar dropdown. Shows companion status, push-to-talk instructions, model picker (Sonnet/Opus), permissions UI, DM feedback button, and quit button. Dark aesthetic using `DS` design system. |
| `OverlayWindow.swift` | ~872 | Full-screen transparent overlay hosting the circle cursor, response text, waveform, and spinner. Handles cursor animation, element pointing with bezier arcs, multi-monitor coordinate mapping, and fade-out transitions. |
| `CompanionResponseOverlay.swift` | ~217 | SwiftUI view for the response text bubble and waveform displayed next to the cursor in the overlay. |
| `CompanionScreenCaptureUtility.swift` | ~132 | Multi-monitor screenshot capture using ScreenCaptureKit. Returns labeled image data for each connected display. |
| `BuddyDictationManager.swift` | ~866 | Push-to-talk voice pipeline. Handles microphone capture via `AVAudioEngine`, provider-aware permission checks, keyboard/button dictation sessions, transcript finalization, shortcut parsing, contextual keyterms, and live audio-level reporting for waveform feedback. |
| `BuddyTranscriptionProvider.swift` | ~100 | Protocol surface and provider factory for voice transcription backends. Resolves provider based on `VoiceTranscriptionProvider` in Info.plist — AssemblyAI, OpenAI, or Apple Speech. |
| `AssemblyAIStreamingTranscriptionProvider.swift` | ~479 | Streaming transcription provider. Fetches temp tokens from the Cloudflare Worker, opens an AssemblyAI v3 websocket, streams PCM16 audio, tracks turn-based transcripts, and delivers finalized text on key-up. Shares a single URLSession across all sessions. |
| `OpenAIAudioTranscriptionProvider.swift` | ~317 | Upload-based transcription provider. Buffers push-to-talk audio locally, uploads as WAV on release, returns finalized transcript. |
| `AppleSpeechTranscriptionProvider.swift` | ~147 | Local fallback transcription provider backed by Apple's Speech framework. |
| `BuddyAudioConversionSupport.swift` | ~108 | Audio conversion helpers. Converts live mic buffers to PCM16 mono audio and builds WAV payloads for upload-based providers. |
| `GlobalPushToTalkShortcutMonitor.swift` | ~132 | System-wide push-to-talk monitor. Owns the listen-only `CGEvent` tap and publishes press/release transitions. |
| `ClaudeAPI.swift` | ~291 | Claude vision API client with streaming (SSE) and non-streaming modes. TLS warmup optimization, image MIME detection, conversation history support. |
| `OpenAIAPI.swift` | ~142 | OpenAI GPT vision API client. |
| `ElevenLabsTTSClient.swift` | ~81 | ElevenLabs TTS client. Sends text to the Worker proxy, plays back audio via `AVAudioPlayer`. Exposes `isPlaying` for transient cursor scheduling. |
| `ElementLocationDetector.swift` | ~335 | Detects UI element locations in screenshots for cursor pointing. |
| `DesignSystem.swift` | ~879 | Design system tokens — colors, corner radii, shared styles. All UI references `DS.Colors`, `DS.CornerRadius`, etc. `overlayCursorBlue` is actually orange (`#FF8C33`), used for the sparkle icon. |
| `ClickyAnalytics.swift` | ~122 | PostHog analytics integration (`VibecademyAnalytics`) for usage tracking. |
| `WindowPositionManager.swift` | ~262 | Window placement logic, Screen Recording permission flow, and accessibility permission helpers. |
| `AppBundleConfiguration.swift` | ~28 | Runtime configuration reader for keys stored in the app bundle Info.plist. |
| `worker/src/index.ts` | ~142 | Cloudflare Worker proxy. Three routes: `/chat` (Claude), `/tts` (ElevenLabs), `/transcribe-token` (AssemblyAI temp token). |

## Build & Run

```bash
# Open in Xcode
open leanring-buddy.xcodeproj

# Select the leanring-buddy scheme, set signing team, Cmd+R to build and run

# Known non-blocking warnings: Swift 6 concurrency warnings,
# deprecated onChange warning in OverlayWindow.swift. Do NOT attempt to fix these.
```

**Do NOT run `xcodebuild` from the terminal** — it invalidates TCC (Transparency, Consent, and Control) permissions and the app will need to re-request screen recording, accessibility, etc.

## Cloudflare Worker

The deployed worker URL is `https://nativelearn-proxy.danteocualesjr.workers.dev`.

```bash
cd worker
npm install

# Add secrets
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY

# Deploy
npx wrangler deploy

# Local dev (create worker/.dev.vars with your keys)
npx wrangler dev
```

## Code Style & Conventions

### Variable and Method Naming

IMPORTANT: Follow these naming rules strictly. Clarity is the top priority.

- Be as clear and specific with variable and method names as possible
- **Optimize for clarity over concision.** A developer with zero context on the codebase should immediately understand what a variable or method does just from reading its name
- Use longer names when it improves clarity. Do NOT use single-character variable names
- Example: use `originalQuestionLastAnsweredDate` instead of `originalAnswered`
- When passing props or arguments to functions, keep the same names as the original variable. Do not shorten or abbreviate parameter names. If you have `currentCardData`, pass it as `currentCardData`, not `card` or `cardData`

### Code Clarity

- **Clear is better than clever.** Do not write functionality in fewer lines if it makes the code harder to understand
- Write more lines of code if additional lines improve readability and comprehension
- Make things so clear that someone with zero context would completely understand the variable names, method names, what things do, and why they exist
- When a variable or method name alone cannot fully explain something, add a comment explaining what is happening and why

### Swift/SwiftUI Conventions

- Use SwiftUI for all UI unless a feature is only supported in AppKit (e.g., `NSPanel` for floating windows)
- All UI state updates must be on `@MainActor`
- Use async/await for all asynchronous operations
- Comments should explain "why" not just "what", especially for non-obvious AppKit bridging
- AppKit `NSPanel`/`NSWindow` bridged into SwiftUI via `NSHostingView`
- All buttons must show a pointer cursor on hover
- For any interactive element, explicitly think through its hover behavior (cursor, visual feedback, and whether hover should communicate clickability)

### Do NOT

- Do not add features, refactor code, or make "improvements" beyond what was asked
- Do not add docstrings, comments, or type annotations to code you did not change
- Do not try to fix the known non-blocking warnings (Swift 6 concurrency, deprecated onChange)
- Do not rename the project directory or scheme (the "leanring" typo is intentional/legacy)
- Do not run `xcodebuild` from the terminal — it invalidates TCC permissions

## Git Workflow

- Branch naming: `feature/description` or `fix/description`
- Commit messages: imperative mood, concise, explain the "why" not the "what"
- Do not force-push to main

## Self-Update Instructions

<!-- AI agents: follow these instructions to keep this file accurate. -->

When you make changes to this project that affect the information in this file, update this file to reflect those changes. Specifically:

1. **New files**: Add new source files to the "Key Files" table with their purpose and approximate line count
2. **Deleted files**: Remove entries for files that no longer exist
3. **Architecture changes**: Update the architecture section if you introduce new patterns, frameworks, or significant structural changes
4. **Build changes**: Update build commands if the build process changes
5. **New conventions**: If the user establishes a new coding convention during a session, add it to the appropriate conventions section
6. **Line count drift**: If a file's line count changes significantly (>50 lines), update the approximate count in the Key Files table

Do NOT update this file for minor edits, bug fixes, or changes that don't affect the documented architecture or conventions.
