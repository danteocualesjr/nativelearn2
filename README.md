# Sparkle

An AI tutor that lives on your Mac. Sparkle places a companion cursor (an orange sparkle shape) right next to your pointer that can see your screen, listen to your voice, and teach you how to use AI tools step by step.

## What it does

- **AI Tutor**: Sparkle helps you become AI-native by teaching you tools like Replit, Cursor, Claude Code, Codex, and more
- **Screen-Aware**: Sparkle can see your screen and reference specific UI elements while teaching
- **Voice Conversation**: Hold Control+Option to talk to Sparkle naturally
- **Cursor Pointing**: Sparkle flies to and points at relevant buttons, menus, and UI elements to guide you
- **Step-by-Step**: Sparkle walks you through tutorials conversationally, asking what you want to build
- **Desktop App**: Full window with sidebar navigation, conversation history grouped by date, and Spaces (folders) for organizing sessions
- **Sparkle Toggle**: Turn Sparkle on/off from the desktop app — he's off by default so you can explore the app first
- **Conversation History**: Every voice session is saved as a summary and full transcript

## Prerequisites

- macOS 14.2+
- Xcode 15+
- Node.js + npm (for the Cloudflare Worker)
- API keys for: Anthropic, AssemblyAI, ElevenLabs
- Cloudflare account (free tier works)

## Setup

### 1. Deploy the Worker

```bash
cd worker
npm install
```

Set your API secrets:
```bash
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY
```

Create a KV namespace for web search rate limiting:
```bash
npx wrangler kv:namespace create WEB_SEARCH_RATE_LIMIT_KV
npx wrangler kv:namespace create WEB_SEARCH_RATE_LIMIT_KV --preview
```

Copy the generated IDs into `worker/wrangler.toml` and uncomment the `[[kv_namespaces]]` binding. `WEB_SEARCH_DAILY_LIMIT` defaults to `20` web-search-enabled requests per client per UTC day.

Update the voice ID in `wrangler.toml` if desired, then deploy:
```bash
npx wrangler deploy
```

Note the worker URL (e.g., `https://sparkle-proxy.<your-subdomain>.workers.dev`).

### 2. Update the Worker URL in Swift

In `CompanionManager.swift`, replace the `workerBaseURL` with your deployed worker URL.

### 3. Build and Run

```
open leanring-buddy.xcodeproj
```

- Set your development team for code signing
- Select the `leanring-buddy` scheme
- Build and run (Cmd+R)
- Grant permissions when prompted: Screen Recording, Accessibility, Microphone

## Usage

1. Open Sparkle — the desktop app window appears with a "Meet Sparkle" hero card
2. Click **Turn on Sparkle** to activate the companion cursor, or use the toggle in the sidebar
3. Hold **Control + Option** to activate push-to-talk
4. Ask Sparkle something like: "Hey Sparkle, I want to learn how to use Cursor. Can you show me?"
5. Sparkle will see your screen, talk back to you, and point at relevant UI elements
6. Your conversations are automatically saved — find them in the desktop app grouped by date
