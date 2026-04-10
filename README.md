# NativeLearn

An AI tutor that lives on your Mac. NativeLearn places a companion cursor called **Nate** (a small orange circle) right next to your pointer that can see your screen, listen to your voice, and teach you how to use AI tools step by step.

## What it does

- **AI Tutor**: Nate helps you become AI-native by teaching you tools like Replit, Cursor, Claude Code, Codex, and more
- **Screen-Aware**: Nate can see your screen and reference specific UI elements while teaching
- **Voice Conversation**: Hold Control+Option to talk to Nate naturally
- **Cursor Pointing**: Nate flies to and points at relevant buttons, menus, and UI elements to guide you
- **Step-by-Step**: Nate walks you through tutorials conversationally, asking what you want to build
- **Desktop App**: Full window with sidebar navigation, conversation history grouped by date, and Spaces (folders) for organizing sessions
- **Nate Toggle**: Turn Nate on/off from the desktop app — he's off by default so you can explore the app first
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

Update the voice ID in `wrangler.toml` if desired, then deploy:
```bash
npx wrangler deploy
```

Note the worker URL (e.g., `https://nativelearn-proxy.<your-subdomain>.workers.dev`).

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

1. Open NativeLearn — the desktop app window appears with a "Meet Nate" hero card
2. Click **Turn on Nate** to activate the companion cursor, or use the toggle in the sidebar
3. Hold **Control + Option** to activate push-to-talk
4. Ask Nate something like: "Hey Nate, I want to learn how to use Cursor. Can you show me?"
5. Nate will see your screen, talk back to you, and point at relevant UI elements
6. Your conversations are automatically saved — find them in the desktop app grouped by date

## Based on

Built on top of [Clicky](https://github.com/farzaa/clicky) by Farza.
