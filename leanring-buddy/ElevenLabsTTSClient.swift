//
//  ElevenLabsTTSClient.swift
//  leanring-buddy
//
//  Streams text-to-speech audio from ElevenLabs and plays it back
//  through the system audio output. Uses the streaming endpoint so
//  playback begins before the full audio has been generated.
//

import AVFoundation
import Foundation

@MainActor
final class ElevenLabsTTSClient {
    private let proxyURL: URL
    private let session: URLSession

    /// The audio player for the current TTS playback. Kept alive so the
    /// audio finishes playing even if the caller doesn't hold a reference.
    private var audioPlayer: AVAudioPlayer?

    init(proxyURL: String) {
        guard let parsedURL = URL(string: proxyURL) else {
            fatalError("ElevenLabsTTSClient: invalid proxy URL string — \(proxyURL)")
        }
        self.proxyURL = parsedURL

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }

    /// Fetches TTS audio from ElevenLabs without playing it. Use this to
    /// preload audio for multiple segments before sequential playback.
    /// Throws on network or decoding errors. Cancellation-safe.
    func fetchAudioData(_ text: String) async throws -> Data {
        var request = URLRequest(url: proxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        // Identify this Sparkle install to the Worker proxy. Without this
        // header the request is rejected with HTTP 401, since the proxy
        // gates all upstream API calls on a valid Sparkle bearer token.
        let clientBearerToken = SparkleClientCredentials.shared.currentClientToken
        request.setValue("Bearer \(clientBearerToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_flash_v2_5",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ElevenLabsTTS", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // Wrap non-2xx in SparkleProxyError so CompanionManager can
            // detect a 429 (daily TTS budget exhausted) and degrade to
            // the system voice instead of speaking the misleading
            // "trouble connecting" credits-error utterance.
            throw SparkleProxyError.fromHTTPResponse(
                endpoint: .tts,
                statusCode: httpResponse.statusCode,
                responseBody: data
            )
        }

        try Task.checkCancellation()
        return data
    }

    /// Plays previously fetched audio data. Replaces any in-progress playback.
    func playAudioData(_ data: Data) throws {
        let player = try AVAudioPlayer(data: data)
        self.audioPlayer = player
        player.play()
        print("🔊 ElevenLabs TTS: playing \(data.count / 1024)KB audio")
    }

    /// Blocks until the current audio playback finishes. Returns immediately
    /// if nothing is playing. Checks every 200ms. Cancellation-safe.
    func waitForPlaybackCompletion() async {
        while isPlaying {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return }
        }
    }

    /// Sends `text` to ElevenLabs TTS and plays the resulting audio.
    /// Convenience wrapper around fetchAudioData + playAudioData.
    /// Throws on network or decoding errors. Cancellation-safe.
    func speakText(_ text: String) async throws {
        let audioData = try await fetchAudioData(text)
        try playAudioData(audioData)
    }

    /// Whether TTS audio is currently playing back.
    var isPlaying: Bool {
        audioPlayer?.isPlaying ?? false
    }

    /// Stops any in-progress playback immediately.
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
}
