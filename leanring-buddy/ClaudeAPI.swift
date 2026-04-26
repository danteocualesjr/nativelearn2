//
//  ClaudeAPI.swift
//  Claude API Implementation with streaming support
//

import Foundation

/// Claude API helper with streaming for progressive text display.
class ClaudeAPI {
    private static let tlsWarmupLock = NSLock()
    private static var hasStartedTLSWarmup = false
    private static let agentDebugLogPath = "/Users/dantecualesjr/Documents/Projects/Projects_2026/nativelearn2/.cursor/debug-60fa08.log"

    private let apiURL: URL
    var model: String
    private let session: URLSession

    private static func writeAgentDebugLog(
        location: String,
        message: String,
        hypothesisId: String,
        data: [String: Any]
    ) {
        let payload: [String: Any] = [
            "sessionId": "60fa08",
            "runId": "pre-fix-web-search-review",
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]

        guard JSONSerialization.isValidJSONObject(payload),
              let encodedPayload = try? JSONSerialization.data(withJSONObject: payload),
              let newline = "\n".data(using: .utf8) else {
            return
        }

        let logURL = URL(fileURLWithPath: Self.agentDebugLogPath)
        FileManager.default.createFile(atPath: Self.agentDebugLogPath, contents: nil)

        guard let fileHandle = try? FileHandle(forWritingTo: logURL) else {
            return
        }

        defer {
            try? fileHandle.close()
        }

        try? fileHandle.seekToEnd()
        try? fileHandle.write(contentsOf: encodedPayload)
        try? fileHandle.write(contentsOf: newline)
    }

    init(proxyURL: String, model: String = "claude-sonnet-4-6") {
        guard let parsedURL = URL(string: proxyURL) else {
            fatalError("ClaudeAPI: invalid proxy URL string — \(proxyURL)")
        }
        self.apiURL = parsedURL
        self.model = model

        // Use .default instead of .ephemeral so TLS session tickets are cached.
        // Ephemeral sessions do a full TLS handshake on every request, which causes
        // transient -1200 (errSSLPeerHandshakeFail) errors with large image payloads.
        // Disable URL/cookie caching to avoid storing responses or credentials on disk.
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        config.urlCache = nil
        config.httpCookieStorage = nil
        self.session = URLSession(configuration: config)

        // Fire a lightweight HEAD request in the background to pre-establish the TLS
        // connection. This caches the TLS session ticket so the first real API call
        // (which carries a large image payload) doesn't need a cold TLS handshake.
        warmUpTLSConnectionIfNeeded()
    }

    private func makeAPIRequest() -> URLRequest {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// Detects the MIME type of image data by inspecting the first bytes.
    /// Screen captures from ScreenCaptureKit are JPEG, but pasted images from the
    /// clipboard are PNG. The API rejects requests where the declared media_type
    /// doesn't match the actual image format.
    private func detectImageMediaType(for imageData: Data) -> String {
        // PNG files start with the 8-byte signature: 89 50 4E 47 0D 0A 1A 0A
        if imageData.count >= 4 {
            let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
            let firstFourBytes = [UInt8](imageData.prefix(4))
            if firstFourBytes == pngSignature {
                return "image/png"
            }
        }
        // Default to JPEG — screen captures use JPEG compression
        return "image/jpeg"
    }

    /// Sends a no-op HEAD request to the API host to establish and cache a TLS session.
    /// Failures are silently ignored — this is purely an optimization.
    private func warmUpTLSConnectionIfNeeded() {
        Self.tlsWarmupLock.lock()
        let shouldStartTLSWarmup = !Self.hasStartedTLSWarmup
        if shouldStartTLSWarmup {
            Self.hasStartedTLSWarmup = true
        }
        Self.tlsWarmupLock.unlock()

        guard shouldStartTLSWarmup else { return }

        guard var warmupURLComponents = URLComponents(url: apiURL, resolvingAgainstBaseURL: false) else {
            return
        }

        // The TLS session ticket is host-scoped, so warming the root host is enough.
        // Hitting the host instead of `/v1/messages` avoids extra endpoint-specific noise.
        warmupURLComponents.path = "/"
        warmupURLComponents.query = nil
        warmupURLComponents.fragment = nil

        guard let warmupURL = warmupURLComponents.url else {
            return
        }

        var warmupRequest = URLRequest(url: warmupURL)
        warmupRequest.httpMethod = "HEAD"
        warmupRequest.timeoutInterval = 10
        session.dataTask(with: warmupRequest) { _, _, _ in
            // Response doesn't matter — the TLS handshake is the goal
        }.resume()
    }

    /// Send a vision request to Claude with streaming.
    /// Calls `onTextChunk` on the main actor each time new text arrives so the UI updates progressively.
    /// Returns the full accumulated text and total duration when the stream completes.
    func analyzeImageStreaming(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)] = [],
        userPrompt: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval) {
        let startTime = Date()

        var request = makeAPIRequest()

        // Build messages array
        var messages: [[String: Any]] = []

        for (userPlaceholder, assistantResponse) in conversationHistory {
            messages.append(["role": "user", "content": userPlaceholder])
            messages.append(["role": "assistant", "content": assistantResponse])
        }

        // Build current message with all labeled images + prompt
        var contentBlocks: [[String: Any]] = []
        for image in images {
            contentBlocks.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": detectImageMediaType(for: image.data),
                    "data": image.data.base64EncodedString()
                ]
            ])
            contentBlocks.append([
                "type": "text",
                "text": image.label
            ])
        }
        contentBlocks.append([
            "type": "text",
            "text": userPrompt
        ])
        messages.append(["role": "user", "content": contentBlocks])

        // Advertise Anthropic's hosted web search tool. Claude only invokes it when
        // a question genuinely needs current information (the system prompt also
        // gates this). max_uses caps the number of searches per turn so a single
        // exchange can't run away on cost — Anthropic bills ~$10 per 1,000 searches.
        // max_tokens is bumped to 2048 because search responses tend to be longer
        // (Claude inlines findings + a brief synthesis).
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "stream": true,
            "system": systemPrompt,
            "messages": messages,
            "tools": [
                [
                    "type": "web_search_20250305",
                    "name": "web_search",
                    "max_uses": 3
                ]
            ]
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData
        let payloadMB = Double(bodyData.count) / 1_048_576.0
        print("🌐 Claude streaming request: \(String(format: "%.1f", payloadMB))MB, \(images.count) image(s)")
        let lowercaseUserPrompt = userPrompt.lowercased()
        let promptHasCurrentInformationSignal = [
            "latest",
            "news",
            "current",
            "today",
            "this week",
            "recent",
            "look up",
            "search",
            "weather"
        ].contains { lowercaseUserPrompt.contains($0) }
        // #region agent log
        Self.writeAgentDebugLog(
            location: "ClaudeAPI.swift:170",
            message: "claude streaming request prepared",
            hypothesisId: "H1,H2",
            data: [
                "model": model,
                "imageCount": images.count,
                "conversationHistoryCount": conversationHistory.count,
                "payloadMegabytes": payloadMB,
                "hasWebSearchTool": true,
                "webSearchMaxUses": 3,
                "maxTokens": 2048,
                "promptHasCurrentInformationSignal": promptHasCurrentInformationSignal
            ]
        )
        // #endregion

        // Use bytes streaming for SSE (Server-Sent Events)
        let (byteStream, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "ClaudeAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"]
            )
        }
        // #region agent log
        Self.writeAgentDebugLog(
            location: "ClaudeAPI.swift:199",
            message: "claude streaming http response received",
            hypothesisId: "H1",
            data: [
                "statusCode": httpResponse.statusCode,
                "contentType": httpResponse.value(forHTTPHeaderField: "content-type") ?? "missing"
            ]
        )
        // #endregion

        // If non-2xx status, read the full body as error text
        guard (200...299).contains(httpResponse.statusCode) else {
            var errorBodyChunks: [String] = []
            for try await line in byteStream.lines {
                errorBodyChunks.append(line)
            }
            let errorBody = errorBodyChunks.joined(separator: "\n")
            // #region agent log
            Self.writeAgentDebugLog(
                location: "ClaudeAPI.swift:218",
                message: "claude streaming request failed",
                hypothesisId: "H1",
                data: [
                    "statusCode": httpResponse.statusCode,
                    "errorBodyLength": errorBody.count,
                    "errorBodyContainsWebSearch": errorBody.localizedCaseInsensitiveContains("web_search"),
                    "errorBodyContainsTool": errorBody.localizedCaseInsensitiveContains("tool"),
                    "errorBodyContainsBeta": errorBody.localizedCaseInsensitiveContains("beta"),
                    "errorBodyContainsModel": errorBody.localizedCaseInsensitiveContains("model")
                ]
            )
            // #endregion
            throw NSError(
                domain: "ClaudeAPI",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "API Error (\(httpResponse.statusCode)): \(errorBody)"]
            )
        }

        // Parse SSE stream — each event is "data: {json}\n\n"
        var accumulatedResponseText = ""
        // Track which content block the most recent text_delta belonged to. With
        // the web_search tool enabled, Claude's response is split across multiple
        // content blocks (text → server_tool_use → web_search_tool_result → text).
        // When we cross from one text block into another we insert a space so the
        // joined output doesn't fuse two blocks together (e.g. "let me check" +
        // "the news" becoming "let me checkthe news"). Tool-use and tool-result
        // blocks are silently skipped — they're not spoken.
        var indexOfMostRecentTextContentBlock: Int? = nil
        var eventTypeCounts: [String: Int] = [:]
        var contentBlockTypeCounts: [String: Int] = [:]
        var textDeltaCount = 0
        var inputJSONDeltaCount = 0
        var inputJSONDeltaCharacterCount = 0
        var insertedTextBlockSeparatorCount = 0
        var observedTextContentBlockIndices: [Int] = []
        var didSeeWebSearchServerToolUse = false
        var didSeeWebSearchToolResult = false

        for try await line in byteStream.lines {
            // SSE lines look like: "data: {...}"
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6)) // Drop "data: " prefix

            // End of stream marker
            guard jsonString != "[DONE]" else { break }

            guard let jsonData = jsonString.data(using: .utf8),
                  let eventPayload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let eventType = eventPayload["type"] as? String else {
                continue
            }
            eventTypeCounts[eventType, default: 0] += 1

            if eventType == "content_block_start",
               let contentBlock = eventPayload["content_block"] as? [String: Any],
               let contentBlockType = contentBlock["type"] as? String {
                contentBlockTypeCounts[contentBlockType, default: 0] += 1
                if contentBlockType == "server_tool_use",
                   let toolName = contentBlock["name"] as? String,
                   toolName == "web_search" {
                    didSeeWebSearchServerToolUse = true
                }
                if contentBlockType == "web_search_tool_result" {
                    didSeeWebSearchToolResult = true
                }
            }

            if eventType == "content_block_delta",
               let delta = eventPayload["delta"] as? [String: Any],
               let deltaType = delta["type"] as? String,
               deltaType == "input_json_delta" {
                inputJSONDeltaCount += 1
                inputJSONDeltaCharacterCount += (delta["partial_json"] as? String)?.count ?? 0
            }

            // We care about content_block_delta events that contain text chunks
            if eventType == "content_block_delta",
               let delta = eventPayload["delta"] as? [String: Any],
               let deltaType = delta["type"] as? String,
               deltaType == "text_delta",
               let textChunk = delta["text"] as? String {
                textDeltaCount += 1
                let currentContentBlockIndex = eventPayload["index"] as? Int
                if let currentContentBlockIndex = currentContentBlockIndex,
                   !observedTextContentBlockIndices.contains(currentContentBlockIndex) {
                    observedTextContentBlockIndices.append(currentContentBlockIndex)
                }
                let isCrossingIntoNewTextBlock: Bool = {
                    guard let currentContentBlockIndex = currentContentBlockIndex,
                          let indexOfMostRecentTextContentBlock = indexOfMostRecentTextContentBlock else {
                        return false
                    }
                    return currentContentBlockIndex != indexOfMostRecentTextContentBlock
                }()
                if isCrossingIntoNewTextBlock,
                   let lastCharacter = accumulatedResponseText.last,
                   !lastCharacter.isWhitespace {
                    insertedTextBlockSeparatorCount += 1
                    accumulatedResponseText += " "
                }
                indexOfMostRecentTextContentBlock = currentContentBlockIndex
                accumulatedResponseText += textChunk
                // Send the accumulated text so far to the UI for progressive rendering
                let currentAccumulatedText = accumulatedResponseText
                await onTextChunk(currentAccumulatedText)
            }
        }

        // #region agent log
        Self.writeAgentDebugLog(
            location: "ClaudeAPI.swift:308",
            message: "claude streaming sse summary",
            hypothesisId: "H2,H3",
            data: [
                "eventTypeCounts": eventTypeCounts,
                "contentBlockTypeCounts": contentBlockTypeCounts,
                "textDeltaCount": textDeltaCount,
                "inputJSONDeltaCount": inputJSONDeltaCount,
                "inputJSONDeltaCharacterCount": inputJSONDeltaCharacterCount,
                "insertedTextBlockSeparatorCount": insertedTextBlockSeparatorCount,
                "observedTextContentBlockIndices": observedTextContentBlockIndices,
                "didSeeWebSearchServerToolUse": didSeeWebSearchServerToolUse,
                "didSeeWebSearchToolResult": didSeeWebSearchToolResult,
                "accumulatedResponseTextLength": accumulatedResponseText.count
            ]
        )
        // #endregion

        let duration = Date().timeIntervalSince(startTime)
        return (text: accumulatedResponseText, duration: duration)
    }

    /// Non-streaming fallback for validation requests where we don't need progressive display.
    func analyzeImage(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)] = [],
        userPrompt: String
    ) async throws -> (text: String, duration: TimeInterval) {
        let startTime = Date()

        var request = makeAPIRequest()

        var messages: [[String: Any]] = []
        for (userPlaceholder, assistantResponse) in conversationHistory {
            messages.append(["role": "user", "content": userPlaceholder])
            messages.append(["role": "assistant", "content": assistantResponse])
        }

        // Build current message with all labeled images + prompt
        var contentBlocks: [[String: Any]] = []
        for image in images {
            contentBlocks.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": detectImageMediaType(for: image.data),
                    "data": image.data.base64EncodedString()
                ]
            ])
            contentBlocks.append([
                "type": "text",
                "text": image.label
            ])
        }
        contentBlocks.append([
            "type": "text",
            "text": userPrompt
        ])
        messages.append(["role": "user", "content": contentBlocks])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 256,
            "system": systemPrompt,
            "messages": messages
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData
        let payloadMB = Double(bodyData.count) / 1_048_576.0
        print("🌐 Claude request: \(String(format: "%.1f", payloadMB))MB, \(images.count) image(s)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let responseString = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "ClaudeAPI",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: "API Error: \(responseString)"]
            )
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let textBlock = content.first(where: { ($0["type"] as? String) == "text" }),
              let text = textBlock["text"] as? String else {
            throw NSError(
                domain: "ClaudeAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response format"]
            )
        }

        let duration = Date().timeIntervalSince(startTime)
        return (text: text, duration: duration)
    }
}
