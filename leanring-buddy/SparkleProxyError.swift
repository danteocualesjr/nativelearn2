//
//  SparkleProxyError.swift
//  leanring-buddy
//
//  Typed error returned by every Sparkle Worker call (`/chat`, `/tts`,
//  `/transcribe-token`). Wrapping non-2xx responses in a single concrete
//  type lets `CompanionManager` branch cleanly on the two interesting
//  states — daily rate limit (HTTP 429) and rejected credentials
//  (HTTP 401) — and produce friendlier UX copy than the generic
//  "couldn't reach Sparkle's brain" message.
//
//  All non-2xx responses from the Worker are routed through
//  `SparkleProxyError.fromHTTPResponse(...)`, which best-effort parses
//  the JSON body shape:
//
//      { "error": "Daily chat limit reached",
//        "limit": 200,
//        "retryAfterSeconds": 41213 }
//
//  Bodies that don't match that shape (e.g. an upstream Anthropic 5xx
//  forwarded as-is, or a CDN HTML error page) still produce a valid
//  `SparkleProxyError` — the parsed fields are simply nil.
//

import Foundation

/// A non-2xx response from the Sparkle Cloudflare Worker proxy.
///
/// Conforms to `LocalizedError` so the existing transcription
/// pipeline (which already calls `error.localizedDescription`) gets a
/// friendly message for free without us threading the typed error
/// through additional call sites.
struct SparkleProxyError: LocalizedError {

    /// Which Worker route returned the error. Used both to choose
    /// user-facing copy and to tag analytics.
    enum Endpoint: String {
        /// `/chat` — Claude vision + streaming chat.
        case chat
        /// `/tts` — ElevenLabs text-to-speech audio.
        case tts
        /// `/transcribe-token` — short-lived AssemblyAI websocket token.
        case transcribe
    }

    /// The Worker route that returned the error.
    let endpoint: Endpoint

    /// The HTTP status code returned by the Worker (e.g. 401, 429, 500).
    let statusCode: Int

    /// The `error` string from the Worker JSON body, if present.
    /// Falls back to the raw response body string when the body wasn't
    /// JSON-shaped.
    let serverErrorMessage: String?

    /// The `limit` value from the Worker JSON body. Only set on 429
    /// responses from `applyEndpointRateLimit` / `applyWebSearchRateLimit`.
    let dailyLimit: Int?

    /// Seconds until the per-day counter rolls over (UTC midnight). Only
    /// set on 429 responses.
    let retryAfterSeconds: Int?

    /// True when the Worker returned 429 — the daily budget for this
    /// endpoint is exhausted.
    var isRateLimited: Bool { statusCode == 429 }

    /// True when the Worker rejected the request because the bearer
    /// token was missing or malformed (HTTP 401). This usually means
    /// the on-device Keychain token got wiped or the user is on a
    /// version that predates `SparkleClientCredentials`.
    var isCredentialsRejected: Bool { statusCode == 401 }

    /// Friendly text used by `LocalizedError`-aware call sites
    /// (notably `BuddyDictationManager.userFacingErrorMessage`). Keeping
    /// the rate-limit / credentials copy here means the dictation
    /// pipeline gets the same UX treatment as `CompanionManager`
    /// without a second branching block.
    var errorDescription: String? {
        if isRateLimited {
            switch endpoint {
            case .chat:
                return "Daily Sparkle limit reached — try again tomorrow."
            case .tts:
                return "Daily voice limit reached — using system voice."
            case .transcribe:
                return "Daily voice-input limit reached — try again tomorrow."
            }
        }
        if isCredentialsRejected {
            return "Sparkle credentials were rejected — try restarting the app."
        }
        if let serverErrorMessage, !serverErrorMessage.isEmpty {
            return "Sparkle proxy error (\(endpoint.rawValue), HTTP \(statusCode)): \(serverErrorMessage)"
        }
        return "Sparkle proxy error (\(endpoint.rawValue), HTTP \(statusCode))."
    }

    /// Best-effort parse of a non-2xx response body into a typed proxy
    /// error. The parser is deliberately lenient — any field can be
    /// missing — because the Worker forwards upstream Anthropic /
    /// ElevenLabs / AssemblyAI errors without rewriting them, and those
    /// payloads don't follow our `{ error, limit, retryAfterSeconds }`
    /// shape.
    static func fromHTTPResponse(
        endpoint: Endpoint,
        statusCode: Int,
        responseBody: Data
    ) -> SparkleProxyError {
        var parsedServerErrorMessage: String? = nil
        var parsedDailyLimit: Int? = nil
        var parsedRetryAfterSeconds: Int? = nil

        if let parsedJSONObject = try? JSONSerialization.jsonObject(with: responseBody) as? [String: Any] {
            parsedServerErrorMessage = parsedJSONObject["error"] as? String
            parsedDailyLimit = parsedJSONObject["limit"] as? Int
            parsedRetryAfterSeconds = parsedJSONObject["retryAfterSeconds"] as? Int
        }

        // Fall back to the raw body string when the JSON shape wasn't
        // ours — this preserves the previous debug-friendly behavior
        // where the response text shows up in error logs.
        if parsedServerErrorMessage == nil {
            let rawBodyString = String(data: responseBody, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let rawBodyString, !rawBodyString.isEmpty {
                parsedServerErrorMessage = rawBodyString
            }
        }

        return SparkleProxyError(
            endpoint: endpoint,
            statusCode: statusCode,
            serverErrorMessage: parsedServerErrorMessage,
            dailyLimit: parsedDailyLimit,
            retryAfterSeconds: parsedRetryAfterSeconds
        )
    }
}
