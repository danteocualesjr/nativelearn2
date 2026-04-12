//
//  ConversationStore.swift
//  leanring-buddy
//
//  Persistent storage for voice conversations between the user and Sparkle.
//  Each conversation is a session (from first push-to-talk to last),
//  containing multiple exchanges (user transcript + Sparkle response).
//  Stored as JSON files in ~/Library/Application Support/Vibecademy/.
//

import Combine
import Foundation

// MARK: - Tool Type

enum ConversationToolType: String, Codable, CaseIterable {
    case mobileApp = "mobile_app"
    case webApp = "web_app"
    case internalTool = "internal_tool"
    case aiAgent = "ai_agent"

    var displayName: String {
        switch self {
        case .mobileApp: return "Mobile App"
        case .webApp: return "Web App"
        case .internalTool: return "Internal Tool"
        case .aiAgent: return "AI Agent"
        }
    }

    var iconName: String {
        switch self {
        case .mobileApp: return "iphone"
        case .webApp: return "globe"
        case .internalTool: return "rectangle.3.group"
        case .aiAgent: return "cpu"
        }
    }
}

struct ConversationExchange: Codable, Identifiable {
    let id: UUID
    let userTranscript: String
    let assistantResponse: String
    let timestamp: Date

    init(userTranscript: String, assistantResponse: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.userTranscript = userTranscript
        self.assistantResponse = assistantResponse
        self.timestamp = timestamp
    }
}

struct Conversation: Codable, Identifiable {
    let id: UUID
    var title: String
    var summary: String
    var spaceId: UUID?
    var toolType: ConversationToolType?
    var isArchived: Bool?
    var exchanges: [ConversationExchange]
    let createdAt: Date
    var updatedAt: Date

    init(title: String = "", summary: String = "", spaceId: UUID? = nil, toolType: ConversationToolType? = nil) {
        self.id = UUID()
        self.title = title
        self.summary = summary
        self.spaceId = spaceId
        self.toolType = toolType
        self.isArchived = false
        self.exchanges = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var archived: Bool { isArchived ?? false }

    var resolvedToolType: ConversationToolType {
        toolType ?? .webApp
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if let first = exchanges.first {
            let preview = first.userTranscript.prefix(60)
            return preview.count < first.userTranscript.count
                ? "\(preview)..."
                : String(preview)
        }
        return "New Conversation"
    }
}

struct Space: Codable, Identifiable {
    let id: UUID
    var name: String
    var icon: String
    let createdAt: Date

    init(name: String, icon: String = "folder") {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.createdAt = Date()
    }
}

final class ConversationStore: ObservableObject {
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var spaces: [Space] = []
    @Published var activeConversationId: UUID?

    private let storageDirectory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDirectory = appSupport.appendingPathComponent("Vibecademy", isDirectory: true)

        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)

        loadAll()
    }

    // MARK: - Active Conversation

    var activeConversation: Conversation? {
        guard let id = activeConversationId else { return nil }
        return conversations.first { $0.id == id }
    }

    func startNewConversation() -> UUID {
        let conversation = Conversation()
        conversations.insert(conversation, at: 0)
        activeConversationId = conversation.id
        save()
        return conversation.id
    }

    func appendExchange(userTranscript: String, assistantResponse: String) {
        if activeConversationId == nil {
            _ = startNewConversation()
        }

        // If the activeConversationId points to a conversation that no longer
        // exists (e.g. it was deleted or failed to load), start a fresh one
        // instead of silently dropping the exchange.
        if conversations.firstIndex(where: { $0.id == activeConversationId }) == nil {
            activeConversationId = nil
            _ = startNewConversation()
        }

        guard let idx = conversations.firstIndex(where: { $0.id == activeConversationId }) else { return }

        let exchange = ConversationExchange(
            userTranscript: userTranscript,
            assistantResponse: assistantResponse
        )
        conversations[idx].exchanges.append(exchange)
        conversations[idx].updatedAt = Date()

        if conversations[idx].title.isEmpty && conversations[idx].exchanges.count == 1 {
            let preview = userTranscript.prefix(60)
            conversations[idx].title = preview.count < userTranscript.count
                ? "\(preview)..."
                : String(preview)
        }

        if conversations[idx].exchanges.count <= 3 {
            conversations[idx].summary = conversations[idx].exchanges
                .map { $0.userTranscript }
                .joined(separator: " → ")
        }

        save()
    }

    func updateConversation(_ conversationId: UUID, title: String, summary: String, toolType: ConversationToolType) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].title = title
        conversations[idx].summary = summary
        conversations[idx].toolType = toolType
        save()
    }

    func endCurrentConversation() {
        activeConversationId = nil
    }

    // MARK: - Spaces

    func createSpace(name: String) {
        let space = Space(name: name)
        spaces.append(space)
        save()
    }

    func moveConversation(_ conversationId: UUID, toSpace spaceId: UUID?) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].spaceId = spaceId
        save()
    }

    func archiveConversation(_ conversationId: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].isArchived = true
        if activeConversationId == conversationId {
            activeConversationId = nil
        }
        save()
    }

    func unarchiveConversation(_ conversationId: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].isArchived = false
        save()
    }

    func deleteConversation(_ conversationId: UUID) {
        conversations.removeAll { $0.id == conversationId }
        if activeConversationId == conversationId {
            activeConversationId = nil
        }
        save()
    }

    func deleteSpace(_ spaceId: UUID) {
        for i in conversations.indices where conversations[i].spaceId == spaceId {
            conversations[i].spaceId = nil
        }
        spaces.removeAll { $0.id == spaceId }
        save()
    }

    // MARK: - Grouping

    func conversationsGroupedByDate(spaceId: UUID? = nil) -> [(String, [Conversation])] {
        let filtered = (spaceId == nil
            ? conversations
            : conversations.filter { $0.spaceId == spaceId })
            .filter { !$0.archived }

        let sorted = filtered.sorted { $0.updatedAt > $1.updatedAt }
        let calendar = Calendar.current

        var groups: [(String, [Conversation])] = []
        var currentLabel = ""
        var currentGroup: [Conversation] = []

        for conversation in sorted {
            let label: String
            if calendar.isDateInToday(conversation.updatedAt) {
                label = "Today"
            } else if calendar.isDateInYesterday(conversation.updatedAt) {
                label = "Yesterday"
            } else if calendar.isDate(conversation.updatedAt, equalTo: Date(), toGranularity: .weekOfYear) {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE"
                label = formatter.string(from: conversation.updatedAt)
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM d"
                label = formatter.string(from: conversation.updatedAt)
            }

            if label != currentLabel {
                if !currentGroup.isEmpty {
                    groups.append((currentLabel, currentGroup))
                }
                currentLabel = label
                currentGroup = [conversation]
            } else {
                currentGroup.append(conversation)
            }
        }

        if !currentGroup.isEmpty {
            groups.append((currentLabel, currentGroup))
        }

        return groups
    }

    func conversationsForSpace(_ spaceId: UUID) -> [Conversation] {
        conversations.filter { $0.spaceId == spaceId }
    }

    // MARK: - Reload

    func reload() {
        loadAll()
    }

    // MARK: - Persistence

    private var conversationsURL: URL { storageDirectory.appendingPathComponent("conversations.json") }
    private var spacesURL: URL { storageDirectory.appendingPathComponent("spaces.json") }

    private func loadAll() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: conversationsURL),
           let decoded = try? decoder.decode([Conversation].self, from: data) {
            conversations = decoded
        }
        if let data = try? Data(contentsOf: spacesURL),
           let decoded = try? decoder.decode([Space].self, from: data) {
            spaces = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        if let data = try? encoder.encode(conversations) {
            try? data.write(to: conversationsURL, options: .atomic)
        }
        if let data = try? encoder.encode(spaces) {
            try? data.write(to: spacesURL, options: .atomic)
        }
    }
}
