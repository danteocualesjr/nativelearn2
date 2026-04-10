//
//  MainWindowView.swift
//  leanring-buddy
//
//  Primary desktop window styled after Granola. Left sidebar with search,
//  navigation, and spaces. Main panel shows conversation sessions grouped
//  by date, or a conversation detail view with summary + transcript.
//

import SwiftUI

private let warmBackground = Color(red: 0.98, green: 0.97, blue: 0.95)
private let sidebarBackground = Color(red: 0.96, green: 0.95, blue: 0.92)
private let sidebarSelected = Color(red: 0.93, green: 0.91, blue: 0.88)
private let sidebarHover = Color(red: 0.94, green: 0.93, blue: 0.90)
private let subtleText = Color(red: 0.55, green: 0.53, blue: 0.50)
private let accentOrange = Color(red: 0.95, green: 0.55, blue: 0.20)

struct MainWindowView: View {
    @ObservedObject var conversationStore: ConversationStore
    @ObservedObject var companionManager: CompanionManager
    @State private var selectedConversationId: UUID?
    @State private var searchText: String = ""
    @State private var sidebarSelection: SidebarItem = .home
    @State private var isCreatingSpace = false
    @State private var newSpaceName = ""
    @State private var hoveredSidebarItem: SidebarItem?

    enum SidebarItem: Hashable {
        case home
        case chat
        case space(UUID)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebarView
                .frame(width: 220)
            Divider()
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(warmBackground)
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 52)

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(subtleText)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                Spacer()
                Text("⌘K")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(subtleText.opacity(0.6))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(subtleText.opacity(0.2), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(warmBackground)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 16)

            // Navigation
            VStack(spacing: 2) {
                sidebarRow(item: .home, icon: "house", label: "Home")
                sidebarRow(item: .chat, icon: "bubble.left.and.bubble.right", label: "Chat")
            }
            .padding(.horizontal, 8)

            // Spaces
            VStack(alignment: .leading, spacing: 2) {
                Text("Spaces")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(subtleText.opacity(0.7))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 6)

                ForEach(conversationStore.spaces) { space in
                    sidebarRow(item: .space(space.id), icon: space.icon, label: space.name)
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
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 13))
                            .foregroundColor(subtleText)
                            .frame(width: 20)
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }

                Button {
                    isCreatingSpace = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 13))
                            .foregroundColor(subtleText.opacity(0.6))
                            .frame(width: 20)
                        Text("Add folder")
                            .font(.system(size: 13))
                            .foregroundColor(subtleText.opacity(0.6))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)

            Spacer()

            // Footer
            Divider().opacity(0.5)
            HStack(spacing: 8) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundColor(accentOrange)
                Text("NativeLearn")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(subtleText)
                Spacer()
                Circle()
                    .fill(companionManager.allPermissionsGranted ? Color.green.opacity(0.8) : Color.orange.opacity(0.8))
                    .frame(width: 7, height: 7)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(sidebarBackground)
    }

    private func sidebarRow(item: SidebarItem, icon: String, label: String) -> some View {
        let isSelected = sidebarSelection == item
        let isHovered = hoveredSidebarItem == item

        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(isSelected ? .primary : subtleText)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .primary : .primary.opacity(0.8))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? sidebarSelected : (isHovered ? sidebarHover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            sidebarSelection = item
            selectedConversationId = nil
        }
        .onHover { hovering in
            hoveredSidebarItem = hovering ? item : nil
        }
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
            // Top bar
            HStack {
                Spacer()
            }
            .frame(height: 52)

            if filteredGroups.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(subtleText.opacity(0.3))
                    Text("No conversations yet")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(subtleText)
                    Text("Hold  Control + Option  to talk to Nate")
                        .font(.system(size: 13))
                        .foregroundColor(subtleText.opacity(0.6))
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredGroups, id: \.0) { label, convos in
                            dateSectionHeader(label)

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
                    .padding(.bottom, 24)
                }
            }
        }
        .background(warmBackground)
    }

    private func dateSectionHeader(_ label: String) -> some View {
        HStack(spacing: 8) {
            if label == "Today" {
                Circle()
                    .fill(accentOrange)
                    .frame(width: 8, height: 8)
            }
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(subtleText)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }
}

// MARK: - Conversation Row

struct ConversationRowView: View {
    let conversation: Conversation
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 14))
                .foregroundColor(subtleText.opacity(0.5))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.6))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                Text("Me")
                    .font(.system(size: 12))
                    .foregroundColor(subtleText)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 11))
                    .foregroundColor(subtleText.opacity(0.4))
                Text(timeLabel)
                    .font(.system(size: 12))
                    .foregroundColor(subtleText)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.5) : Color.clear)
        )
        .padding(.horizontal, 8)
        .onHover { hovering in isHovered = hovering }
    }

    private var timeLabel: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(conversation.updatedAt) {
            formatter.dateFormat = "h:mm"
        } else {
            formatter.dateFormat = "h:mm"
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
            // Top bar with back button
            HStack(spacing: 12) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "house")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(subtleText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.6))
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                Picker("", selection: $showTranscript) {
                    Text("Summary").tag(false)
                    Text("Transcript").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            .frame(height: 52)
            .padding(.horizontal, 28)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Title
                    Text(conversation.displayTitle)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 12)

                    // Tags
                    HStack(spacing: 8) {
                        tagBadge(icon: "calendar", text: dateLabel)
                        tagBadge(icon: "person", text: "Me")
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)

                    Divider()
                        .padding(.horizontal, 28)
                        .padding(.bottom, 20)

                    if showTranscript {
                        transcriptView
                    } else {
                        summaryView
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .background(warmBackground)
    }

    private func tagBadge(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(subtleText)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.6))
        )
    }

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 20) {
            if conversation.summary.isEmpty && conversation.exchanges.isEmpty {
                Text("No content yet.")
                    .font(.system(size: 14))
                    .foregroundColor(subtleText)
                    .padding(.horizontal, 28)
            } else if !conversation.summary.isEmpty {
                Text(conversation.summary)
                    .font(.system(size: 15, design: .default))
                    .foregroundColor(.primary)
                    .lineSpacing(4)
                    .padding(.horizontal, 28)
            } else {
                ForEach(conversation.exchanges) { exchange in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("# \(exchange.userTranscript)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(exchange.assistantResponse)
                            .font(.system(size: 14))
                            .foregroundColor(.primary.opacity(0.85))
                            .lineSpacing(3)
                    }
                    .padding(.horizontal, 28)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Divider().padding(.horizontal, 28)
                HStack(spacing: 16) {
                    Label("\(conversation.exchanges.count) exchange\(conversation.exchanges.count == 1 ? "" : "s")", systemImage: "bubble.left.and.bubble.right")
                    Label(formattedDate(conversation.createdAt), systemImage: "clock")
                }
                .font(.system(size: 12))
                .foregroundColor(subtleText)
                .padding(.horizontal, 28)
                .padding(.top, 8)
            }
        }
    }

    private var transcriptView: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(conversation.exchanges) { exchange in
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.blue.opacity(0.6)))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("You")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(subtleText)
                            Text(exchange.userTranscript)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .lineSpacing(3)
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(accentOrange)
                            .frame(width: 20, height: 20)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Nate")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(subtleText)
                            Text(exchange.assistantResponse)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .lineSpacing(3)
                        }
                    }
                }

                if exchange.id != conversation.exchanges.last?.id {
                    Divider().padding(.leading, 40)
                }
            }
        }
        .padding(.horizontal, 28)
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(conversation.createdAt) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(conversation.createdAt) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "EEEE, MMMM d"
            return formatter.string(from: conversation.createdAt)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
