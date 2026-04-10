//
//  MainWindowView.swift
//  leanring-buddy
//
//  The primary desktop window with a Granola-style sidebar + main panel.
//  Sidebar: search, Home, Chat, Spaces. Main panel: conversation list
//  grouped by date, or conversation detail view.
//

import SwiftUI

struct MainWindowView: View {
    @ObservedObject var conversationStore: ConversationStore
    @ObservedObject var companionManager: CompanionManager
    @State private var selectedConversationId: UUID?
    @State private var selectedSpaceId: UUID?
    @State private var searchText: String = ""
    @State private var sidebarSelection: SidebarItem = .home
    @State private var isCreatingSpace = false
    @State private var newSpaceName = ""

    enum SidebarItem: Hashable {
        case home
        case chat
        case space(UUID)
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detailContent
        }
        .frame(minWidth: 800, minHeight: 550)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .quaternarySystemFill))
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            List(selection: Binding(
                get: { sidebarSelection },
                set: { newValue in
                    if let val = newValue {
                        sidebarSelection = val
                        selectedConversationId = nil
                    }
                }
            )) {
                Section {
                    Label("Home", systemImage: "house")
                        .tag(SidebarItem.home)
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                        .tag(SidebarItem.chat)
                }

                Section("Spaces") {
                    ForEach(conversationStore.spaces) { space in
                        Label(space.name, systemImage: space.icon)
                            .tag(SidebarItem.space(space.id))
                            .contextMenu {
                                Button("Delete Space", role: .destructive) {
                                    conversationStore.deleteSpace(space.id)
                                    if case .space(let id) = sidebarSelection, id == space.id {
                                        sidebarSelection = .home
                                    }
                                }
                            }
                    }

                    if isCreatingSpace {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .foregroundColor(.secondary)
                            TextField("Space name", text: $newSpaceName, onCommit: {
                                let name = newSpaceName.trimmingCharacters(in: .whitespaces)
                                if !name.isEmpty {
                                    conversationStore.createSpace(name: name)
                                }
                                newSpaceName = ""
                                isCreatingSpace = false
                            })
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                        }
                    }

                    Button {
                        isCreatingSpace = true
                    } label: {
                        Label("Add folder", systemImage: "folder.badge.plus")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)

            Divider()

            VStack(spacing: 8) {
                nateToggle

                HStack {
                    Text("NativeLearn")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    statusIndicator
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var nateToggle: some View {
        Toggle(isOn: Binding(
            get: { companionManager.isNateCursorEnabled },
            set: { companionManager.setNateCursorEnabled($0) }
        )) {
            HStack(spacing: 6) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 12))
                    .foregroundColor(companionManager.isNateCursorEnabled ? .orange : .secondary)
                Text("Nate")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }

    private var statusIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusLabel)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private var statusColor: Color {
        if !companionManager.allPermissionsGranted { return .orange }
        if companionManager.isNateCursorEnabled { return .green }
        return Color.secondary.opacity(0.5)
    }

    private var statusLabel: String {
        if !companionManager.allPermissionsGranted { return "Setup needed" }
        if companionManager.isNateCursorEnabled { return "Active" }
        return "Off"
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        if let conversationId = selectedConversationId,
           let conversation = conversationStore.conversations.first(where: { $0.id == conversationId }) {
            ConversationDetailView(
                conversation: conversation,
                conversationStore: conversationStore,
                onBack: { selectedConversationId = nil }
            )
        } else {
            conversationListView
        }
    }

    private var conversationListView: some View {
        let spaceFilter: UUID? = {
            if case .space(let id) = sidebarSelection { return id }
            return nil
        }()

        let groups = conversationStore.conversationsGroupedByDate(spaceId: spaceFilter)
        let filteredGroups: [(String, [Conversation])] = {
            if searchText.isEmpty { return groups }
            return groups.compactMap { label, convos in
                let filtered = convos.filter {
                    $0.displayTitle.localizedCaseInsensitiveContains(searchText)
                    || $0.summary.localizedCaseInsensitiveContains(searchText)
                    || $0.exchanges.contains { ex in
                        ex.userTranscript.localizedCaseInsensitiveContains(searchText)
                        || ex.assistantResponse.localizedCaseInsensitiveContains(searchText)
                    }
                }
                return filtered.isEmpty ? nil : (label, filtered)
            }
        }()

        return VStack(spacing: 0) {
            headerBar(title: headerTitle)

            if sidebarSelection == .home && !companionManager.isNateCursorEnabled {
                nateHeroCard
            }

            if filteredGroups.isEmpty && (sidebarSelection != .home || companionManager.isNateCursorEnabled) {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No conversations yet")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Hold Control + Option to talk to Nate")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                Spacer()
            } else if filteredGroups.isEmpty && sidebarSelection == .home && !companionManager.isNateCursorEnabled {
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredGroups, id: \.0) { label, convos in
                            Text(label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 24)
                                .padding(.top, 20)
                                .padding(.bottom, 6)

                            ForEach(convos) { conversation in
                                ConversationRowView(conversation: conversation)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedConversationId = conversation.id
                                    }
                                    .contextMenu {
                                        Menu("Move to Space") {
                                            Button("None") {
                                                conversationStore.moveConversation(conversation.id, toSpace: nil)
                                            }
                                            ForEach(conversationStore.spaces) { space in
                                                Button(space.name) {
                                                    conversationStore.moveConversation(conversation.id, toSpace: space.id)
                                                }
                                            }
                                        }
                                        Divider()
                                        Button("Delete", role: .destructive) {
                                            conversationStore.deleteConversation(conversation.id)
                                        }
                                    }
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private var nateHeroCard: some View {
        VStack(spacing: 20) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 72, height: 72)
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                }

                VStack(spacing: 6) {
                    Text("Meet Nate")
                        .font(.system(size: 20, weight: .bold))
                    Text("Your AI tutor that lives on your screen.\nHe'll walk you through any tool, step by step.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
            }

            Button {
                companionManager.setNateCursorEnabled(true)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "power")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Turn on Nate")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.orange)
                )
            }
            .buttonStyle(.plain)

            Text("Then hold  \(Text("Control + Option").bold())  to talk")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        )
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var headerTitle: String {
        switch sidebarSelection {
        case .home: return "Home"
        case .chat: return "All Conversations"
        case .space(let id):
            return conversationStore.spaces.first { $0.id == id }?.name ?? "Space"
        }
    }

    private func headerBar(title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 22, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }
}

// MARK: - Conversation Row

struct ConversationRowView: View {
    let conversation: Conversation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                if !conversation.summary.isEmpty {
                    Text(conversation.summary)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Text(timeLabel)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color.clear)
    }

    private var timeLabel: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(conversation.updatedAt) {
            formatter.dateFormat = "h:mm"
        } else {
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: conversation.updatedAt)
    }
}

// MARK: - Conversation Detail

struct ConversationDetailView: View {
    let conversation: Conversation
    let conversationStore: ConversationStore
    let onBack: () -> Void

    @State private var showTranscript = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Text(conversation.displayTitle)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)

                Spacer()

                Text(dateLabel)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Picker("", selection: $showTranscript) {
                    Text("Summary").tag(false)
                    Text("Transcript").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                if showTranscript {
                    transcriptView
                } else {
                    summaryView
                }
            }
        }
    }

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !conversation.summary.isEmpty {
                Text(conversation.summary)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("DETAILS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)

                Text("\(conversation.exchanges.count) exchange\(conversation.exchanges.count == 1 ? "" : "s")")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                Text("Created \(formattedDate(conversation.createdAt))")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            Spacer()
        }
    }

    private var transcriptView: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            ForEach(conversation.exchanges) { exchange in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.blue.opacity(0.7)))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("You")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text(exchange.userTranscript)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                        }
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "graduationcap.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.orange))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nate")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text(exchange.assistantResponse)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: conversation.createdAt)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
