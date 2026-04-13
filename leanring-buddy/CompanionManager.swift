//
//  CompanionManager.swift
//  leanring-buddy
//
//  Central state manager for the companion voice mode. Owns the push-to-talk
//  pipeline (dictation manager + global shortcut monitor + overlay) and
//  exposes observable voice state for the panel UI.
//

import AVFoundation
import Combine
import Foundation
import PostHog
import ScreenCaptureKit
import SwiftUI

enum CompanionVoiceState {
    case idle
    case listening
    case processing
    case responding
}

@MainActor
final class CompanionManager: ObservableObject {
    @Published private(set) var voiceState: CompanionVoiceState = .idle
    @Published private(set) var lastTranscript: String?
    @Published private(set) var currentAudioPowerLevel: CGFloat = 0
    @Published private(set) var hasAccessibilityPermission = false
    @Published private(set) var hasScreenRecordingPermission = false
    @Published private(set) var hasMicrophonePermission = false
    @Published private(set) var hasScreenContentPermission = false

    /// Set by the app delegate so conversations are auto-saved to disk.
    var conversationStore: ConversationStore?

    /// When true, Sparkle is stepping through a multi-point response sequence.
    /// The overlay uses this to skip its auto-return-to-cursor after each point,
    /// keeping Sparkle at each target until the next fly command arrives.
    @Published var isMultiPointSequenceActive = false

    /// Screen location (global AppKit coords) of a detected UI element the
    /// buddy should fly to and point at. Parsed from Claude's response;
    /// observed by BlueCursorView to trigger the flight animation.
    @Published var detectedElementScreenLocation: CGPoint?
    /// The display frame (global AppKit coords) of the screen the detected
    /// element is on, so BlueCursorView knows which screen overlay should animate.
    @Published var detectedElementDisplayFrame: CGRect?
    /// Custom speech bubble text for the pointing animation. When set,
    /// BlueCursorView uses this instead of a random pointer phrase.
    @Published var detectedElementBubbleText: String?
    /// Set to true once on app launch so BlueCursorView plays the fly-in
    /// entrance animation. Reset to false after the animation starts.
    @Published var playEntranceAnimation = false

    // MARK: - Onboarding Video State (shared across all screen overlays)

    @Published var onboardingVideoPlayer: AVPlayer?
    @Published var showOnboardingVideo: Bool = false
    @Published var onboardingVideoOpacity: Double = 0.0
    private var onboardingVideoEndObserver: NSObjectProtocol?
    private var onboardingDemoTimeObserver: Any?

    // MARK: - Onboarding Prompt Bubble

    /// Text streamed character-by-character on the cursor after the onboarding video ends.
    @Published var onboardingPromptText: String = ""
    @Published var onboardingPromptOpacity: Double = 0.0
    @Published var showOnboardingPrompt: Bool = false

    // MARK: - Onboarding Music

    private var onboardingMusicPlayer: AVAudioPlayer?
    private var onboardingMusicFadeTimer: Timer?

    let buddyDictationManager = BuddyDictationManager()
    let globalPushToTalkShortcutMonitor = GlobalPushToTalkShortcutMonitor()
    let overlayWindowManager = OverlayWindowManager()
    // Response text is now displayed inline on the cursor overlay via
    // streamingResponseText, so no separate response overlay manager is needed.

    /// Base URL for the Cloudflare Worker proxy. All API requests route
    /// through this so keys never ship in the app binary.
    /// TODO: Replace with your deployed Cloudflare Worker URL after running `wrangler deploy`
    /// Example: "https://nativelearn-proxy.danteocualesjr.workers.dev"
    private static let workerBaseURL = "https://nativelearn-proxy.danteocualesjr.workers.dev"

    private lazy var claudeAPI: ClaudeAPI = {
        return ClaudeAPI(proxyURL: "\(Self.workerBaseURL)/chat", model: selectedModel)
    }()

    private lazy var elevenLabsTTSClient: ElevenLabsTTSClient = {
        return ElevenLabsTTSClient(proxyURL: "\(Self.workerBaseURL)/tts")
    }()

    /// Conversation history so Claude remembers prior exchanges within a session.
    /// Each entry is the user's transcript and Claude's response.
    private var conversationHistory: [(userTranscript: String, assistantResponse: String)] = []

    /// The currently running AI response task, if any. Cancelled when the user
    /// speaks again so a new response can begin immediately.
    private var currentResponseTask: Task<Void, Never>?

    private var shortcutTransitionCancellable: AnyCancellable?
    private var voiceStateCancellable: AnyCancellable?
    private var audioPowerCancellable: AnyCancellable?
    private var accessibilityCheckTimer: Timer?
    private var pendingKeyboardShortcutStartTask: Task<Void, Never>?
    /// Scheduled hide for transient cursor mode — cancelled if the user
    /// speaks again before the delay elapses.
    private var transientHideTask: Task<Void, Never>?

    /// True when core permissions (accessibility, screen recording, microphone)
    /// are granted. Screen content is verified lazily on first capture, so it
    /// doesn't block the overlay from appearing.
    var allPermissionsGranted: Bool {
        hasAccessibilityPermission && hasScreenRecordingPermission && hasMicrophonePermission
    }

    /// Whether the blue cursor overlay is currently visible on screen.
    /// Used by the panel to show accurate status text ("Active" vs "Ready").
    @Published private(set) var isOverlayVisible: Bool = false

    /// The Claude model used for voice responses. Persisted to UserDefaults.
    @Published var selectedModel: String = UserDefaults.standard.string(forKey: "selectedClaudeModel") ?? "claude-sonnet-4-6"

    func setSelectedModel(_ model: String) {
        selectedModel = model
        UserDefaults.standard.set(model, forKey: "selectedClaudeModel")
        claudeAPI.model = model
    }

    /// User preference for whether the Vibecademy cursor should be shown.
    /// When toggled off, the overlay is hidden and push-to-talk is disabled.
    /// Persisted to UserDefaults so the choice survives app restarts.
    @Published var isSparkleCursorEnabled: Bool = UserDefaults.standard.object(forKey: "isSparkleCursorEnabled") == nil
        ? true
        : UserDefaults.standard.bool(forKey: "isSparkleCursorEnabled")

    func setSparkleCursorEnabled(_ enabled: Bool) {
        isSparkleCursorEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "isSparkleCursorEnabled")
        transientHideTask?.cancel()
        transientHideTask = nil

        if enabled {
            overlayWindowManager.hasShownOverlayBefore = true
            overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
            isOverlayVisible = true
        } else {
            overlayWindowManager.hideOverlay()
            isOverlayVisible = false
        }
    }

    /// Whether the user has completed onboarding at least once. Persisted
    /// to UserDefaults so the Start button only appears on first launch.
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    /// Whether the user has submitted their email during onboarding.
    @Published var hasSubmittedEmail: Bool = UserDefaults.standard.bool(forKey: "hasSubmittedEmail")

    /// Submits the user's email to FormSpark and identifies them in PostHog.
    func submitEmail(_ email: String) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else { return }

        hasSubmittedEmail = true
        UserDefaults.standard.set(true, forKey: "hasSubmittedEmail")

        // Identify user in PostHog
        PostHogSDK.shared.identify(trimmedEmail, userProperties: [
            "email": trimmedEmail
        ])

        // TODO: Replace with your own email collection endpoint
        // Task {
        //     var request = URLRequest(url: URL(string: "https://your-form-endpoint")!)
        //     request.httpMethod = "POST"
        //     request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        //     request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": trimmedEmail])
        //     _ = try? await URLSession.shared.data(for: request)
        // }
    }

    func start() {
        refreshAllPermissions()
        print("🔑 Vibecademy start — accessibility: \(hasAccessibilityPermission), screen: \(hasScreenRecordingPermission), mic: \(hasMicrophonePermission), screenContent: \(hasScreenContentPermission), onboarded: \(hasCompletedOnboarding)")
        startPermissionPolling()
        bindVoiceStateObservation()
        bindAudioPowerLevel()
        bindShortcutTransitions()
        // Eagerly touch the Claude API so its TLS warmup handshake completes
        // well before the onboarding demo fires at ~40s into the video.
        _ = claudeAPI

        // Show the cursor overlay on launch so Sparkle is always visible.
        if isSparkleCursorEnabled {
            if allPermissionsGranted {
                hasCompletedOnboarding = true
            }
            overlayWindowManager.hasShownOverlayBefore = true
            overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
            isOverlayVisible = true

            if hasCompletedOnboarding {
                playEntranceAnimation = true
            }
        }
    }

    /// Called by BlueCursorView after the buddy finishes its pointing
    /// animation and returns to cursor-following mode.
    /// Triggers the onboarding sequence — dismisses the panel and restarts
    /// the overlay so the welcome animation and intro video play.
    func triggerOnboarding() {
        // Post notification so the panel manager can dismiss the panel
        NotificationCenter.default.post(name: .vibecademyDismissPanel, object: nil)

        // Mark onboarding as completed so the Start button won't appear
        // again on future launches — the cursor will auto-show instead
        hasCompletedOnboarding = true

        VibecademyAnalytics.trackOnboardingStarted()

        // Play Besaid theme at 60% volume, fade out after 1m 30s
        startOnboardingMusic()

        // Show the overlay for the first time — isFirstAppearance triggers
        // the welcome animation and onboarding video
        overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
        isOverlayVisible = true
    }

    /// Replays the onboarding experience from the "Watch Onboarding Again"
    /// footer link. Same flow as triggerOnboarding but the cursor overlay
    /// is already visible so we just restart the welcome animation and video.
    func replayOnboarding() {
        NotificationCenter.default.post(name: .vibecademyDismissPanel, object: nil)
        VibecademyAnalytics.trackOnboardingReplayed()
        startOnboardingMusic()
        // Tear down any existing overlays and recreate with isFirstAppearance = true
        overlayWindowManager.hasShownOverlayBefore = false
        overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
        isOverlayVisible = true
    }

    private func stopOnboardingMusic() {
        onboardingMusicFadeTimer?.invalidate()
        onboardingMusicFadeTimer = nil
        onboardingMusicPlayer?.stop()
        onboardingMusicPlayer = nil
    }

    private func startOnboardingMusic() {
        stopOnboardingMusic()
        guard let musicURL = Bundle.main.url(forResource: "ff", withExtension: "mp3") else {
            print("⚠️ Vibecademy: ff.mp3 not found in bundle")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: musicURL)
            player.volume = 0.3
            player.play()
            self.onboardingMusicPlayer = player

            // After 1m 30s, fade the music out over 3s
            onboardingMusicFadeTimer = Timer.scheduledTimer(withTimeInterval: 90.0, repeats: false) { [weak self] _ in
                self?.fadeOutOnboardingMusic()
            }
        } catch {
            print("⚠️ Vibecademy: Failed to play onboarding music: \(error)")
        }
    }

    private func fadeOutOnboardingMusic() {
        guard let player = onboardingMusicPlayer else { return }

        let fadeSteps = 30
        let fadeDuration: Double = 3.0
        let stepInterval = fadeDuration / Double(fadeSteps)
        let volumeDecrement = player.volume / Float(fadeSteps)
        var stepsRemaining = fadeSteps

        onboardingMusicFadeTimer = Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { [weak self] timer in
            stepsRemaining -= 1
            player.volume -= volumeDecrement

            if stepsRemaining <= 0 {
                timer.invalidate()
                player.stop()
                self?.onboardingMusicPlayer = nil
                self?.onboardingMusicFadeTimer = nil
            }
        }
    }

    func clearDetectedElementLocation() {
        detectedElementScreenLocation = nil
        detectedElementDisplayFrame = nil
        detectedElementBubbleText = nil
    }

    func stop() {
        globalPushToTalkShortcutMonitor.stop()
        buddyDictationManager.cancelCurrentDictation()
        overlayWindowManager.hideOverlay()
        transientHideTask?.cancel()

        pendingKeyboardShortcutStartTask?.cancel()
        pendingKeyboardShortcutStartTask = nil

        currentResponseTask?.cancel()
        currentResponseTask = nil
        shortcutTransitionCancellable?.cancel()
        voiceStateCancellable?.cancel()
        audioPowerCancellable?.cancel()
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = nil

        stopOnboardingMusic()
    }

    func refreshAllPermissions() {
        let previouslyHadAccessibility = hasAccessibilityPermission
        let previouslyHadScreenRecording = hasScreenRecordingPermission
        let previouslyHadMicrophone = hasMicrophonePermission
        let previouslyHadAll = allPermissionsGranted

        let currentlyHasAccessibility = WindowPositionManager.hasAccessibilityPermission()
        hasAccessibilityPermission = currentlyHasAccessibility

        if currentlyHasAccessibility {
            globalPushToTalkShortcutMonitor.start()
        } else {
            globalPushToTalkShortcutMonitor.stop()
        }

        hasScreenRecordingPermission = WindowPositionManager.hasScreenRecordingPermission()

        let micAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        hasMicrophonePermission = micAuthStatus == .authorized

        // Debug: log permission state on changes
        if previouslyHadAccessibility != hasAccessibilityPermission
            || previouslyHadScreenRecording != hasScreenRecordingPermission
            || previouslyHadMicrophone != hasMicrophonePermission {
            print("🔑 Permissions — accessibility: \(hasAccessibilityPermission), screen: \(hasScreenRecordingPermission), mic: \(hasMicrophonePermission), screenContent: \(hasScreenContentPermission)")
        }

        // Track individual permission grants as they happen
        if !previouslyHadAccessibility && hasAccessibilityPermission {
            VibecademyAnalytics.trackPermissionGranted(permission: "accessibility")
        }
        if !previouslyHadScreenRecording && hasScreenRecordingPermission {
            VibecademyAnalytics.trackPermissionGranted(permission: "screen_recording")
        }
        if !previouslyHadMicrophone && hasMicrophonePermission {
            VibecademyAnalytics.trackPermissionGranted(permission: "microphone")
        }
        // Screen content permission is persisted — once the user has approved the
        // SCShareableContent picker, we don't need to re-check it.
        if !hasScreenContentPermission {
            hasScreenContentPermission = UserDefaults.standard.bool(forKey: "hasScreenContentPermission")
        }

        if !previouslyHadAll && allPermissionsGranted {
            VibecademyAnalytics.trackAllPermissionsGranted()
        }
    }

    /// Triggers the macOS screen content picker by performing a dummy
    /// screenshot capture. Once the user approves, we persist the grant
    /// so they're never asked again during onboarding.
    @Published private(set) var isRequestingScreenContent = false

    func requestScreenContentPermission() {
        guard !isRequestingScreenContent else { return }
        isRequestingScreenContent = true
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    await MainActor.run { isRequestingScreenContent = false }
                    return
                }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = 320
                config.height = 240
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                // Verify the capture actually returned real content — a 0x0 or
                // fully-empty image means the user denied the prompt.
                let didCapture = image.width > 0 && image.height > 0
                print("🔑 Screen content capture result — width: \(image.width), height: \(image.height), didCapture: \(didCapture)")
                await MainActor.run {
                    isRequestingScreenContent = false
                    guard didCapture else { return }
                    hasScreenContentPermission = true
                    UserDefaults.standard.set(true, forKey: "hasScreenContentPermission")
                    VibecademyAnalytics.trackPermissionGranted(permission: "screen_content")

                    if allPermissionsGranted && !isOverlayVisible && isSparkleCursorEnabled {
                        hasCompletedOnboarding = true
                        overlayWindowManager.hasShownOverlayBefore = true
                        overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
                        isOverlayVisible = true
                    }
                }
            } catch {
                print("⚠️ Screen content permission request failed: \(error)")
                await MainActor.run { isRequestingScreenContent = false }
            }
        }
    }

    // MARK: - Private

    /// Triggers the system microphone prompt if the user has never been asked.
    /// Once granted/denied the status sticks and polling picks it up.
    private func promptForMicrophoneIfNotDetermined() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.hasMicrophonePermission = granted
            }
        }
    }

    /// Polls all permissions frequently so the UI updates live after the
    /// user grants them in System Settings. Screen Recording is the exception —
    /// macOS requires an app restart for that one to take effect.
    private func startPermissionPolling() {
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAllPermissions()
            }
        }
    }

    private func bindAudioPowerLevel() {
        audioPowerCancellable = buddyDictationManager.$currentAudioPowerLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] powerLevel in
                self?.currentAudioPowerLevel = powerLevel
            }
    }

    private func bindVoiceStateObservation() {
        voiceStateCancellable = buddyDictationManager.$isRecordingFromKeyboardShortcut
            .combineLatest(
                buddyDictationManager.$isFinalizingTranscript,
                buddyDictationManager.$isPreparingToRecord
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording, isFinalizing, isPreparing in
                guard let self else { return }
                // Don't override .responding — the AI response pipeline
                // manages that state directly until streaming finishes.
                guard self.voiceState != .responding else { return }

                if isFinalizing {
                    self.voiceState = .processing
                } else if isRecording {
                    self.voiceState = .listening
                } else if isPreparing {
                    self.voiceState = .processing
                } else {
                    self.voiceState = .idle
                    // If the user pressed and released the hotkey without
                    // saying anything, no response task runs — schedule the
                    // transient hide here so the overlay doesn't get stuck.
                    // Only do this when no response is in flight, otherwise
                    // the brief idle gap between recording and processing
                    // would prematurely hide the overlay.
                    if self.currentResponseTask == nil {
                        self.scheduleTransientHideIfNeeded()
                    }
                }
            }
    }

    private func bindShortcutTransitions() {
        shortcutTransitionCancellable = globalPushToTalkShortcutMonitor
            .shortcutTransitionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transition in
                self?.handleShortcutTransition(transition)
            }
    }

    private func handleShortcutTransition(_ transition: BuddyPushToTalkShortcut.ShortcutTransition) {
        switch transition {
        case .pressed:
            print("🎤 Push-to-talk: shortcut pressed (dictationInProgress: \(buddyDictationManager.isDictationInProgress), onboardingVideo: \(showOnboardingVideo))")
            guard !buddyDictationManager.isDictationInProgress else { return }
            guard !showOnboardingVideo else { return }

            // Cancel any pending transient hide so the overlay stays visible
            transientHideTask?.cancel()
            transientHideTask = nil

            // If the cursor is hidden, bring it back transiently for this interaction
            if !isSparkleCursorEnabled && !isOverlayVisible {
                overlayWindowManager.hasShownOverlayBefore = true
                overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
                isOverlayVisible = true
            }

            // Dismiss the menu bar panel so it doesn't cover the screen
            NotificationCenter.default.post(name: .vibecademyDismissPanel, object: nil)

            // Cancel any in-progress response and TTS from a previous utterance
            currentResponseTask?.cancel()
            elevenLabsTTSClient.stopPlayback()
            isMultiPointSequenceActive = false
            clearDetectedElementLocation()

            // Dismiss the onboarding prompt if it's showing
            if showOnboardingPrompt {
                withAnimation(.easeOut(duration: 0.3)) {
                    onboardingPromptOpacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.showOnboardingPrompt = false
                    self.onboardingPromptText = ""
                }
            }
    

            VibecademyAnalytics.trackPushToTalkStarted()

            pendingKeyboardShortcutStartTask?.cancel()
            pendingKeyboardShortcutStartTask = Task {
                await buddyDictationManager.startPushToTalkFromKeyboardShortcut(
                    currentDraftText: "",
                    updateDraftText: { _ in
                        // Partial transcripts are hidden (waveform-only UI)
                    },
                    submitDraftText: { [weak self] finalTranscript in
                        self?.lastTranscript = finalTranscript
                        print("🗣️ Companion received transcript: \(finalTranscript)")
                        VibecademyAnalytics.trackUserMessageSent(transcript: finalTranscript)
                        self?.sendTranscriptToClaudeWithScreenshot(transcript: finalTranscript)
                    }
                )
            }
        case .released:
            // Cancel the pending start task in case the user released the shortcut
            // before the async startPushToTalk had a chance to begin recording.
            // Without this, a quick press-and-release drops the release event and
            // leaves the waveform overlay stuck on screen indefinitely.
            VibecademyAnalytics.trackPushToTalkReleased()
            pendingKeyboardShortcutStartTask?.cancel()
            pendingKeyboardShortcutStartTask = nil
            buddyDictationManager.stopPushToTalkFromKeyboardShortcut()
        case .none:
            break
        }
    }

    // MARK: - Companion Prompt

    private static let companionVoiceResponseSystemPrompt = """
    you're sparkle, an AI tutor that lives on the user's mac. your mission is to help people become AI-native — fluent and confident with AI tools. the user just spoke to you via push-to-talk and you can see their screen(s). your reply will be spoken aloud via text-to-speech, so write the way you'd actually talk. this is an ongoing conversation — you remember everything they've said before.

    your specialty:
    - you're an expert at teaching people how to use AI tools and products: Replit, Cursor, Claude Code, Codex, ChatGPT, Windsurf, v0, Bolt, Lovable, and any other AI-powered tool.
    - when someone wants to learn a tool, walk them through it step by step like a patient teacher sitting next to them. point at the buttons they need to click, explain what each part of the interface does, and guide them through building something real.
    - be conversational. ask what they want to build or learn. tailor the tutorial to their goal. for example, if they want to learn Replit, ask what kind of project interests them, then guide them through building it.
    - celebrate small wins. when they complete a step, acknowledge it and move to the next one.
    - you can help with anything beyond AI tools too — coding, writing, general knowledge, brainstorming — but your superpower is making people comfortable and skilled with AI.

    rules:
    - default to two to four sentences for tutorial steps. be clear and actionable. BUT if the user asks you to explain more, go deeper, or elaborate, then give a thorough, detailed explanation.
    - all lowercase, casual, warm, encouraging. no emojis.
    - write for the ear, not the eye. short sentences. no lists, bullet points, markdown, or formatting — just natural speech.
    - don't use abbreviations or symbols that sound weird read aloud. write "for example" not "e.g.", spell out small numbers.
    - reference specific things you see on their screen. this is key to being a good tutor — show them you're looking at the same thing they are.
    - never say "simply" or "just" — these words make beginners feel dumb.
    - don't read out code verbatim. describe what the code does or what needs to change conversationally.
    - when teaching, give ONE step at a time. don't overwhelm with multiple steps. wait for the user to complete each step before moving on.
    - after giving a step, naturally suggest what comes next or ask a question that moves the tutorial forward. for example: "once you click that, you'll see the editor open up. go ahead and try it, then tell me what you see."
    - if the user seems stuck, offer encouragement and rephrase the instruction differently.
    - if you receive multiple screen images, the one labeled "primary focus" is where the cursor is — prioritize that one but reference others if relevant.

    element pointing:
    you have a small orange circle icon that can fly to and point at things on screen. as a tutor, pointing is your most powerful teaching tool — use it as much as possible. whenever you mention anything that's visible on screen, point at it. this makes your tutorials feel like having a real teacher sitting next to them. a static sparkle that never moves feels lifeless. a sparkle that constantly flies around to show the user exactly what you're talking about feels alive and helpful.

    your default should be to point. look for ANY reason to point at something on screen. only use [POINT:none] when absolutely nothing on screen is relevant to what you're saying.

    always point when: guiding through UI, showing where buttons are, teaching navigation, demonstrating workflows, helping find menus or settings, referencing any visible text or element, explaining what something on screen does, answering questions where you can point at something related on screen, or when the user's screen shows anything connected to the topic.

    only skip pointing when: the conversation is purely abstract with zero connection to anything visible on screen.

    you can use MULTIPLE point tags in a single response. place each [POINT:...] tag inline, right after the sentence or phrase that talks about that element. sparkle will fly to each location in order while speaking the surrounding text. this is incredibly powerful for giving tours or explaining multiple parts of an interface — sparkle will physically move from element to element as you talk about each one.

    use multiple points when: giving an overview of a UI, explaining several features, walking through a workflow that involves multiple buttons or panels, or anytime you're referencing more than one thing on screen. the more you point, the more alive and helpful the tutorial feels.

    the screenshot images are labeled with their pixel dimensions. use those dimensions as the coordinate space. the origin (0,0) is the top-left corner of the image. x increases rightward, y increases downward.

    format: [POINT:x,y:label] where x,y are integer pixel coordinates in the screenshot's coordinate space, and label is a short 1-3 word description of the element (like "search bar" or "save button"). if the element is on the cursor's screen you can omit the screen number. if the element is on a DIFFERENT screen, append :screenN where N is the screen number from the image label (e.g. :screen2). this is important — without the screen number, the cursor will point at the wrong place.

    if pointing wouldn't help for the entire response, use a single [POINT:none] at the end.

    examples:
    - single point, user wants to learn Replit: "alright, first thing — see that blue plus button up there? click that to create a new project. replit calls them repls. [POINT:180,45:create repl button]"
    - single point, user asks what a prompt is: "a prompt is basically the instruction you give to an AI. see that text box right there? that's where you'd type your prompt — the better you describe what you need, the better the result. [POINT:640,380:text input]"
    - no pointing, purely abstract question: "machine learning is how computers learn patterns from data, kind of like how you learn to recognize faces — you see enough examples and your brain figures out the pattern. [POINT:none]"
    - multiple points, giving a tour of Cursor: "okay let me show you around. see these toggle icons up top? [POINT:380,52:toggle icons] this first one opens and closes the file explorer on the left side. and this one over here [POINT:420,52:terminal toggle] toggles the terminal panel at the bottom. and all these files on the left [POINT:140,300:file explorer] are the files in your project — click any of them to open it in the editor."
    - multiple points, explaining a workflow: "to create a new file, first click the new file icon here. [POINT:160,35:new file button] then type your filename in that text field that appears. [POINT:160,55:filename input] once you hit enter, the file opens in the main editor panel over here. [POINT:700,400:editor panel]"
    - element is on screen 2: "that terminal is on your other screen — you'll want to run the command over there. [POINT:400,300:terminal:screen2]"
    """

    // MARK: - AI Response Pipeline

    /// Captures a screenshot, sends it along with the transcript to Claude,
    /// and plays the response aloud via ElevenLabs TTS. The cursor stays in
    /// the spinner/processing state until TTS audio begins playing.
    ///
    /// Claude's response may include one or more inline `[POINT:x,y:label]`
    /// tags. When multiple tags are present, Sparkle flies to each location
    /// in sequence while speaking the surrounding text segments.
    private func sendTranscriptToClaudeWithScreenshot(transcript: String) {
        currentResponseTask?.cancel()
        elevenLabsTTSClient.stopPlayback()

        currentResponseTask = Task {
            voiceState = .processing
            print("📡 Sending transcript to Claude: \"\(transcript.prefix(80))...\"")

            do {
                let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()

                guard !Task.isCancelled else { return }

                let labeledImages = screenCaptures.map { capture in
                    let dimensionInfo = " (image dimensions: \(capture.screenshotWidthInPixels)x\(capture.screenshotHeightInPixels) pixels)"
                    return (data: capture.imageData, label: capture.label + dimensionInfo)
                }

                let historyForAPI = conversationHistory.map { entry in
                    (userPlaceholder: entry.userTranscript, assistantResponse: entry.assistantResponse)
                }

                let (fullResponseText, _) = try await claudeAPI.analyzeImageStreaming(
                    images: labeledImages,
                    systemPrompt: Self.companionVoiceResponseSystemPrompt,
                    conversationHistory: historyForAPI,
                    userPrompt: transcript,
                    onTextChunk: { _ in }
                )

                guard !Task.isCancelled else { return }

                let segments = Self.parseResponseIntoSegments(from: fullResponseText)
                let pointSegmentCount = segments.filter({ $0.pointCoordinate != nil }).count
                let hasMultiplePointSegments = pointSegmentCount > 1
                print("📡 Claude responded: \(segments.count) segments, \(pointSegmentCount) with coordinates (multi-point: \(hasMultiplePointSegments))")

                let fullSpokenText = segments.map { $0.spokenText }.joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if hasMultiplePointSegments {
                    try await playMultiPointResponse(
                        segments: segments,
                        screenCaptures: screenCaptures
                    )
                } else {
                    try await playSinglePointResponse(
                        segments: segments,
                        screenCaptures: screenCaptures
                    )
                }

                guard !Task.isCancelled else { return }

                conversationHistory.append((
                    userTranscript: transcript,
                    assistantResponse: fullSpokenText
                ))

                if conversationHistory.count > 10 {
                    conversationHistory.removeFirst(conversationHistory.count - 10)
                }

                conversationStore?.appendExchange(
                    userTranscript: transcript,
                    assistantResponse: fullSpokenText
                )

                print("🧠 Conversation history: \(conversationHistory.count) exchanges")
                VibecademyAnalytics.trackAIResponseReceived(response: fullSpokenText)

            } catch is CancellationError {
                voiceState = .idle
                isMultiPointSequenceActive = false
            } catch {
                VibecademyAnalytics.trackResponseError(error: error.localizedDescription)
                print("⚠️ Companion response error: \(error)")
                isMultiPointSequenceActive = false
                speakCreditsErrorFallback()
            }

            if !Task.isCancelled {
                voiceState = .idle
                isMultiPointSequenceActive = false
                scheduleTransientHideIfNeeded()
            }
        }
    }

    /// Handles responses with zero or one POINT tag — the original behavior.
    /// Sparkle flies to one target (if any) while the full text plays as a
    /// single TTS audio clip.
    private func playSinglePointResponse(
        segments: [MultiPointResponseSegment],
        screenCaptures: [CompanionScreenCapture]
    ) async throws {
        let firstSegmentWithPoint = segments.first(where: { $0.pointCoordinate != nil })
        let fullSpokenText = segments.map { $0.spokenText }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Switch to idle BEFORE setting the location so the sparkle becomes
        // visible and can fly to the target. Without this, the spinner hides
        // the sparkle and the flight animation is invisible.
        if firstSegmentWithPoint != nil {
            voiceState = .idle
        }

        if let segment = firstSegmentWithPoint,
           let pointCoordinate = segment.pointCoordinate {
            let globalLocation = convertPointToGlobalScreenCoordinates(
                pointCoordinate: pointCoordinate,
                screenNumber: segment.pointScreenNumber,
                screenCaptures: screenCaptures
            )
            if let globalLocation {
                detectedElementScreenLocation = globalLocation.location
                detectedElementDisplayFrame = globalLocation.displayFrame
                VibecademyAnalytics.trackElementPointed(elementLabel: segment.pointLabel)
                print("🎯 Element pointing: (\(Int(pointCoordinate.x)), \(Int(pointCoordinate.y))) → \"\(segment.pointLabel ?? "element")\"")
            }
        }

        if !fullSpokenText.isEmpty {
            do {
                try await elevenLabsTTSClient.speakText(fullSpokenText)
                voiceState = .responding
            } catch {
                VibecademyAnalytics.trackTTSError(error: error.localizedDescription)
                print("⚠️ ElevenLabs TTS error: \(error)")
                speakCreditsErrorFallback()
            }
        }
    }

    /// Handles responses with multiple POINT tags. Pre-fetches all TTS audio
    /// in parallel, then plays each segment sequentially — flying Sparkle to
    /// the associated screen location before each audio clip starts.
    private func playMultiPointResponse(
        segments: [MultiPointResponseSegment],
        screenCaptures: [CompanionScreenCapture]
    ) async throws {
        print("🔀 Multi-point: preloading TTS for \(segments.count) segments")

        // Pre-fetch TTS audio for every non-empty text segment in parallel
        // so there's no network delay between segments during playback.
        // Each segment is fetched independently; we collect the results by index.
        var preloadedAudioBySegmentIndex: [Int: Data] = [:]

        for (index, segment) in segments.enumerated() {
            let textToSpeak = segment.spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !textToSpeak.isEmpty else { continue }
            guard !Task.isCancelled else { return }

            do {
                let audioData = try await elevenLabsTTSClient.fetchAudioData(textToSpeak)
                preloadedAudioBySegmentIndex[index] = audioData
            } catch {
                print("⚠️ ElevenLabs TTS preload error for segment \(index): \(error)")
            }
        }

        guard !Task.isCancelled else { return }
        print("🔀 Multi-point: preloaded \(preloadedAudioBySegmentIndex.count) audio segments, starting playback")

        isMultiPointSequenceActive = true
        voiceState = .idle

        for (index, segment) in segments.enumerated() {
            guard !Task.isCancelled else { return }

            if let pointCoordinate = segment.pointCoordinate {
                let globalLocation = convertPointToGlobalScreenCoordinates(
                    pointCoordinate: pointCoordinate,
                    screenNumber: segment.pointScreenNumber,
                    screenCaptures: screenCaptures
                )
                if let globalLocation {
                    detectedElementScreenLocation = globalLocation.location
                    detectedElementDisplayFrame = globalLocation.displayFrame
                    VibecademyAnalytics.trackElementPointed(elementLabel: segment.pointLabel)
                    print("🎯 Multi-point [\(index + 1)/\(segments.count)]: (\(Int(pointCoordinate.x)), \(Int(pointCoordinate.y))) → \"\(segment.pointLabel ?? "element")\"")

                    // Wait for the bezier flight animation to reach the target.
                    // Flight duration is 0.6–1.4s; 1.0s covers most cases.
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { return }
                }
            }

            if let audioData = preloadedAudioBySegmentIndex[index] {
                do {
                    try elevenLabsTTSClient.playAudioData(audioData)
                    voiceState = .responding
                    await elevenLabsTTSClient.waitForPlaybackCompletion()
                } catch {
                    print("⚠️ ElevenLabs TTS playback error for segment \(index): \(error)")
                }
            }
        }

        isMultiPointSequenceActive = false
        print("🔀 Multi-point: sequence complete")
    }

    // MARK: - Coordinate Conversion

    /// Converts a POINT tag's screenshot-pixel coordinate to global AppKit
    /// screen coordinates, returning the location and display frame for the
    /// overlay to use.
    private func convertPointToGlobalScreenCoordinates(
        pointCoordinate: CGPoint,
        screenNumber: Int?,
        screenCaptures: [CompanionScreenCapture]
    ) -> (location: CGPoint, displayFrame: CGRect)? {
        let targetScreenCapture: CompanionScreenCapture? = {
            if let screenNumber,
               screenNumber >= 1 && screenNumber <= screenCaptures.count {
                return screenCaptures[screenNumber - 1]
            }
            return screenCaptures.first(where: { $0.isCursorScreen })
        }()

        guard let targetScreenCapture else { return nil }

        let screenshotWidth = CGFloat(targetScreenCapture.screenshotWidthInPixels)
        let screenshotHeight = CGFloat(targetScreenCapture.screenshotHeightInPixels)
        let displayWidth = CGFloat(targetScreenCapture.displayWidthInPoints)
        let displayHeight = CGFloat(targetScreenCapture.displayHeightInPoints)
        let displayFrame = targetScreenCapture.displayFrame

        guard screenshotWidth > 0, screenshotHeight > 0 else {
            print("⚠️ Screenshot dimensions are zero — skipping element pointing")
            return nil
        }

        let clampedX = max(0, min(pointCoordinate.x, screenshotWidth))
        let clampedY = max(0, min(pointCoordinate.y, screenshotHeight))

        let displayLocalX = clampedX * (displayWidth / screenshotWidth)
        let displayLocalY = clampedY * (displayHeight / screenshotHeight)

        let appKitY = displayHeight - displayLocalY

        let globalLocation = CGPoint(
            x: displayLocalX + displayFrame.origin.x,
            y: appKitY + displayFrame.origin.y
        )

        return (location: globalLocation, displayFrame: displayFrame)
    }

    /// If the cursor is in transient mode (user toggled "Show Sparkle" off),
    /// waits for TTS playback and any pointing animation to finish, then
    /// fades out the overlay after a 1-second pause. Cancelled automatically
    /// if the user starts another push-to-talk interaction.
    private func scheduleTransientHideIfNeeded() {
        guard !isSparkleCursorEnabled && isOverlayVisible else { return }

        transientHideTask?.cancel()
        transientHideTask = Task {
            // Wait for TTS audio to finish playing
            while elevenLabsTTSClient.isPlaying {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
            }

            // Wait for pointing animation to finish (location is cleared
            // when the buddy flies back to the cursor)
            while detectedElementScreenLocation != nil {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
            }

            // Pause 1s after everything finishes, then fade out
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            overlayWindowManager.fadeOutAndHideOverlay()
            isOverlayVisible = false
        }
    }

    /// Speaks a hardcoded error message using macOS system TTS when API
    /// credits run out. Uses NSSpeechSynthesizer so it works even when
    /// ElevenLabs is down.
    private func speakCreditsErrorFallback() {
        let utterance = "Looks like I'm having trouble connecting right now. Please check the API configuration and try again."
        let synthesizer = NSSpeechSynthesizer()
        synthesizer.startSpeaking(utterance)
        voiceState = .responding
    }

    // MARK: - Point Tag Parsing

    /// Result of parsing a [POINT:...] tag from Claude's response.
    struct PointingParseResult {
        /// The response text with the [POINT:...] tag removed — this is what gets spoken.
        let spokenText: String
        /// The parsed pixel coordinate, or nil if Claude said "none" or no tag was found.
        let coordinate: CGPoint?
        /// Short label describing the element (e.g. "run button"), or "none".
        let elementLabel: String?
        /// Which screen the coordinate refers to (1-based), or nil to default to cursor screen.
        let screenNumber: Int?
    }

    /// Parses a [POINT:x,y:label:screenN] or [POINT:none] tag from the end of Claude's response.
    /// Returns the spoken text (tag removed) and the optional coordinate + label + screen number.
    static func parsePointingCoordinates(from responseText: String) -> PointingParseResult {
        // Match [POINT:none] or [POINT:123,456:label] or [POINT:123,456:label:screen2]
        let pattern = #"\[POINT:(?:none|(\d+)\s*,\s*(\d+)(?::([^\]:\s][^\]:]*?))?(?::screen(\d+))?)\]\s*$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: responseText, range: NSRange(responseText.startIndex..., in: responseText)) else {
            return PointingParseResult(spokenText: responseText, coordinate: nil, elementLabel: nil, screenNumber: nil)
        }

        guard let tagRange = Range(match.range, in: responseText) else {
            return PointingParseResult(spokenText: responseText, coordinate: nil, elementLabel: nil, screenNumber: nil)
        }
        let spokenText = String(responseText[..<tagRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it's [POINT:none]
        guard match.numberOfRanges >= 3,
              let xRange = Range(match.range(at: 1), in: responseText),
              let yRange = Range(match.range(at: 2), in: responseText),
              let x = Double(responseText[xRange]),
              let y = Double(responseText[yRange]) else {
            return PointingParseResult(spokenText: spokenText, coordinate: nil, elementLabel: "none", screenNumber: nil)
        }

        var elementLabel: String? = nil
        if match.numberOfRanges >= 4, let labelRange = Range(match.range(at: 3), in: responseText) {
            elementLabel = String(responseText[labelRange]).trimmingCharacters(in: .whitespaces)
        }

        var screenNumber: Int? = nil
        if match.numberOfRanges >= 5, let screenRange = Range(match.range(at: 4), in: responseText) {
            screenNumber = Int(responseText[screenRange])
        }

        return PointingParseResult(
            spokenText: spokenText,
            coordinate: CGPoint(x: x, y: y),
            elementLabel: elementLabel,
            screenNumber: screenNumber
        )
    }

    // MARK: - Multi-Point Parsing

    /// A single segment of a multi-point response. Each segment has spoken text
    /// and an optional coordinate for Sparkle to fly to while that text plays.
    struct MultiPointResponseSegment {
        let spokenText: String
        let pointCoordinate: CGPoint?
        let pointLabel: String?
        let pointScreenNumber: Int?
    }

    /// Splits Claude's response at every inline `[POINT:...]` tag into an ordered
    /// array of segments. Text before each tag becomes the spoken text for that
    /// segment, paired with the tag's coordinate. Any trailing text after the
    /// last tag becomes a final text-only segment.
    ///
    /// Returns a single text-only segment (no coordinate) if there are no POINT
    /// tags or only a `[POINT:none]`.
    static func parseResponseIntoSegments(from responseText: String) -> [MultiPointResponseSegment] {
        let pattern = #"\[POINT:(?:none|(\d+)\s*,\s*(\d+)(?::([^\]:\s][^\]:]*?))?(?::screen(\d+))?)\]"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [MultiPointResponseSegment(spokenText: responseText, pointCoordinate: nil, pointLabel: nil, pointScreenNumber: nil)]
        }

        let fullRange = NSRange(responseText.startIndex..., in: responseText)
        let matches = regex.matches(in: responseText, options: [], range: fullRange)

        if matches.isEmpty {
            return [MultiPointResponseSegment(spokenText: responseText, pointCoordinate: nil, pointLabel: nil, pointScreenNumber: nil)]
        }

        // Check if the only match is [POINT:none] — treat as a single text-only segment
        if matches.count == 1 {
            let match = matches[0]
            let matchedString = String(responseText[Range(match.range, in: responseText)!])
            if matchedString == "[POINT:none]" {
                let spokenText = responseText.replacingOccurrences(of: "[POINT:none]", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return [MultiPointResponseSegment(spokenText: spokenText, pointCoordinate: nil, pointLabel: nil, pointScreenNumber: nil)]
            }
        }

        var segments: [MultiPointResponseSegment] = []
        var currentTextStartIndex = responseText.startIndex

        for match in matches {
            guard let tagRange = Range(match.range, in: responseText) else { continue }

            let textBeforeTag = String(responseText[currentTextStartIndex..<tagRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Parse coordinate from this match
            var coordinate: CGPoint? = nil
            var elementLabel: String? = nil
            var screenNumber: Int? = nil

            if match.numberOfRanges >= 3,
               let xRange = Range(match.range(at: 1), in: responseText),
               let yRange = Range(match.range(at: 2), in: responseText),
               let x = Double(responseText[xRange]),
               let y = Double(responseText[yRange]) {
                coordinate = CGPoint(x: x, y: y)

                if match.numberOfRanges >= 4, let labelRange = Range(match.range(at: 3), in: responseText) {
                    elementLabel = String(responseText[labelRange]).trimmingCharacters(in: .whitespaces)
                }
                if match.numberOfRanges >= 5, let screenRange = Range(match.range(at: 4), in: responseText) {
                    screenNumber = Int(responseText[screenRange])
                }
            }

            // Skip segments that have no text AND no coordinate (e.g. adjacent [POINT:none] tags)
            if !textBeforeTag.isEmpty || coordinate != nil {
                segments.append(MultiPointResponseSegment(
                    spokenText: textBeforeTag,
                    pointCoordinate: coordinate,
                    pointLabel: elementLabel,
                    pointScreenNumber: screenNumber
                ))
            }

            currentTextStartIndex = tagRange.upperBound
        }

        // Any text after the last POINT tag becomes a trailing text-only segment
        let trailingText = String(responseText[currentTextStartIndex...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailingText.isEmpty {
            segments.append(MultiPointResponseSegment(
                spokenText: trailingText,
                pointCoordinate: nil,
                pointLabel: nil,
                pointScreenNumber: nil
            ))
        }

        if segments.isEmpty {
            return [MultiPointResponseSegment(spokenText: responseText, pointCoordinate: nil, pointLabel: nil, pointScreenNumber: nil)]
        }

        return segments
    }

    // MARK: - Onboarding Video

    /// Called by BlueCursorView after the welcome text disappears.
    /// Skips straight to showing the onboarding prompt with usage instructions.
    func setupOnboardingVideo() {
        startOnboardingPromptStream()
    }

    func tearDownOnboardingVideo() {
        showOnboardingVideo = false
        if let timeObserver = onboardingDemoTimeObserver {
            onboardingVideoPlayer?.removeTimeObserver(timeObserver)
            onboardingDemoTimeObserver = nil
        }
        onboardingVideoPlayer?.pause()
        onboardingVideoPlayer = nil
        if let observer = onboardingVideoEndObserver {
            NotificationCenter.default.removeObserver(observer)
            onboardingVideoEndObserver = nil
        }
    }

    private func startOnboardingPromptStream() {
        let message = "hold control + option to talk to me. try asking me to teach you something!"
        onboardingPromptText = ""
        showOnboardingPrompt = true
        onboardingPromptOpacity = 0.0

        withAnimation(.easeIn(duration: 0.4)) {
            onboardingPromptOpacity = 1.0
        }

        var currentIndex = 0
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            guard currentIndex < message.count else {
                timer.invalidate()
                // Auto-dismiss after 10 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                    guard self.showOnboardingPrompt else { return }
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.onboardingPromptOpacity = 0.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        self.showOnboardingPrompt = false
                        self.onboardingPromptText = ""
                    }
                }
                return
            }
            let index = message.index(message.startIndex, offsetBy: currentIndex)
            self.onboardingPromptText.append(message[index])
            currentIndex += 1
        }
    }

    /// Gradually raises an AVPlayer's volume from its current level to the
    /// target over the specified duration, creating a smooth audio fade-in.
    private func fadeInVideoAudio(player: AVPlayer, targetVolume: Float, duration: Double) {
        let steps = 20
        let stepInterval = duration / Double(steps)
        let volumeIncrement = (targetVolume - player.volume) / Float(steps)
        var stepsRemaining = steps

        Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { timer in
            stepsRemaining -= 1
            player.volume += volumeIncrement

            if stepsRemaining <= 0 {
                timer.invalidate()
                player.volume = targetVolume
            }
        }
    }

    // MARK: - Onboarding Demo Interaction

    private static let onboardingDemoSystemPrompt = """
    you're sparkle, a small sparkle-shaped buddy and AI tutor living on the user's screen. you're showing off during onboarding — look at their screen and find ONE specific, concrete thing to point at. pick something with a clear name or identity: a specific app icon (say its name), a specific word or phrase of text you can read, a specific filename, a specific button label, a specific tab title, a specific image you can describe. do NOT point at vague things like "a window" or "some text" — be specific about exactly what you see.

    make a short quirky 3-6 word observation about the specific thing you picked — something fun, playful, or curious that shows you actually read/recognized it. no emojis ever. NEVER quote or repeat text you see on screen — just react to it. keep it to 6 words max, no exceptions.

    CRITICAL COORDINATE RULE: you MUST only pick elements near the CENTER of the screen. your x coordinate must be between 20%-80% of the image width. your y coordinate must be between 20%-80% of the image height. do NOT pick anything in the top 20%, bottom 20%, left 20%, or right 20% of the screen. no menu bar items, no dock icons, no sidebar items, no items near any edge. only things clearly in the middle area of the screen. if the only interesting things are near the edges, pick something boring in the center instead.

    respond with ONLY your short comment followed by the coordinate tag. nothing else. all lowercase.

    format: your comment [POINT:x,y:label]

    the screenshot images are labeled with their pixel dimensions. use those dimensions as the coordinate space. origin (0,0) is top-left. x increases rightward, y increases downward.
    """

    /// Captures a screenshot and asks Claude to find something interesting to
    /// point at, then triggers the buddy's flight animation. Used during
    /// onboarding to demo the pointing feature while the intro video plays.
    func performOnboardingDemoInteraction() {
        // Don't interrupt an active voice response
        guard voiceState == .idle || voiceState == .responding else { return }

        Task {
            do {
                let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()

                // Only send the cursor screen so Claude can't pick something
                // on a different monitor that we can't point at.
                guard let cursorScreenCapture = screenCaptures.first(where: { $0.isCursorScreen }) else {
                    print("🎯 Onboarding demo: no cursor screen found")
                    return
                }

                let dimensionInfo = " (image dimensions: \(cursorScreenCapture.screenshotWidthInPixels)x\(cursorScreenCapture.screenshotHeightInPixels) pixels)"
                let labeledImages = [(data: cursorScreenCapture.imageData, label: cursorScreenCapture.label + dimensionInfo)]

                let (fullResponseText, _) = try await claudeAPI.analyzeImageStreaming(
                    images: labeledImages,
                    systemPrompt: Self.onboardingDemoSystemPrompt,
                    userPrompt: "look around my screen and find something interesting to point at",
                    onTextChunk: { _ in }
                )

                let parseResult = Self.parsePointingCoordinates(from: fullResponseText)

                guard let pointCoordinate = parseResult.coordinate else {
                    print("🎯 Onboarding demo: no element to point at")
                    return
                }

                let screenshotWidth = CGFloat(cursorScreenCapture.screenshotWidthInPixels)
                let screenshotHeight = CGFloat(cursorScreenCapture.screenshotHeightInPixels)
                let displayWidth = CGFloat(cursorScreenCapture.displayWidthInPoints)
                let displayHeight = CGFloat(cursorScreenCapture.displayHeightInPoints)
                let displayFrame = cursorScreenCapture.displayFrame

                let clampedX = max(0, min(pointCoordinate.x, screenshotWidth))
                let clampedY = max(0, min(pointCoordinate.y, screenshotHeight))
                let displayLocalX = clampedX * (displayWidth / screenshotWidth)
                let displayLocalY = clampedY * (displayHeight / screenshotHeight)
                let appKitY = displayHeight - displayLocalY
                let globalLocation = CGPoint(
                    x: displayLocalX + displayFrame.origin.x,
                    y: appKitY + displayFrame.origin.y
                )

                detectedElementBubbleText = parseResult.spokenText
                detectedElementScreenLocation = globalLocation
                detectedElementDisplayFrame = displayFrame
                print("🎯 Onboarding demo: pointing at \"\(parseResult.elementLabel ?? "element")\" — \"\(parseResult.spokenText)\"")
            } catch {
                print("⚠️ Onboarding demo error: \(error)")
            }
        }
    }
}
