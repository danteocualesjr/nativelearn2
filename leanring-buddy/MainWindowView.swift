//
//  MainWindowView.swift
//  leanring-buddy
//
//  Primary desktop window. Left sidebar with logo, search, navigation,
//  and spaces. Main panel shows a bento stats dashboard, conversation
//  sessions tiered by date, and a floating focus dock.
//

import SwiftUI

// MARK: - Theme Colors (Material Design 3 — Vibe Academy light palette)

private let themePrimary = Color(hex: "#b72301")
private let themePrimaryContainer = Color(hex: "#ff5733")
private let themeSecondary = Color(hex: "#904d00")
private let themeSecondaryContainer = Color(hex: "#fd8b00")
private let themeTertiary = Color(hex: "#765b00")
private let themeTertiaryContainer = Color(hex: "#d4a500")
private let themeSurface = Color(hex: "#f9f9f9")
private let themeOnSurface = Color(hex: "#1b1b1b")
private let themeSurfaceContainer = Color(hex: "#eeeeee")
private let themeSurfaceContainerLow = Color(hex: "#f3f3f3")
private let themeSurfaceContainerHigh = Color(hex: "#e8e8e8")
private let themeSurfaceContainerLowest = Color.white
private let themeOnSurfaceVariant = Color(hex: "#5b403a")
private let themeOutlineVariant = Color(hex: "#e4beb6")

private let sidebarBg = Color(hex: "#f5f5f5")
private let sidebarHoverBg = Color(hex: "#e5e5e5")
private let neutralGray400 = Color(hex: "#a3a3a3")
private let neutralGray500 = Color(hex: "#737373")
private let neutralGray600 = Color(hex: "#525252")

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

    enum SidebarItem: Hashable {
        case home
        case chat
        case space(UUID)
    }

    private var sidebarWidth: CGFloat { isSidebarCollapsed ? 60 : 256 }

    var body: some View {
        HStack(spacing: 0) {
            sidebarView
                .frame(width: sidebarWidth)
                .clipped()
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(themeSurface)
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(alignment: isSidebarCollapsed ? .center : .leading, spacing: 0) {
            Spacer().frame(height: 52)

            // Logo + collapse toggle
            if isSidebarCollapsed {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isSidebarCollapsed = false }
                } label: {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(themePrimary)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text("V")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        )
                }
                .buttonStyle(.plain)
                .nativeTooltip("Expand sidebar")
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .padding(.bottom, 16)
            } else {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(themePrimary)
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
            }

            // Search
            if isSidebarCollapsed {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isSidebarCollapsed = false }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(neutralGray400)
                        .frame(width: 40, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(themeSurfaceContainerHigh)
                        )
                }
                .buttonStyle(.plain)
                .nativeTooltip("Search  ⌘K")
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .padding(.bottom, 16)
            } else {
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
            }

            // Nav items
            VStack(spacing: 2) {
                sidebarNavRow(item: .home, icon: "house.fill", label: "Home")
                sidebarNavRow(item: .chat, icon: "bubble.left.and.bubble.right", label: "Chat")
            }
            .padding(.horizontal, isSidebarCollapsed ? 4 : 8)

            // Spaces
            if isSidebarCollapsed {
                VStack(spacing: 2) {
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

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isSidebarCollapsed = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            isCreatingSpace = true
                        }
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 14))
                            .foregroundColor(neutralGray400.opacity(0.6))
                            .frame(width: 40, height: 36)
                    }
                    .buttonStyle(.plain)
                    .nativeTooltip("Add folder")
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 16)
            } else {
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
            }

            Spacer()

            // Bottom section
            sidebarBottom
        }
        .background(sidebarBg)
    }

    // MARK: - Sidebar Bottom

    private var sidebarBottom: some View {
        VStack(spacing: 2) {
            Divider().opacity(0.3).padding(.horizontal, isSidebarCollapsed ? 8 : 12)

            if isSidebarCollapsed {
                // Collapsed: icon-only buttons stacked vertically
                Button {
                    companionManager.setSparkleCursorEnabled(!companionManager.isSparkleCursorEnabled)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 14))
                            .foregroundColor(companionManager.isSparkleCursorEnabled ? themePrimary : neutralGray600)
                            .frame(width: 40, height: 36)
                        Circle()
                            .fill(sparkleStatusColor)
                            .frame(width: 6, height: 6)
                            .offset(x: -6, y: 6)
                    }
                }
                .buttonStyle(.plain)
                .nativeTooltip("Sparkle — \(sparkleStatusShortLabel)")
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }

                Image(systemName: "person.circle")
                    .font(.system(size: 14))
                    .foregroundColor(neutralGray600)
                    .frame(width: 40, height: 36)
                    .nativeTooltip("Profile — Dante")

                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(neutralGray600)
                        .frame(width: 40, height: 36)
                }
                .buttonStyle(.plain)
                .nativeTooltip("Settings")
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            } else {
                // Expanded: full rows
                Button {
                    companionManager.setSparkleCursorEnabled(!companionManager.isSparkleCursorEnabled)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 14))
                            .foregroundColor(companionManager.isSparkleCursorEnabled ? themePrimary : neutralGray600)
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

                HStack(spacing: 12) {
                    Image(systemName: "person.circle")
                        .font(.system(size: 14))
                        .foregroundColor(neutralGray600)
                    Text("Profile")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(neutralGray600)
                    Spacer()
                    Text("Dante")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(themePrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(themePrimary.opacity(0.1))
                        )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

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
        }
        .padding(.horizontal, isSidebarCollapsed ? 4 : 8)
        .padding(.bottom, 12)
    }

    // MARK: - Sidebar Helpers

    private func sidebarNavRow(item: SidebarItem, icon: String, label: String) -> some View {
        let isSelected = sidebarSelection == item
        let isHovered = hoveredSidebarItem == item
        let activeColor = Color(hex: "#c2410c")

        return Group {
            if isSidebarCollapsed {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? activeColor : neutralGray600)
                    .frame(width: 40, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? Color.white.opacity(0.5) : (isHovered ? sidebarHoverBg : Color.clear))
                    )
                    .nativeTooltip(label)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? activeColor : neutralGray600)
                    Text(label)
                        .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? activeColor : neutralGray600)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.5) : (isHovered ? sidebarHoverBg : Color.clear))
                )
            }
        }
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
        } else {
            dashboardView
        }
    }

    // MARK: - Dashboard (Main Content)

    private var dashboardView: some View {
        let spaceFilter: UUID? = {
            if case .space(let id) = sidebarSelection { return id }
            return nil
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

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [themePrimaryContainer, themePrimary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text("D")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    )
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
            Text("Welcome back, Dante")
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
                        colors: [themePrimary, themePrimaryContainer],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: themePrimary.opacity(0.2), radius: 24, y: 12)

            // Abstract glow circle (decorative background element)
            Circle()
                .fill(Color.white.opacity(0.08))
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
                            colors: [themePrimary, themePrimaryContainer],
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
                        .foregroundColor(themePrimary)
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
            [Color(hex: "#7c2d12"), Color(hex: "#ea580c")],
            [Color(hex: "#78350f"), Color(hex: "#d97706")],
            [Color(hex: "#422006"), Color(hex: "#a16207")],
            [Color(hex: "#991b1b"), Color(hex: "#dc2626")],
            [Color(hex: "#713f12"), Color(hex: "#ca8a04")],
        ]
        let index = abs(conversation.id.hashValue) % gradients.count
        return gradients[index]
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
