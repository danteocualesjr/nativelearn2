//
//  MainWindowView.swift
//  leanring-buddy
//
//  Primary desktop window. Left sidebar with logo, search, navigation,
//  and spaces. Main panel shows a bento stats dashboard, conversation
//  sessions tiered by date, and a floating focus dock.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Theme Colors (Material Design 3 — Vibe Academy light palette)

private let themePrimary = Color(hex: "#5f5e5e")
private let themePrimaryContainer = Color(hex: "#e5e2e1")
private let themeSecondary = Color(hex: "#5f5f5f")
private let themeSecondaryContainer = Color(hex: "#e4e2e2")
private let themeTertiary = Color(hex: "#9a4800")
private let themeTertiaryContainer = Color(hex: "#fa7e1d")
private let themeSurface = Color(hex: "#f9f9f7")
private let themeOnSurface = Color(hex: "#2d3432")
private let themeSurfaceContainer = Color(hex: "#ecefec")
private let themeSurfaceContainerLow = Color(hex: "#f2f4f2")
private let themeSurfaceContainerHigh = Color(hex: "#e5e9e6")
private let themeSurfaceContainerLowest = Color.white
private let themeOnSurfaceVariant = Color(hex: "#5a605e")
private let themeOutlineVariant = Color(hex: "#adb3b0")

private let sidebarBg = Color(hex: "#f9f9f7")
private let sidebarHoverBg = Color(hex: "#dee4e0")
private let neutralGray400 = Color(hex: "#adb3b0")
private let neutralGray500 = Color(hex: "#767c79")
private let neutralGray600 = Color(hex: "#5a605e")

private let sidebarLogoColor = Color(hex: "#C0504D")

// MARK: - Tool Type Colors

private let toolTypeColors: [ConversationToolType: Color] = [
    .mobileApp: Color(hex: "#059669"),
    .webApp: Color(hex: "#2563eb"),
    .internalTool: Color(hex: "#0891b2"),
    .aiAgent: Color(hex: "#b72301"),
]

private func iconForConversation(_ conversation: Conversation) -> String {
    conversation.resolvedToolType.iconName
}

private func colorForConversation(_ conversation: Conversation) -> Color {
    toolTypeColors[conversation.resolvedToolType] ?? Color(hex: "#2563eb")
}

// MARK: - Main Window View

struct MainWindowView: View {
    @ObservedObject var conversationStore: ConversationStore
    @ObservedObject var companionManager: CompanionManager
    @State private var selectedConversationId: UUID?
    @State private var searchText: String = ""
    @State private var sidebarSelection: SidebarItem = .home
    @State private var isCreatingSpace = false
    @State private var newSpaceName = ""
    @State private var hoveredSidebarItem: SidebarItem?
    @State private var hoveredCardId: UUID?
    @State private var editingCardId: UUID?
    @State private var editingTitle: String = ""
    @State private var editingSummary: String = ""
    @State private var editingToolType: ConversationToolType = .webApp
    @AppStorage("sidebarCollapsed") private var isSidebarCollapsed = false
    @AppStorage("userDisplayName") private var userDisplayName = "Dante"
    @AppStorage("profilePhotoPath") private var profilePhotoRelativePath = ""

    enum SidebarItem: Hashable {
        case home
        case chat
        case profile
        case space(UUID)
    }

    private var sidebarWidth: CGFloat { isSidebarCollapsed ? 0 : 256 }

    private var profilePhotoImage: NSImage? {
        guard !profilePhotoRelativePath.isEmpty else { return nil }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = appSupport
            .appendingPathComponent("Vibecademy/ProfilePhotos", isDirectory: true)
            .appendingPathComponent(profilePhotoRelativePath)
        return NSImage(contentsOf: url)
    }

    var body: some View {
        HStack(spacing: 0) {
            if !isSidebarCollapsed {
                sidebarView
                    .frame(width: sidebarWidth)
                    .clipped()
            }
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(themeSurface)
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 32)

            // Logo + collapse toggle
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(sidebarLogoColor)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text("V")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    )
                Text("Vibecademy")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(themeOnSurface)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isSidebarCollapsed = true }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(neutralGray400)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .nativeTooltip("Collapse sidebar")
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(neutralGray400)
                TextField("Search sessions...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                Spacer()
                HStack(spacing: 2) {
                    monoKeycap("⌘")
                    monoKeycap("K")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(themeSurfaceContainerHigh)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 24)

            // Nav items
            VStack(spacing: 2) {
                sidebarNavRow(item: .home, icon: "house.fill", label: "Home")
                sidebarNavRow(item: .chat, icon: "bubble.left.and.bubble.right", label: "Chat")
            }
            .padding(.horizontal, 8)

            // Spaces
            VStack(alignment: .leading, spacing: 2) {
                Text("SPACES")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(neutralGray400)
                    .tracking(2)
                    .padding(.horizontal, 16)
                    .padding(.top, 32)
                    .padding(.bottom, 8)

                ForEach(conversationStore.spaces) { space in
                    sidebarNavRow(item: .space(space.id), icon: "folder", label: space.name)
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
                            .foregroundColor(neutralGray400)
                            .frame(width: 20)
                        TextField("Space name", text: $newSpaceName, onCommit: {
                            let trimmedName = newSpaceName.trimmingCharacters(in: .whitespaces)
                            if !trimmedName.isEmpty {
                                conversationStore.createSpace(name: trimmedName)
                            }
                            newSpaceName = ""
                            isCreatingSpace = false
                        })
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
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
                            .foregroundColor(neutralGray400.opacity(0.6))
                            .frame(width: 20)
                        Text("Add folder")
                            .font(.system(size: 12))
                            .foregroundColor(neutralGray400.opacity(0.6))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            // Bottom section
            sidebarBottom
        }
        .background(sidebarBg)
    }

    // MARK: - Sidebar Bottom

    private var sidebarBottom: some View {
        VStack(spacing: 2) {
            Divider().opacity(0.3).padding(.horizontal, 12)

            Button {
                companionManager.setSparkleCursorEnabled(!companionManager.isSparkleCursorEnabled)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 14))
                        .foregroundColor(companionManager.isSparkleCursorEnabled ? themeTertiary : neutralGray600)
                    Text("Sparkle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(neutralGray600)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(sparkleStatusColor)
                            .frame(width: 7, height: 7)
                        Text(sparkleStatusShortLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(neutralGray500)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

            Button {
                sidebarSelection = .profile
                selectedConversationId = nil
            } label: {
                HStack(spacing: 12) {
                    if let photo = profilePhotoImage {
                        Image(nsImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 22, height: 22)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.circle")
                            .font(.system(size: 14))
                            .foregroundColor(sidebarSelection == .profile ? themeOnSurface : neutralGray600)
                    }
                    Text("Profile")
                        .font(.system(size: 13, weight: sidebarSelection == .profile ? .semibold : .medium))
                        .foregroundColor(sidebarSelection == .profile ? themeOnSurface : neutralGray600)
                    Spacer()
                    Text(userDisplayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(themePrimary)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(themePrimary.opacity(0.1))
                        )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(sidebarSelection == .profile ? sidebarHoverBg.opacity(0.35) : Color.clear)
                )
                .overlay(alignment: .leading) {
                    if sidebarSelection == .profile {
                        Rectangle()
                            .fill(themePrimary)
                            .frame(width: 2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .nativeTooltip("Profile and display name")
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(neutralGray600)
                    Text("Settings")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(neutralGray600)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Sidebar Helpers

    private func sidebarNavRow(item: SidebarItem, icon: String, label: String) -> some View {
        let isSelected = sidebarSelection == item
        let isHovered = hoveredSidebarItem == item
        let activeColor = themeOnSurface

        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? activeColor : neutralGray600)
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? activeColor : neutralGray600)
            Spacer()
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? sidebarHoverBg.opacity(0.3) : Color.clear)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(themePrimary)
                    .frame(width: 2)
            }
        }
        .opacity(isSelected || isHovered ? 1.0 : 0.7)
        .contentShape(Rectangle())
        .onTapGesture {
            sidebarSelection = item
            selectedConversationId = nil
        }
        .onHover { hovering in
            hoveredSidebarItem = hovering ? item : nil
        }
    }

    private func sessionHoverButton(
        icon: String,
        tooltip: String,
        isDestructive: Bool = false,
        lightStyle: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(
                    isDestructive
                        ? (lightStyle ? Color.white : Color(hex: "#dc2626"))
                        : (lightStyle ? Color.white : themeOnSurfaceVariant)
                )
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            isDestructive
                                ? (lightStyle ? Color.red.opacity(0.5) : Color(hex: "#dc2626").opacity(0.1))
                                : (lightStyle ? Color.white.opacity(0.2) : themeOnSurface.opacity(0.06))
                        )
                )
        }
        .buttonStyle(.plain)
        .nativeTooltip(tooltip)
        .transition(.opacity)
        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }

    private func monoKeycap(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(neutralGray500)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(sidebarHoverBg)
            )
    }

    private var sparkleStatusColor: Color {
        if !companionManager.allPermissionsGranted { return Color.orange.opacity(0.8) }
        if companionManager.isSparkleCursorEnabled { return Color.green.opacity(0.8) }
        return neutralGray400.opacity(0.5)
    }

    private var sparkleStatusShortLabel: String {
        if !companionManager.allPermissionsGranted { return "Setup" }
        if companionManager.isSparkleCursorEnabled {
            switch companionManager.voiceState {
            case .idle: return "Active"
            case .listening: return "Listening"
            case .processing: return "Processing"
            case .responding: return "Speaking"
            }
        }
        return "Off"
    }

    private var userInitialLetterForToolbar: String {
        let trimmed = userDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first {
            return String(first).uppercased()
        }
        return "?"
    }

    // MARK: - Detail Routing

    @ViewBuilder
    private var detailContent: some View {
        if let conversationId = selectedConversationId,
           let conversation = conversationStore.conversations.first(where: { $0.id == conversationId }) {
            ConversationDetailView(
                conversation: conversation,
                conversationStore: conversationStore,
                onBack: { selectedConversationId = nil }
            )
        } else if sidebarSelection == .profile {
            ProfileDetailView(
                userDisplayName: $userDisplayName,
                companionManager: companionManager,
                conversationStore: conversationStore
            )
        } else {
            dashboardView
        }
    }

    // MARK: - Dashboard (Main Content)

    private var dashboardView: some View {
        let spaceFilter: UUID? = {
            switch sidebarSelection {
            case .space(let id): return id
            case .home, .chat, .profile: return nil
            }
        }()

        let allGroups = conversationStore.conversationsGroupedByDate(spaceId: spaceFilter)
        let filteredGroups: [(String, [Conversation])] = {
            if searchText.isEmpty { return allGroups }
            return allGroups.compactMap { label, conversations in
                let filtered = conversations.filter {
                    $0.displayTitle.localizedCaseInsensitiveContains(searchText)
                    || $0.summary.localizedCaseInsensitiveContains(searchText)
                    || $0.exchanges.contains { exchange in
                        exchange.userTranscript.localizedCaseInsensitiveContains(searchText)
                        || exchange.assistantResponse.localizedCaseInsensitiveContains(searchText)
                    }
                }
                return filtered.isEmpty ? nil : (label, filtered)
            }
        }()

        let todayGroup = filteredGroups.first(where: { $0.0 == "Today" })
        let yesterdayGroup = filteredGroups.first(where: { $0.0 == "Yesterday" })
        let previousGroups = filteredGroups.filter { $0.0 != "Today" && $0.0 != "Yesterday" }

        return ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                topAppBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Welcome
                        welcomeHeader
                            .padding(.horizontal, 32)
                            .padding(.bottom, 12)

                        // Hero (setup / activation)
                        if !companionManager.allPermissionsGranted || !companionManager.isSparkleCursorEnabled {
                            heroCard
                                .padding(.horizontal, 32)
                                .padding(.bottom, 24)
                        }

                        // Bento stats
                        bentoStatsGrid
                            .padding(.horizontal, 32)
                            .padding(.bottom, 48)

                        // Today
                        if let todayConversations = todayGroup?.1, !todayConversations.isEmpty {
                            sectionHeader("Today", color: themeSecondary)
                                .padding(.horizontal, 32)
                                .padding(.bottom, 24)

                            LazyVGrid(
                                columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)],
                                spacing: 24
                            ) {
                                ForEach(todayConversations) { conversation in
                                    todayConversationCard(conversation)
                                }
                            }
                            .padding(.horizontal, 32)
                            .padding(.bottom, 48)
                        }

                        // Yesterday
                        if let yesterdayConversations = yesterdayGroup?.1, !yesterdayConversations.isEmpty {
                            sectionHeader("Yesterday", color: themeOnSurfaceVariant)
                                .padding(.horizontal, 32)
                                .padding(.bottom, 16)

                            VStack(spacing: 4) {
                                ForEach(yesterdayConversations) { conversation in
                                    yesterdayConversationRow(conversation)
                                }
                            }
                            .padding(.horizontal, 32)
                            .padding(.bottom, 48)
                        }

                        // Previous
                        if !previousGroups.isEmpty {
                            let allPreviousConversations = previousGroups.flatMap { $0.1 }
                            sectionHeader("Previous Sessions", color: themeOnSurfaceVariant.opacity(0.5))
                                .padding(.horizontal, 32)
                                .padding(.bottom, 24)

                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: 3),
                                spacing: 24
                            ) {
                                ForEach(allPreviousConversations) { conversation in
                                    previousSessionCard(conversation)
                                }
                            }
                            .padding(.horizontal, 32)
                            .padding(.bottom, 48)
                        }

                        // Empty state
                        if filteredGroups.isEmpty {
                            emptyStateView
                                .padding(.top, 24)
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
            .background(themeSurface)

            // Floating focus dock
            focusDock
                .padding(.bottom, 32)
        }
    }

    // MARK: - Top App Bar

    @State private var isRefreshing = false

    private var topAppBar: some View {
        HStack {
            if isSidebarCollapsed {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isSidebarCollapsed = false }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(themeOnSurfaceVariant)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .nativeTooltip("Expand sidebar")
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }

            Spacer()

            HStack(spacing: 16) {
                Button {
                    withAnimation(.easeInOut(duration: 0.5)) { isRefreshing = true }
                    conversationStore.reload()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation { isRefreshing = false }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(themeOnSurfaceVariant)
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(.easeInOut(duration: 0.5), value: isRefreshing)
                }
                .buttonStyle(.plain)
                .nativeTooltip("Refresh")
                .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }

                Image(systemName: "bell")
                    .font(.system(size: 14))
                    .foregroundColor(themeOnSurfaceVariant)
                Image(systemName: "text.book.closed")
                    .font(.system(size: 14))
                    .foregroundColor(themeOnSurfaceVariant)

                if let photo = profilePhotoImage {
                    Image(nsImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(themePrimary)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(userInitialLetterForToolbar)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        )
                }
            }
        }
        .padding(.horizontal, 32)
        .frame(height: 52)
        .background(themeSurface.opacity(0.8))
        .background(.ultraThinMaterial)
    }

    // MARK: - Welcome Header

    private var welcomeHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Welcome back, \(userDisplayName)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(themeOnSurface)
                .tracking(-0.5)
            Text("Your next AI win is queued up. Keep the momentum and make today count.")
                .font(.system(size: 16))
                .foregroundColor(themeOnSurfaceVariant.opacity(0.7))
        }
        .padding(.top, 32)
    }

    // MARK: - Bento Stats Grid

    private var bentoStatsGrid: some View {
        HStack(alignment: .top, spacing: 24) {
            // Left card — trajectory
            trajectoryCard
            // Right card — streak
            streakCard
                .frame(minWidth: 200, maxWidth: 260)
        }
        .frame(minHeight: 240)
    }

    private var trajectoryCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [themeOnSurface, Color(hex: "#3d4a47")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: themeOnSurface.opacity(0.12), radius: 24, y: 12)

            // Abstract glow circle (decorative background element)
        Circle()
            .fill(Color.white.opacity(0.04))
            .frame(width: 260, height: 260)
            .blur(radius: 60)
            .offset(x: 180, y: -60)

            VStack(alignment: .leading, spacing: 0) {
                Text("STATS")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .tracking(2)
                    .padding(.bottom, 8)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(aiToolsLearnedCount)")
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .tracking(-2)
                    Text("AI tools learned")
                        .font(.system(size: 18, weight: .light, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer()

                HStack(spacing: 32) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SESSIONS")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(totalSessionsCount)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("total")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 1, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("TOTAL HOURS")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                        Text(totalHoursStudyingLabel)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 1, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("MODEL")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                        Text(companionManager.selectedModel == "claude-opus-4-6" ? "Opus 4.6" : "Sonnet 4.6")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var streakCard: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(themeSurfaceContainerHigh, lineWidth: 8)
                    .frame(width: 116, height: 116)

                Circle()
                    .trim(from: 0, to: streakProgress)
                    .stroke(
                        LinearGradient(
                            colors: [themeTertiary, themeTertiaryContainer],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 116, height: 116)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(consecutiveDayStreak)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(themeTertiary)
                    Text("DAYS")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(themeOnSurfaceVariant)
                }
            }
            .padding(.bottom, 12)

            Text("Persistence Streak")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(themeOnSurface)

            Text("Keep the momentum going.")
                .font(.system(size: 12))
                .foregroundColor(themeOnSurfaceVariant)
                .padding(.top, 2)

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(themeSurfaceContainerLowest)
                .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(themeOutlineVariant.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .tracking(2)
            VStack { Divider().background(themeOutlineVariant.opacity(0.2)) }
        }
    }

    // MARK: - Today Conversation Card

    private func enterEditMode(for conversation: Conversation) {
        editingTitle = conversation.displayTitle
        editingSummary = conversation.summary.isEmpty
            ? (conversation.exchanges.first?.userTranscript ?? "")
            : conversation.summary
        editingToolType = conversation.resolvedToolType
        editingCardId = conversation.id
    }

    private func saveEditingCard() {
        guard let cardId = editingCardId else { return }
        let trimmedTitle = editingTitle.trimmingCharacters(in: .whitespaces)
        let trimmedSummary = editingSummary.trimmingCharacters(in: .whitespaces)
        conversationStore.updateConversation(
            cardId,
            title: trimmedTitle.isEmpty ? "Untitled" : trimmedTitle,
            summary: trimmedSummary,
            toolType: editingToolType
        )
        editingCardId = nil
    }

    private func todayConversationCard(_ conversation: Conversation) -> some View {
        let isHovered = hoveredCardId == conversation.id
        let isEditing = editingCardId == conversation.id
        let conversationIcon = iconForConversation(conversation)
        let conversationColor = colorForConversation(conversation)
        let progress = progressForConversation(conversation)
        let progressPercent = Int(progress * 100)

        return VStack(alignment: .leading, spacing: 0) {
            // Top row: icon + time/edit controls
            HStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 48, height: 48)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
                    .overlay(
                        Image(systemName: conversationIcon)
                            .font(.system(size: 18))
                            .foregroundColor(conversationColor)
                    )
                    .scaleEffect(isHovered && !isEditing ? 1.1 : 1.0)
                    .animation(.easeOut(duration: 0.2), value: isHovered)

                Spacer()

                if isEditing {
                    Button { saveEditingCard() } label: {
                        Text("Done")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(themePrimary))
                    }
                    .buttonStyle(.plain)
                    .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                } else {
                    HStack(spacing: 6) {
                        if isHovered {
                            sessionHoverButton(icon: "pencil", tooltip: "Edit") {
                                enterEditMode(for: conversation)
                            }
                            sessionHoverButton(icon: "archivebox", tooltip: "Archive") {
                                conversationStore.archiveConversation(conversation.id)
                            }
                            sessionHoverButton(icon: "trash", tooltip: "Delete", isDestructive: true) {
                                conversationStore.deleteConversation(conversation.id)
                            }
                        }

                        Text(timeLabel(for: conversation.updatedAt))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(themeOnSurface.opacity(0.4))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(themeOnSurface.opacity(0.05))
                            )
                    }
                    .animation(.easeOut(duration: 0.15), value: isHovered)
                }
            }
            .padding(.bottom, isEditing ? 16 : 32)

            // Title
            if isEditing {
                TextField("Session title", text: $editingTitle, onCommit: { saveEditingCard() })
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(themeOnSurface)
                    .padding(.bottom, 8)
            } else {
                Text(conversation.displayTitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(themeOnSurface)
                    .lineLimit(2)
            }

            // Tool type picker (edit mode only)
            if isEditing {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ConversationToolType.allCases, id: \.self) { toolType in
                            let isSelectedToolType = editingToolType == toolType
                            Button {
                                editingToolType = toolType
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: toolType.iconName)
                                        .font(.system(size: 10))
                                    Text(toolType.displayName)
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(isSelectedToolType ? .white : themeOnSurfaceVariant)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule().fill(
                                        isSelectedToolType
                                            ? (toolTypeColors[toolType] ?? neutralGray500)
                                            : themeOnSurface.opacity(0.06)
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                            .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                        }
                    }
                }
            }

            if !isEditing {
                Spacer(minLength: 24)

                HStack(spacing: 8) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(themeSurfaceContainerHigh)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(conversationColor)
                                .frame(width: geometry.size.width * progress)
                        }
                    }
                    .frame(height: 6)

                    Text("\(progressPercent)%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(themeOnSurfaceVariant)
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isEditing ? themeSurfaceContainerLowest : (isHovered ? themeSurfaceContainerLowest : themeSurfaceContainerLow))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    isEditing ? themePrimary.opacity(0.4) : (isHovered ? themeOutlineVariant.opacity(0.3) : Color.clear),
                    lineWidth: isEditing ? 1.5 : 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing {
                selectedConversationId = conversation.id
            }
        }
        .onHover { hovering in
            if !isEditing {
                hoveredCardId = hovering ? conversation.id : nil
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .contextMenu {
            Button("Edit") { enterEditMode(for: conversation) }
            Divider()
            Menu("Move to Space") {
                Button("None") { conversationStore.moveConversation(conversation.id, toSpace: nil) }
                ForEach(conversationStore.spaces) { space in
                    Button(space.name) { conversationStore.moveConversation(conversation.id, toSpace: space.id) }
                }
            }
            Divider()
            Button("Archive") { conversationStore.archiveConversation(conversation.id) }
            Button("Delete", role: .destructive) { conversationStore.deleteConversation(conversation.id) }
        }
    }

    // MARK: - Yesterday Conversation Row

    @State private var hoveredYesterdayRowId: UUID?

    private func yesterdayConversationRow(_ conversation: Conversation) -> some View {
        let isHovered = hoveredYesterdayRowId == conversation.id
        let conversationIcon = iconForConversation(conversation)
        let conversationColor = colorForConversation(conversation)
        let exchangeCount = conversation.exchanges.count

        return HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(conversationColor.opacity(0.1))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: conversationIcon)
                        .font(.system(size: 16))
                        .foregroundColor(conversationColor)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.displayTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(themeOnSurface)
                    .lineLimit(1)
                Text(conversationSubtitle(conversation))
                    .font(.system(size: 12))
                    .foregroundColor(themeOnSurfaceVariant)
                    .lineLimit(1)
            }

            Spacer()

            if isHovered {
                HStack(spacing: 4) {
                    sessionHoverButton(icon: "archivebox", tooltip: "Archive") {
                        conversationStore.archiveConversation(conversation.id)
                    }
                    sessionHoverButton(icon: "trash", tooltip: "Delete", isDestructive: true) {
                        conversationStore.deleteConversation(conversation.id)
                    }
                }
                .transition(.opacity)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("EXCHANGES")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(themeOnSurfaceVariant.opacity(0.5))
                    Text("\(exchangeCount)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(themeOnSurface)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(themeOnSurfaceVariant)
                .opacity(isHovered ? 1 : 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isHovered ? themeSurfaceContainerLow : Color.clear)
        )
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .contentShape(Rectangle())
        .onTapGesture { selectedConversationId = conversation.id }
        .onHover { hovering in
            hoveredYesterdayRowId = hovering ? conversation.id : nil
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .contextMenu {
            Menu("Move to Space") {
                Button("None") { conversationStore.moveConversation(conversation.id, toSpace: nil) }
                ForEach(conversationStore.spaces) { space in
                    Button(space.name) { conversationStore.moveConversation(conversation.id, toSpace: space.id) }
                }
            }
            Divider()
            Button("Archive") { conversationStore.archiveConversation(conversation.id) }
            Button("Delete", role: .destructive) { conversationStore.deleteConversation(conversation.id) }
        }
    }

    // MARK: - Previous Session Card

    @State private var hoveredPreviousCardId: UUID?

    private func previousSessionCard(_ conversation: Conversation) -> some View {
        let isHovered = hoveredPreviousCardId == conversation.id
        let gradientColors = gradientForConversation(conversation)

        return ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            LinearGradient(
                colors: [Color.black.opacity(0.6), Color.clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(shortDateLabel(conversation.createdAt))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                Text(conversation.displayTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
            .padding(24)

            if isHovered {
                HStack(spacing: 4) {
                    sessionHoverButton(icon: "archivebox", tooltip: "Archive", lightStyle: true) {
                        conversationStore.archiveConversation(conversation.id)
                    }
                    sessionHoverButton(icon: "trash", tooltip: "Delete", isDestructive: true, lightStyle: true) {
                        conversationStore.deleteConversation(conversation.id)
                    }
                }
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(12)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .opacity(isHovered ? 1.0 : 0.85)
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .contentShape(Rectangle())
        .onTapGesture { selectedConversationId = conversation.id }
        .onHover { hovering in
            hoveredPreviousCardId = hovering ? conversation.id : nil
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .contextMenu {
            Menu("Move to Space") {
                Button("None") { conversationStore.moveConversation(conversation.id, toSpace: nil) }
                ForEach(conversationStore.spaces) { space in
                    Button(space.name) { conversationStore.moveConversation(conversation.id, toSpace: space.id) }
                }
            }
            Divider()
            Button("Archive") { conversationStore.archiveConversation(conversation.id) }
            Button("Delete", role: .destructive) { conversationStore.deleteConversation(conversation.id) }
        }
    }

    // MARK: - Focus Dock

    private var focusDock: some View {
        HStack(spacing: 0) {
            Button {
                conversationStore.endCurrentConversation()
                let newConversationId = conversationStore.startNewConversation()
                selectedConversationId = newConversationId
                if !companionManager.isSparkleCursorEnabled {
                    companionManager.setSparkleCursorEnabled(true)
                }
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(themePrimary)
                            .frame(width: 40, height: 40)
                            .shadow(color: themePrimary.opacity(0.3), radius: 8, y: 2)
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text("New Session")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(themePrimary)
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .padding(.trailing, 16)

            Rectangle()
                .fill(themeOutlineVariant.opacity(0.3))
                .frame(width: 1, height: 24)
                .padding(.horizontal, 8)

            HStack(spacing: 4) {
                dockIconButton("mic")
                dockIconButton("doc.text")
                dockIconButton("link")
            }
            .padding(.leading, 8)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.12), radius: 24, y: 8)
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private func dockIconButton(_ iconName: String) -> some View {
        Button { } label: {
            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundColor(themeOnSurfaceVariant)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    // MARK: - Hero Card

    @ViewBuilder
    private var heroCard: some View {
        if !companionManager.allPermissionsGranted {
            heroCardContainer {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        SparkleShape()
                            .fill(themePrimary)
                            .frame(width: 14, height: 14)
                        Text("Setup Vibecademy")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(themeOnSurface)
                    }
                    Text("Grant the required permissions to get started with Sparkle, your AI tutor.")
                        .font(.system(size: 13))
                        .foregroundColor(themeOnSurfaceVariant)
                        .lineSpacing(2)
                }
            }
        } else if !companionManager.isSparkleCursorEnabled {
            heroCardContainer {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            SparkleShape()
                                .fill(themePrimary)
                                .frame(width: 14, height: 14)
                            Text("Meet Sparkle")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(themeOnSurface)
                        }
                        Text("Your AI tutor that sees your screen and teaches you how to use AI tools — step by step, conversationally.")
                            .font(.system(size: 13))
                            .foregroundColor(themeOnSurfaceVariant)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button {
                        companionManager.setSparkleCursorEnabled(true)
                    } label: {
                        Text("Activate")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(themePrimary))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }
            }
        }
    }

    private func heroCardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(themeSurfaceContainerLowest)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(themeOutlineVariant.opacity(0.2), lineWidth: 1)
            )
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            SparkleShape()
                .fill(neutralGray400.opacity(0.3))
                .frame(width: 32, height: 32)
            Text("No conversations yet")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundColor(neutralGray500)
            Text("Hold  Control + Option  to talk to Sparkle")
                .font(.system(size: 13))
                .foregroundColor(neutralGray400)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Computed Stats

    private static let recognizedAITools: [(name: String, keywords: [String])] = [
        ("Cursor", ["cursor"]),
        ("Replit", ["replit"]),
        ("Claude", ["claude"]),
        ("Claude Code", ["claude code"]),
        ("ChatGPT", ["chatgpt", "chat gpt"]),
        ("Codex", ["codex"]),
        ("GitHub Copilot", ["copilot", "github copilot"]),
        ("v0", ["v0", "v zero", "vercel v0"]),
        ("Bolt", ["bolt.new", "bolt"]),
        ("Windsurf", ["windsurf"]),
        ("Lovable", ["lovable"]),
        ("Gemini", ["gemini"]),
        ("Midjourney", ["midjourney"]),
        ("Perplexity", ["perplexity"]),
    ]

    private var aiToolsLearnedCount: Int {
        let conversations = conversationStore.conversations
        if conversations.isEmpty { return 0 }

        let searchableTextPerConversation = conversations.map { conversation in
            let exchangeText = conversation.exchanges
                .map { "\($0.userTranscript) \($0.assistantResponse)" }
                .joined(separator: " ")
            return "\(conversation.title) \(exchangeText)".lowercased()
        }

        let recognizedToolsMatchedCount = Self.recognizedAITools.filter { tool in
            searchableTextPerConversation.contains { text in
                tool.keywords.contains { keyword in text.contains(keyword) }
            }
        }.count

        let conversationsWithNoRecognizedToolCount = searchableTextPerConversation.filter { text in
            !Self.recognizedAITools.contains { tool in
                tool.keywords.contains { keyword in text.contains(keyword) }
            }
        }.count

        return recognizedToolsMatchedCount + conversationsWithNoRecognizedToolCount
    }

    private var totalHoursStudyingLabel: String {
        let totalSeconds = conversationStore.conversations.reduce(0.0) { total, conversation in
            total + conversation.updatedAt.timeIntervalSince(conversation.createdAt)
        }
        let hours = totalSeconds / 3600.0
        if hours < 0.1 {
            let minutes = Int(totalSeconds / 60.0)
            return "\(minutes)m"
        }
        if hours < 10 {
            return String(format: "%.1fh", hours)
        }
        return "\(Int(hours))h"
    }

    private var totalSessionsCount: Int {
        conversationStore.conversations.count
    }

    private var consecutiveDayStreak: Int {
        let calendar = Calendar.current
        let uniqueConversationDays = Set(
            conversationStore.conversations.map { calendar.startOfDay(for: $0.createdAt) }
        ).sorted(by: >)

        guard !uniqueConversationDays.isEmpty else { return 0 }

        var streak = 0
        var expectedDate = calendar.startOfDay(for: Date())

        for date in uniqueConversationDays {
            if date == expectedDate {
                streak += 1
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: expectedDate) else { break }
                expectedDate = previousDay
            } else if date < expectedDate {
                break
            }
        }
        return streak
    }

    private var streakProgress: Double {
        min(Double(consecutiveDayStreak) / 7.0, 1.0)
    }

    // MARK: - Helpers

    private func progressForConversation(_ conversation: Conversation) -> Double {
        min(Double(conversation.exchanges.count) / 8.0, 1.0)
    }

    private func conversationSubtitle(_ conversation: Conversation) -> String {
        if !conversation.summary.isEmpty { return conversation.summary }
        if let firstExchange = conversation.exchanges.first {
            return firstExchange.userTranscript
        }
        return "No content yet"
    }

    private func timeLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func shortDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date).uppercased()
    }

    private func gradientForConversation(_ conversation: Conversation) -> [Color] {
        let gradients: [[Color]] = [
            [Color(hex: "#2d3432"), Color(hex: "#4a5552")],
            [Color(hex: "#3d3c3c"), Color(hex: "#5f5e5e")],
            [Color(hex: "#3a3530"), Color(hex: "#5a554f")],
            [Color(hex: "#2f3530"), Color(hex: "#4d5349")],
            [Color(hex: "#383838"), Color(hex: "#585858")],
        ]
        let index = abs(conversation.id.hashValue) % gradients.count
        return gradients[index]
    }
}

// MARK: - Profile Detail

private struct ProfileDetailView: View {
    @Binding var userDisplayName: String
    @ObservedObject var companionManager: CompanionManager
    @ObservedObject var conversationStore: ConversationStore

    @State private var draftDisplayName: String = ""
    @State private var draftEmail: String = ""
    @State private var showingSaveConfirmation = false
    @State private var isPickingPhoto = false
    @State private var showingDeleteAllConfirmation = false
    @AppStorage("userEmail") private var persistedEmail = ""
    @AppStorage("profilePhotoPath") private var profilePhotoRelativePath = ""

    private static let profilePhotosDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("Vibecademy/ProfilePhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    private var profilePhotoFullURL: URL? {
        guard !profilePhotoRelativePath.isEmpty else { return nil }
        return Self.profilePhotosDirectory.appendingPathComponent(profilePhotoRelativePath)
    }

    private var profilePhotoImage: NSImage? {
        guard let url = profilePhotoFullURL else { return nil }
        return NSImage(contentsOf: url)
    }

    private var profileInitialLetter: String {
        let name = draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = name.first {
            return String(first).uppercased()
        }
        return "?"
    }

    private var totalExchangeCount: Int {
        conversationStore.conversations.reduce(0) { $0 + $1.exchanges.count }
    }

    private var memberSinceLabel: String {
        guard let oldest = conversationStore.conversations.map({ $0.createdAt }).min() else {
            return "Today"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: oldest)
    }

    private var hasUnsavedChanges: Bool {
        draftDisplayName != userDisplayName || draftEmail != persistedEmail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Profile")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(themeOnSurface)
                Spacer()

                if showingSaveConfirmation {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Saved")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .frame(height: 52)
            .padding(.horizontal, 32)
            .background(themeSurface.opacity(0.8))
            .background(.ultraThinMaterial)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // MARK: Avatar + Photo

                    profileAvatarSection
                        .padding(.top, 32)
                        .padding(.bottom, 32)

                    // MARK: Personal Info

                    profileSectionHeader("Personal Information")

                    VStack(alignment: .leading, spacing: 20) {
                        profileTextField(
                            label: "Display name",
                            placeholder: "Your name",
                            text: $draftDisplayName,
                            hint: "Shown in the sidebar, welcome message, and toolbar."
                        )

                        profileTextField(
                            label: "Email",
                            placeholder: "you@example.com",
                            text: $draftEmail,
                            hint: "Optional. Used for account recovery and notifications."
                        )
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 12)

                    saveButton
                        .padding(.horizontal, 32)
                        .padding(.bottom, 40)

                    Divider().padding(.horizontal, 32).padding(.bottom, 24)

                    // MARK: Preferences

                    profileSectionHeader("Preferences")

                    preferredModelPicker
                        .padding(.horizontal, 32)
                        .padding(.bottom, 40)

                    Divider().padding(.horizontal, 32).padding(.bottom, 24)

                    // MARK: Stats

                    profileSectionHeader("Your Activity")

                    statsGrid
                        .padding(.horizontal, 32)
                        .padding(.bottom, 40)

                    Divider().padding(.horizontal, 32).padding(.bottom, 24)

                    // MARK: Keyboard Shortcuts

                    profileSectionHeader("Keyboard Shortcuts")

                    shortcutsReference
                        .padding(.horizontal, 32)
                        .padding(.bottom, 40)

                    Divider().padding(.horizontal, 32).padding(.bottom, 24)

                    // MARK: Danger Zone

                    profileSectionHeader("Danger Zone")

                    dangerZone
                        .padding(.horizontal, 32)
                        .padding(.bottom, 60)
                }
            }
        }
        .background(themeSurface)
        .onAppear {
            draftDisplayName = userDisplayName
            draftEmail = persistedEmail
        }
    }

    // MARK: - Avatar Section

    private var profileAvatarSection: some View {
        HStack {
            Spacer()
            VStack(spacing: 12) {
                ZStack {
                    if let photo = profilePhotoImage {
                        Image(nsImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(themePrimary)
                            .frame(width: 96, height: 96)
                        Text(profileInitialLetter)
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        pickProfilePhoto()
                    } label: {
                        Text(profilePhotoImage == nil ? "Upload Photo" : "Change Photo")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(themeTertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(themeTertiary.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }

                    if profilePhotoImage != nil {
                        Button {
                            removeProfilePhoto()
                        } label: {
                            Text("Remove")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(hex: "#dc2626"))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(hex: "#dc2626").opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        HStack {
            Spacer()
            Button {
                saveProfile()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .medium))
                    Text("Save Changes")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(hasUnsavedChanges ? themeTertiary : neutralGray400)
                )
            }
            .buttonStyle(.plain)
            .disabled(!hasUnsavedChanges)
            .onHover { h in
                if hasUnsavedChanges {
                    if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
            Spacer()
        }
    }

    // MARK: - Preferred Model Picker

    private var preferredModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default AI model")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(themeOnSurfaceVariant)

            HStack(spacing: 12) {
                modelPickerButton(
                    label: "Sonnet 4.6",
                    subtitle: "Fast & capable",
                    modelId: "claude-sonnet-4-6",
                    icon: "hare"
                )
                modelPickerButton(
                    label: "Opus 4.6",
                    subtitle: "Most intelligent",
                    modelId: "claude-opus-4-6",
                    icon: "brain.head.profile"
                )
            }

            Text("Controls which model Sparkle uses for voice responses.")
                .font(.system(size: 12))
                .foregroundColor(themeOnSurfaceVariant.opacity(0.8))
        }
    }

    private func modelPickerButton(label: String, subtitle: String, modelId: String, icon: String) -> some View {
        let isSelected = companionManager.selectedModel == modelId
        return Button {
            companionManager.setSelectedModel(modelId)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? themeTertiary : neutralGray500)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? themeOnSurface : neutralGray600)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(themeOnSurfaceVariant.opacity(0.7))
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(themeTertiary)
                        .font(.system(size: 16))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? themeTertiary.opacity(0.08) : themeSurfaceContainerHigh)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? themeTertiary.opacity(0.3) : Color.clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        let sessionCount = conversationStore.conversations.count
        let spaceCount = conversationStore.spaces.count

        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ],
            spacing: 16
        ) {
            statCard(value: "\(sessionCount)", label: "Sessions", icon: "bubble.left.and.bubble.right")
            statCard(value: "\(totalExchangeCount)", label: "Exchanges", icon: "text.bubble")
            statCard(value: "\(spaceCount)", label: "Spaces", icon: "folder")
            statCard(value: memberSinceLabel, label: "Member since", icon: "calendar")
            statCard(
                value: companionManager.selectedModel == "claude-opus-4-6" ? "Opus 4.6" : "Sonnet 4.6",
                label: "Current model",
                icon: "cpu"
            )
            statCard(
                value: companionManager.isSparkleCursorEnabled ? "Active" : "Off",
                label: "Sparkle status",
                icon: "sparkle"
            )
        }
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(themeTertiary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(themeOnSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(themeOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(themeSurfaceContainerHigh)
        )
    }

    // MARK: - Keyboard Shortcuts

    private var shortcutsReference: some View {
        VStack(spacing: 0) {
            shortcutRow(keys: ["⌃", "⌥"], description: "Push-to-talk (hold)", isFirst: true)
            shortcutRow(keys: ["⌘", "K"], description: "Search sessions")
            shortcutRow(keys: ["⌘", ","], description: "Open Settings")
            shortcutRow(keys: ["⌘", "Q"], description: "Quit Vibecademy", isLast: true)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(themeOutlineVariant.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func shortcutRow(keys: [String], description: String, isFirst: Bool = false, isLast: Bool = false) -> some View {
        HStack {
            Text(description)
                .font(.system(size: 13))
                .foregroundColor(themeOnSurface)
            Spacer()
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(neutralGray600)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(themeSurfaceContainerHigh)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(themeOutlineVariant.opacity(0.3), lineWidth: 0.5)
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(themeSurfaceContainerLowest)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().opacity(0.3)
            }
        }
    }

    // MARK: - Danger Zone

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    showingDeleteAllConfirmation = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                        Text("Delete All Conversations")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(Color(hex: "#dc2626"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hex: "#dc2626").opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(hex: "#dc2626").opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                .alert("Delete all conversations?", isPresented: $showingDeleteAllConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete All", role: .destructive) {
                        deleteAllConversations()
                    }
                } message: {
                    Text("This will permanently remove all \(conversationStore.conversations.count) conversations. This cannot be undone.")
                }

                Button {
                    resetProfileToDefaults()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 13))
                        Text("Reset Profile")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(Color(hex: "#dc2626"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hex: "#dc2626").opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(hex: "#dc2626").opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
            }

            Text("These actions are permanent and cannot be reversed.")
                .font(.system(size: 12))
                .foregroundColor(themeOnSurfaceVariant.opacity(0.6))
        }
    }

    // MARK: - Helpers

    private func profileSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundColor(themeOnSurface)
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
    }

    private func profileTextField(label: String, placeholder: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(themeOnSurfaceVariant)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(themeSurfaceContainerHigh)
                )
            Text(hint)
                .font(.system(size: 11))
                .foregroundColor(themeOnSurfaceVariant.opacity(0.7))
        }
    }

    // MARK: - Actions

    private func saveProfile() {
        let trimmedName = draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            userDisplayName = trimmedName
            draftDisplayName = trimmedName
        }
        persistedEmail = draftEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        draftEmail = persistedEmail

        withAnimation(.easeInOut(duration: 0.3)) { showingSaveConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.3)) { showingSaveConfirmation = false }
        }
    }

    private func pickProfilePhoto() {
        let panel = NSOpenPanel()
        panel.title = "Choose a profile photo"
        panel.allowedContentTypes = [.jpeg, .png, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        let fileName = "profile_\(UUID().uuidString).\(sourceURL.pathExtension)"
        let destinationURL = Self.profilePhotosDirectory.appendingPathComponent(fileName)

        // Remove the old photo file if one exists
        if let oldURL = profilePhotoFullURL {
            try? FileManager.default.removeItem(at: oldURL)
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            profilePhotoRelativePath = fileName
        } catch {
            print("⚠️ ProfileDetailView: failed to copy profile photo: \(error)")
        }
    }

    private func removeProfilePhoto() {
        if let url = profilePhotoFullURL {
            try? FileManager.default.removeItem(at: url)
        }
        profilePhotoRelativePath = ""
    }

    private func deleteAllConversations() {
        let allIds = conversationStore.conversations.map { $0.id }
        for conversationId in allIds {
            conversationStore.deleteConversation(conversationId)
        }
    }

    private func resetProfileToDefaults() {
        userDisplayName = "Dante"
        draftDisplayName = "Dante"
        persistedEmail = ""
        draftEmail = ""
        removeProfilePhoto()
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
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "house")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(themeOnSurfaceVariant)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(themeSurfaceContainerLowest)
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }

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
                    Text(conversation.displayTitle)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(themeOnSurface)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 12)

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
        .background(themeSurface)
    }

    private func tagBadge(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(themeOnSurfaceVariant)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(themeSurfaceContainerLowest)
        )
    }

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 20) {
            if conversation.summary.isEmpty && conversation.exchanges.isEmpty {
                Text("No content yet.")
                    .font(.system(size: 14))
                    .foregroundColor(themeOnSurfaceVariant)
                    .padding(.horizontal, 28)
            } else if !conversation.summary.isEmpty {
                Text(conversation.summary)
                    .font(.system(size: 15))
                    .foregroundColor(themeOnSurface)
                    .lineSpacing(4)
                    .padding(.horizontal, 28)
            } else {
                ForEach(conversation.exchanges) { exchange in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("# \(exchange.userTranscript)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(themeOnSurface)
                        Text(exchange.assistantResponse)
                            .font(.system(size: 14))
                            .foregroundColor(themeOnSurface.opacity(0.85))
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
                .foregroundColor(themeOnSurfaceVariant)
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
                                .foregroundColor(themeOnSurfaceVariant)
                            Text(exchange.userTranscript)
                                .font(.system(size: 14))
                                .foregroundColor(themeOnSurface)
                                .lineSpacing(3)
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle().fill(themePrimary)
                            SparkleShape()
                                .fill(.white)
                                .frame(width: 14, height: 14)
                        }
                        .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sparkle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(themeOnSurfaceVariant)
                            Text(exchange.assistantResponse)
                                .font(.system(size: 14))
                                .foregroundColor(themeOnSurface)
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
        if Calendar.current.isDateInToday(conversation.createdAt) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(conversation.createdAt) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
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
