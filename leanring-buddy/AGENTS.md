# AGENTS.md - leanring-buddy (Main App Target)

## Source Files

### leanring_buddyApp.swift
- `leanring_buddyApp` — App entry point with `WindowGroup` displaying `MainWindowView`
- `CompanionAppDelegate` — `@MainActor` NSApplicationDelegate
  - Creates `CompanionManager`, `ConversationStore`, and `MenuBarPanelManager`
  - Calls `companionManager.start()` on launch
  - Wires `conversationStore` into `companionManager` for auto-saving voice exchanges
  - Shows onboarding panel if first launch or permissions missing
  - Registers app as login item via `SMAppService`

### MainWindowView.swift
- `MainWindowView` — Primary desktop window with `NavigationSplitView`
  - Sidebar: search field, Home/Chat navigation, Spaces (folders) with create/delete
  - Detail pane: conversation list grouped by date, or `ConversationDetailView`
  - Sparkle on/off toggle (`sparkleToggle`) in sidebar footer
  - Hero card (`sparkleHeroCard`) on Home view when Sparkle is off — "Meet Sparkle" with activate button
  - Status indicator showing Active/Off/Setup needed
- `ConversationRowView` — Row displaying conversation title, summary, and time
- `ConversationDetailView` — Shows conversation summary or full transcript with Summary/Transcript picker
  - Transcript shows user messages (blue avatar) and Sparkle responses (orange sparkle avatar)

### ConversationStore.swift
- `ConversationExchange` — Single user-transcript + assistant-response pair with timestamp
- `Conversation` — Collection of exchanges with title, summary, spaceId, created/updated dates
  - `displayTitle` — Auto-generates from first user message if no explicit title
- `Space` — Named folder with icon for organizing conversations
- `ConversationStore` — `ObservableObject` managing persistence
  - Saves/loads JSON in `~/Library/Application Support/Vibecademy/`
  - `appendExchange()` — Adds exchange to active conversation (or creates new one)
  - `conversationsGroupedByDate()` — Groups by Today/Yesterday/date labels
  - `createSpace()`, `deleteSpace()`, `moveConversation()` — Space management

### CompanionManager.swift
- `CompanionManager` — Central `@MainActor` state machine
  - `isNateCursorEnabled` — User preference for cursor visibility (defaults to `false`, persisted to UserDefaults)
  - `setNateCursorEnabled()` — Toggles overlay on/off
  - `conversationStore` — Reference set by app delegate for auto-saving exchanges
  - `start()` / `stop()` — Lifecycle management
  - `handleShortcutTransition()` — Push-to-talk pipeline entry point
  - `sendTranscriptToClaudeWithScreenshot()` — Core AI pipeline: screenshot → Claude → TTS → pointing
  - Transient cursor mode: if Sparkle is off, pressing hotkey temporarily shows the overlay

### MenuBarPanelManager.swift
- `MenuBarPanelManager` — `@MainActor` class for menu bar status item
  - Menu bar icon: `sparkle` SF Symbol (template mode)
  - Floating `NSPanel` for companion controls
  - Panel is draggable (`isMovableByWindowBackground = true`)

### OverlayWindow.swift
- Full-screen transparent overlay hosting the cursor companion
- Orange sparkle icon (`sparkle` SF Symbol) with glow shadow
- Waveform view replaces cap while listening
- Spinner replaces cap while processing
- Bezier arc flight animations for element pointing

### DesignSystem.swift
- `DS.Colors.overlayCursorBlue` — Actually orange (`#FF8C33`), used for the sparkle icon; kept the property name for compatibility

### worker/src/index.ts
- Cloudflare Worker proxy at `https://nativelearn-proxy.danteocualesjr.workers.dev` (worker name unchanged)
- `ELEVENLABS_VOICE_ID` = `XB0fDUnXU5powFXDhCwa` (Charlotte, female British voice)
