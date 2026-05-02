# Sparkle - Agent Instructions

<!-- This is the single source of truth for all AI coding agents. CLAUDE.md is a symlink to this file. -->
<!-- AGENTS.md spec: https://github.com/agentsmd/agents.md — supported by Claude Code, Cursor, Copilot, Gemini CLI, and others. -->

## Overview

Sparkle is a macOS AI tutor that helps users become AI-native. It places a companion cursor (an orange sparkle shape) next to the user's mouse pointer. Sparkle can see the user's screen, respond to voice commands, and walk them through how to use AI tools like Replit, Cursor, Claude Code, and Codex — step by step, conversationally.

The app has two main surfaces:
1. **Desktop window** — A full-size window with sidebar navigation, conversation history, and a Sparkle on/off toggle. This is what the user sees on launch.
2. **Cursor overlay** — A transparent full-screen overlay hosting Sparkle's sparkle icon, which follows the user's mouse and can fly to and point at UI elements.

Push-to-talk (Control+Option) captures voice, transcribes it, sends it with a screenshot to Claude, and Sparkle responds with voice (ElevenLabs TTS) while pointing at relevant screen elements.

All API keys live on a Cloudflare Worker proxy — nothing sensitive ships in the app binary.

### Product Notes

Key product decisions that shape the current implementation:

- Brand is "Sparkle" with AI tutor persona "Sparkle"
- Companion icon is an orange sparkle (not a geometric shape)
- Full desktop app with main window (`LSUIElement=false`), plus a menu bar status item as a secondary surface
- Persistent conversation storage (JSON files in Application Support)
- Desktop window with sidebar navigation (Home, Chat, Spaces) and conversation history
- Sparkle on/off toggle — Sparkle is off by default, user activates from the desktop app
- TTS voice is a young British female (ElevenLabs "Charlotte" voice: `XB0fDUnXU5powFXDhCwa`)
- No auto-update framework
- No onboarding video — text-based instructions only
- Menu bar panel is draggable
- System prompts are tuned for Sparkle's AI tutor persona

## Architecture

- **App Type**: Desktop app with main window + menu bar status item (`LSUIElement=false` in Info.plist)
- **Framework**: SwiftUI (macOS native) with AppKit bridging for menu bar panel and cursor overlay
- **Pattern**: MVVM with `@StateObject` / `@ObservedObject` / `@Published` state management
- **AI Chat**: Claude (Sonnet 4.6 default, Opus 4.6 optional) via Cloudflare Worker proxy with SSE streaming. The streaming request advertises Anthropic's hosted `web_search_20250305` server tool (capped at 3 searches per turn) so Sparkle can answer questions about current events. The system prompt gates when she actually searches — only for time-sensitive or post-training-cutoff questions. The Worker strips the web-search tool from non-current prompts and enforces a KV-backed daily limit for web-search-enabled requests.
- **Speech-to-Text**: AssemblyAI real-time streaming (`u3-rt-pro` model) via websocket, with OpenAI and Apple Speech as fallbacks
- **Text-to-Speech**: ElevenLabs (`eleven_flash_v2_5` model, female "Charlotte" voice) via Cloudflare Worker proxy
- **Screen Capture**: ScreenCaptureKit (macOS 14.2+), multi-monitor support
- **Voice Input**: Push-to-talk (Control+Option) via `AVAudioEngine` + pluggable transcription-provider layer. System-wide keyboard shortcut via listen-only CGEvent tap.
- **Companion Icon**: Orange sparkle (`sparkle` SF Symbol) — used in cursor overlay, menu bar, and transcript UI
- **Element Pointing**: Claude embeds one or more inline `[POINT:x,y:label:screenN]` tags in responses. For multi-point responses, all TTS audio segments are pre-fetched in parallel, then played sequentially — Sparkle flies to each tagged location via bezier arc before speaking the surrounding text. Single-point responses (one trailing tag) follow the original path. `CompanionManager.isMultiPointSequenceActive` tells the overlay to skip its auto-return-to-cursor between points.
- **Conversation Persistence**: JSON files in `~/Library/Application Support/Vibecademy/`. Conversations are auto-saved during voice interactions and grouped by date in the UI.
- **Concurrency**: `@MainActor` isolation, async/await throughout
- **Analytics**: PostHog via `VibecademyAnalytics.swift`

### API Proxy (Cloudflare Worker)

The app never calls external APIs directly. All requests go through a Cloudflare Worker (`worker/src/index.ts`) that holds the real API keys as secrets.

| Route | Upstream | Purpose |
|-------|----------|---------|
| `POST /chat` | `api.anthropic.com/v1/messages` | Claude vision + streaming chat |
| `POST /tts` | `api.elevenlabs.io/v1/text-to-speech/{voiceId}` | ElevenLabs TTS audio |
| `POST /transcribe-token` | `streaming.assemblyai.com/v3/token` | Fetches a short-lived (480s) AssemblyAI websocket token |

**Authentication**: every request must carry a Sparkle bearer token in the `Authorization: Bearer <token>` header. Tokens are generated locally by the desktop app on first launch (`SparkleClientCredentials.swift`) and persisted in the macOS Keychain. The Worker validates the token format (`sparkle_v1_<64 hex chars>`) and rejects malformed/missing tokens with HTTP 401. Tokens are NOT proof of identity — they're a TOFU credential that filters out anonymous probes and gives the Worker a stable per-install handle for rate limiting. Real attestation would require Apple App Attest, which is out of scope.

**Per-install daily rate limits**: each endpoint counts a per-token, per-day, per-endpoint counter in KV (`<endpoint>:<utc-date>:<sha256(token)>`). When the cap is exceeded the Worker returns HTTP 429 with `retry-after` set to seconds-until-tomorrow-UTC. Defaults: `chat` 200/day, `tts` 1000/day, `transcribe` 200/day, `web-search` 20/day (a sub-cap on chat calls that actually use Anthropic's hosted web_search tool). All limits are configurable via env vars.

**Friendly proxy error UX**: every Worker call (`/chat`, `/tts`, `/transcribe-token`) wraps non-2xx responses in `SparkleProxyError` (a `LocalizedError`). `CompanionManager` branches on `isRateLimited` and `isCredentialsRejected` to render a tailored overlay message and choose a sensible spoken fallback — on a chat 429 it skips the misleading "trouble connecting" credits-error utterance, on a TTS 429 it speaks the actual response text via macOS system TTS so the user still hears the answer, and on a 401 it tells the user to restart the app. Every 429 also fires `VibecademyAnalytics.trackProxyRateLimited(endpoint:retryAfterSeconds:)` so we can see in PostHog when real users hit the caps.

Worker secrets: `ANTHROPIC_API_KEY`, `ASSEMBLYAI_API_KEY`, `ELEVENLABS_API_KEY`
Worker vars: `ELEVENLABS_VOICE_ID` (set to `XB0fDUnXU5powFXDhCwa` — Charlotte female voice), `CHAT_DAILY_LIMIT`, `TTS_DAILY_LIMIT`, `TRANSCRIBE_DAILY_LIMIT`, `WEB_SEARCH_DAILY_LIMIT` (each defaults are described above)
Worker KV bindings: `RATE_LIMIT_KV` stores hashed per-token, per-endpoint daily counters. (Renamed from `WEB_SEARCH_RATE_LIMIT_KV` — the same KV namespace ID is reused so existing counters carry over; only the binding name in code changed.)

### Key Architecture Decisions

**Desktop Window + Menu Bar**: The app launches with a full `WindowGroup` containing `MainWindowView` (sidebar + detail). The menu bar status item with circle icon remains as a secondary access point. `LSUIElement` is `false` so the app starts as a regular Dock app — this ensures Xcode properly terminates the previous instance on re-run.

**Sparkle Toggle**: `CompanionManager.isSparkleCursorEnabled` controls whether the cursor overlay is visible. Defaults to `false` — the desktop app shows first, and the user activates Sparkle via a toggle in the sidebar or a hero card on the Home view. The preference is persisted to `UserDefaults`. Even when Sparkle is off, pressing Control+Option temporarily brings the overlay back for that interaction (transient cursor mode).

**Conversation Storage**: `ConversationStore` saves conversations as JSON to `~/Library/Application Support/Vibecademy/`. Each voice interaction (user transcript + Sparkle response) is appended to the active conversation. Conversations have titles, summaries, and can be organized into Spaces (folders). Titles and summaries are auto-generated by a background Claude Haiku 4.5 call after the 1st, 3rd, 6th, and 12th exchange (see "AI-Generated Titles & Summaries" below); a heuristic title from the first user message is set instantly inside `appendExchange` as a fallback before the Haiku call returns. The `isTitleManuallyEdited` flag on `Conversation` is flipped to true the first time the user renames or edits a conversation, and `applyAutoGeneratedMetadata` respects that flag so AI never clobbers a name the user chose. The store is injected into both `MainWindowView` and `CompanionManager` from the app delegate.

**AI-Generated Titles & Summaries**: After every voice exchange is appended, `CompanionManager.regenerateConversationMetadataIfNeeded` checks the new exchange count against `{1, 3, 6, 12}` and — if it matches — fires a fire-and-forget background `claudeAPI.generateText` call against `claude-haiku-4-5`. The prompt asks for a strict `{"title":"...","summary":"..."}` JSON response. Results flow through `ConversationStore.applyAutoGeneratedMetadata`, which is a no-op when `isTitleManuallyEdited == true`. The previous regeneration task is cancelled before each new one so two background calls never race on the same conversation. Failures (network, parse error, cancellation) are silently logged — the heuristic fallback title stays in place.

**Menu Bar Panel Pattern**: The companion panel uses `NSStatusItem` for the menu bar icon and a custom borderless `NSPanel` for the floating control panel. The panel is non-activating so it doesn't steal focus. A global event monitor auto-dismisses it on outside clicks. The panel is draggable (`isMovableByWindowBackground = true`).

**Cursor Overlay**: A full-screen transparent `NSPanel` hosts the circle companion. It's non-activating, joins all Spaces, and never steals focus. The cursor position, response text, waveform, and pointing animations all render in this overlay via SwiftUI through `NSHostingView`.

**Global Push-To-Talk Shortcut**: Background push-to-talk uses a listen-only `CGEvent` tap instead of an AppKit global monitor so modifier-based shortcuts like `ctrl + option` are detected more reliably while the app is running in the background.

**Shared URLSession for AssemblyAI**: A single long-lived `URLSession` is shared across all AssemblyAI streaming sessions (owned by the provider, not the session). Creating and invalidating a URLSession per session corrupts the OS connection pool and causes "Socket is not connected" errors after a few rapid reconnections.

## Key Files

| File | Lines | Purpose |
|------|-------|---------|
| `leanring_buddyApp.swift` | ~70 | App entry point. `WindowGroup` displays `MainWindowView`. `CompanionAppDelegate` creates `CompanionManager`, `ConversationStore`, and `MenuBarPanelManager`, then starts the companion pipeline on launch. |
| `AcademyContent.swift` | ~530 | Static curriculum data for the Academy tab. Defines `AcademyTool`, `AcademyLesson`, `AcademyCategory`, `AcademyDifficulty` models and a hardcoded `AcademyCatalog` with 13 AI tools (Cursor, Windsurf, GitHub Copilot, Claude, Claude Code, ChatGPT, Codex, Gemini, Replit, v0, Bolt, Lovable, Midjourney, Perplexity) each with 3-5 guided lessons. |
| `CompanionManager.swift` | ~1525 | Central state machine. Owns dictation, shortcut monitoring, screen capture, Claude API, ElevenLabs TTS, overlay management, and Sparkle on/off toggle (`isSparkleCursorEnabled`). Coordinates the full push-to-talk → screenshot → Claude → TTS → pointing pipeline with multi-point support (inline `[POINT:...]` tags, parallel TTS preloading, sequential segment playback). Auto-saves voice exchanges to `ConversationStore` and triggers the Haiku-backed background title/summary regeneration pipeline. Prepends Academy lesson context to Claude system prompt when a guided lesson is active. `handleResponseChainError` and `handleTTSError` translate `SparkleProxyError` (429/401) into endpoint-specific overlay copy and the right spoken fallback. |
| `MainWindowView.swift` | ~1200 | Primary desktop window UI. Granola-style layout with sidebar (search, Home, Chat, Spaces) and detail pane (conversation list grouped by date, or conversation detail view). Sidebar footer has icon toolbar (Sparkle toggle, model picker, settings), status row, and brand row. Top bar tabs switch between Dashboard (stats + conversation history), Academy (tool catalog + guided lessons), and Insights (placeholder). Academy has category filter pills, tool cards with progress tracking, and tool detail views with lesson lists and "Start Lesson" buttons that launch guided Sparkle sessions. |
| `ConversationStore.swift` | ~380 | Persistent conversation storage. Data models: `ConversationExchange`, `Conversation` (with optional `lessonContext` for Academy lessons and `isTitleManuallyEdited` flag), `Space`. Saves/loads JSON in `~/Library/Application Support/Vibecademy/`. Groups conversations by date. Supports Spaces (folders) for organizing conversations. `startNewConversationWithTitle()` creates lesson-linked conversations from the Academy tab. `updateConversation()` (called from user-edit paths) marks the title as manually owned; `applyAutoGeneratedMetadata()` writes AI-generated titles/summaries only when the flag is unset. |
| `MenuBarPanelManager.swift` | ~243 | NSStatusItem + custom NSPanel lifecycle. Creates the circle menu bar icon, manages the floating companion panel (show/hide/position), installs click-outside-to-dismiss monitor. Panel is draggable. |
| `CompanionPanelView.swift` | ~761 | SwiftUI panel content for the menu bar dropdown. Shows companion status, push-to-talk instructions, model picker (Sonnet/Opus), permissions UI, DM feedback button, and quit button. Dark aesthetic using `DS` design system. |
| `OverlayWindow.swift` | ~1012 | Full-screen transparent `NSPanel` overlay (floating, non-activating) hosting the sparkle cursor, response text, waveform, and spinner. Stays visible above all apps and in fullscreen Spaces. Handles cursor animation, element pointing with bezier arcs, multi-monitor coordinate mapping, multi-point sequence support, and fade-out transitions. |
| `CompanionResponseOverlay.swift` | ~217 | SwiftUI view for the response text bubble and waveform displayed next to the cursor in the overlay. |
| `CompanionScreenCaptureUtility.swift` | ~132 | Multi-monitor screenshot capture using ScreenCaptureKit. Returns labeled image data for each connected display. |
| `BuddyDictationManager.swift` | ~866 | Push-to-talk voice pipeline. Handles microphone capture via `AVAudioEngine`, provider-aware permission checks, keyboard/button dictation sessions, transcript finalization, shortcut parsing, contextual keyterms, and live audio-level reporting for waveform feedback. |
| `BuddyTranscriptionProvider.swift` | ~100 | Protocol surface and provider factory for voice transcription backends. Resolves provider based on `VoiceTranscriptionProvider` in Info.plist — AssemblyAI, OpenAI, or Apple Speech. |
| `AssemblyAIStreamingTranscriptionProvider.swift` | ~490 | Streaming transcription provider. Fetches temp tokens from the Cloudflare Worker, opens an AssemblyAI v3 websocket, streams PCM16 audio, tracks turn-based transcripts, and delivers finalized text on key-up. Shares a single URLSession across all sessions. Non-2xx token-fetch responses are wrapped in `SparkleProxyError(endpoint: .transcribe, ...)` so a 429 surfaces as a friendly "Daily voice-input limit reached" message via the dictation manager's `LocalizedError`-aware error path. |
| `OpenAIAudioTranscriptionProvider.swift` | ~317 | Upload-based transcription provider. Buffers push-to-talk audio locally, uploads as WAV on release, returns finalized transcript. |
| `AppleSpeechTranscriptionProvider.swift` | ~147 | Local fallback transcription provider backed by Apple's Speech framework. |
| `BuddyAudioConversionSupport.swift` | ~108 | Audio conversion helpers. Converts live mic buffers to PCM16 mono audio and builds WAV payloads for upload-based providers. |
| `GlobalPushToTalkShortcutMonitor.swift` | ~132 | System-wide push-to-talk monitor. Owns the listen-only `CGEvent` tap and publishes press/release transitions. |
| `ClaudeAPI.swift` | ~415 | Claude vision API client with streaming (SSE) and non-streaming modes, plus a lightweight `generateText` helper for plain-text background calls (used by the title/summary metadata pipeline). TLS warmup optimization, image MIME detection, conversation history support. Streaming requests advertise Anthropic's hosted `web_search_20250305` tool (max 3 searches/turn). The SSE parser tracks content block indices so multi-block text responses (text → tool_use → tool_result → text) are joined with proper whitespace. `generateText` accepts a per-call model override so cheap metadata calls run on `claude-haiku-4-5` while the voice pipeline keeps its Sonnet/Opus selection. All non-2xx responses are wrapped in `SparkleProxyError(endpoint: .chat, ...)`. |
| `OpenAIAPI.swift` | ~142 | OpenAI GPT vision API client. |
| `ElevenLabsTTSClient.swift` | ~115 | ElevenLabs TTS client. Sends text to the Worker proxy, plays back audio via `AVAudioPlayer`. Supports preloading audio via `fetchAudioData` for multi-point segment playback. Exposes `isPlaying` and `waitForPlaybackCompletion` for sequencing. Non-2xx responses are wrapped in `SparkleProxyError(endpoint: .tts, ...)`. |
| `ElementLocationDetector.swift` | ~335 | Detects UI element locations in screenshots for cursor pointing. |
| `DesignSystem.swift` | ~879 | Design system tokens — colors, corner radii, shared styles. All UI references `DS.Colors`, `DS.CornerRadius`, etc. `overlayCursorBlue` is actually orange (`#FF8C33`), used for the sparkle icon. |
| `VibecademyAnalytics.swift` | ~122 | PostHog analytics integration (`VibecademyAnalytics`) for usage tracking. |
| `WindowPositionManager.swift` | ~262 | Window placement logic, Screen Recording permission flow, and accessibility permission helpers. |
| `AppBundleConfiguration.swift` | ~28 | Runtime configuration reader for keys stored in the app bundle Info.plist. |
| `SparkleClientCredentials.swift` | ~165 | Keychain-backed per-install bearer token (`sparkle_v1_<64 hex chars>`). Generates and persists on first access via `SecRandomCopyBytes` + `SecItemAdd`. Singleton (`SparkleClientCredentials.shared`). Used by `ClaudeAPI`, `ElevenLabsTTSClient`, and `AssemblyAIStreamingTranscriptionProvider` to authenticate every Worker call. The token is cached in-process after first read so we don't hit the Keychain on every API request. |
| `SparkleProxyError.swift` | ~140 | Typed error returned by every Sparkle Worker call (`/chat`, `/tts`, `/transcribe-token`). Conforms to `LocalizedError` so the dictation pipeline gets friendly messages for free. `fromHTTPResponse(endpoint:statusCode:responseBody:)` best-effort parses the Worker's `{ error, limit, retryAfterSeconds }` 429 body shape; bodies that don't match still produce a valid error with nil parsed fields. Exposes `isRateLimited` (HTTP 429) and `isCredentialsRejected` (HTTP 401) so `CompanionManager` can branch into endpoint-specific overlay copy and the right spoken fallback. |
| `worker/src/index.ts` | ~510 | Cloudflare Worker proxy. Three routes: `/chat` (Claude), `/tts` (ElevenLabs), `/transcribe-token` (AssemblyAI temp token). All routes require a valid `Authorization: Bearer sparkle_v1_<64hex>` header (validated by `authenticateSparkleClient`). Each route enforces a per-install daily cap via `applyEndpointRateLimit` (counters stored in KV under `<endpoint>:<utc-date>:<sha256(token)>`). The `/chat` route also strips web_search from non-current prompts and applies a tighter sub-cap before forwarding web-search-enabled requests to Anthropic. |

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

# Add the rate-limit KV namespace and copy the generated IDs into wrangler.toml
# under `binding = "RATE_LIMIT_KV"`. (If you previously created
# WEB_SEARCH_RATE_LIMIT_KV, you can keep the same namespace ID and just
# rename the binding — counters carry over.)
npx wrangler kv:namespace create RATE_LIMIT_KV
npx wrangler kv:namespace create RATE_LIMIT_KV --preview

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
