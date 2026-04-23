//
//  InsightsView.swift
//  leanring-buddy
//
//  Insights tab: KPI tiles, activity heatmap, tool breakdown, and streak
//  stats — all derived from the existing ConversationStore data.
//

import Charts
import SwiftUI

// MARK: - Theme (local copies matching MainWindowView)

private let insightsPrimary = Color(hex: "#0058bc")
private let insightsSurface = Color(hex: "#f9f9fe")
private let insightsSurfaceLowest = Color.white
private let insightsSurfaceContainerLow = Color(hex: "#f3f3f8")
private let insightsSurfaceContainerHigh = Color(hex: "#e8e8ed")
private let insightsOnSurface = Color(hex: "#1a1c1f")
private let insightsOnSurfaceVariant = Color(hex: "#414755")
private let insightsOutlineVariant = Color(hex: "#c1c6d7")
private let insightsNeutralGray400 = Color(hex: "#94a3b8")
private let insightsNeutralGray500 = Color(hex: "#64748b")

// MARK: - AI Tool Keywords
//
// Duplicated from `MainWindowView.recognizedAITools` so the Insights stats
// layer can be self-contained. When promoting this list to a shared module,
// both sites should read from the shared source.

private let insightsRecognizedAITools: [(name: String, keywords: [String])] = [
    ("Cursor", ["cursor"]),
    ("Replit", ["replit"]),
    ("Claude Code", ["claude code"]),
    ("Claude", ["claude"]),
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

// MARK: - Stats Model

/// Aggregated metrics derived from a slice of conversations.
///
/// Range-scoped metrics (`totalSessions`, `totalMinutes`, `sessionsPerDay`,
/// `toolBreakdown`) reflect only conversations whose `updatedAt` falls within
/// the selected range. Streak metrics always use the full history so the
/// user's longest streak is meaningful even when looking at a recent window.
struct InsightsStats {
    enum Range: String, CaseIterable, Identifiable {
        case week
        case month
        case all

        var id: String { rawValue }

        var label: String {
            switch self {
            case .week:  return "7 days"
            case .month: return "30 days"
            case .all:   return "All time"
            }
        }

        /// Number of days back the heatmap should cover for this range.
        var heatmapDays: Int {
            switch self {
            case .week:  return 28   // 4 weeks so the grid has shape even on short ranges
            case .month: return 35   // 5 weeks
            case .all:   return 182  // ~26 weeks
            }
        }
    }

    struct ToolUsage: Identifiable {
        let name: String
        let sessions: Int
        let minutes: Int
        var id: String { name }
    }

    let range: Range
    let sessionsPerDay: [Date: Int]
    let totalSessions: Int
    let totalMinutes: Int
    let currentStreak: Int
    let longestStreak: Int
    let toolBreakdown: [ToolUsage]

    init(conversations: [Conversation], range: Range, now: Date = Date()) {
        self.range = range

        let calendar = Calendar.current
        let active = conversations.filter { !$0.archived }

        let rangeStart: Date? = {
            switch range {
            case .week:  return calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))
            case .month: return calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))
            case .all:   return nil
            }
        }()

        let scoped: [Conversation] = {
            guard let rangeStart else { return active }
            return active.filter { $0.updatedAt >= rangeStart }
        }()

        var perDay: [Date: Int] = [:]
        var totalSeconds: Double = 0
        for conversation in scoped {
            let day = calendar.startOfDay(for: conversation.updatedAt)
            perDay[day, default: 0] += 1
            totalSeconds += max(0, conversation.updatedAt.timeIntervalSince(conversation.createdAt))
        }
        self.sessionsPerDay = perDay
        self.totalSessions = scoped.count
        self.totalMinutes = Int(totalSeconds / 60.0)

        let (current, longest) = Self.computeStreaks(from: active, now: now, calendar: calendar)
        self.currentStreak = current
        self.longestStreak = longest

        self.toolBreakdown = Self.computeToolBreakdown(from: scoped)
    }

    // MARK: Streaks

    private static func computeStreaks(
        from conversations: [Conversation],
        now: Date,
        calendar: Calendar
    ) -> (current: Int, longest: Int) {
        let uniqueDays = Set(conversations.map { calendar.startOfDay(for: $0.createdAt) })
            .sorted()

        guard !uniqueDays.isEmpty else { return (0, 0) }

        var longest = 1
        var run = 1
        for i in 1..<uniqueDays.count {
            let previous = uniqueDays[i - 1]
            let current = uniqueDays[i]
            if let next = calendar.date(byAdding: .day, value: 1, to: previous), next == current {
                run += 1
                longest = max(longest, run)
            } else {
                run = 1
            }
        }

        var current = 0
        let today = calendar.startOfDay(for: now)
        var expected = today
        let daysDescending = uniqueDays.reversed()

        var startedYesterday = false
        for day in daysDescending {
            if day == expected {
                current += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: expected) else { break }
                expected = previous
            } else if current == 0,
                      let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                      day == yesterday,
                      !startedYesterday {
                startedYesterday = true
                current = 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: yesterday) else { break }
                expected = previous
            } else if day < expected {
                break
            }
        }

        return (current, longest)
    }

    // MARK: Tool Breakdown

    private static func computeToolBreakdown(from conversations: [Conversation]) -> [ToolUsage] {
        guard !conversations.isEmpty else { return [] }

        var sessionsByTool: [String: Int] = [:]
        var minutesByTool: [String: Int] = [:]

        for conversation in conversations {
            let exchangeText = conversation.exchanges
                .map { "\($0.userTranscript) \($0.assistantResponse)" }
                .joined(separator: " ")
            let haystack = "\(conversation.title) \(exchangeText)".lowercased()
            let minutes = Int(max(0, conversation.updatedAt.timeIntervalSince(conversation.createdAt)) / 60.0)

            var matched = false
            for tool in insightsRecognizedAITools {
                if tool.keywords.contains(where: { haystack.contains($0) }) {
                    sessionsByTool[tool.name, default: 0] += 1
                    minutesByTool[tool.name, default: 0] += minutes
                    matched = true
                    break
                }
            }
            if !matched {
                sessionsByTool["Other", default: 0] += 1
                minutesByTool["Other", default: 0] += minutes
            }
        }

        return sessionsByTool
            .map { ToolUsage(name: $0.key, sessions: $0.value, minutes: minutesByTool[$0.key] ?? 0) }
            .sorted { lhs, rhs in
                if lhs.sessions != rhs.sessions { return lhs.sessions > rhs.sessions }
                return lhs.name < rhs.name
            }
    }
}

// MARK: - Insights View

struct InsightsView: View {
    @ObservedObject var conversationStore: ConversationStore
    @State private var selectedRange: InsightsStats.Range = .month

    private var stats: InsightsStats {
        InsightsStats(conversations: conversationStore.conversations, range: selectedRange)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            headerRow
            kpiTilesRow
            activityHeatmapCard
            breakdownAndStreaksRow
        }
        .padding(.horizontal, 32)
    }

    // MARK: Header + Range Picker

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Insights")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(insightsOnSurface)
                    .tracking(-0.5)
                Text("Your learning activity at a glance.")
                    .font(.system(size: 13))
                    .foregroundColor(insightsOnSurfaceVariant)
            }
            Spacer()
            rangePicker
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(InsightsStats.Range.allCases) { range in
                let isSelected = selectedRange == range
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedRange = range
                    }
                } label: {
                    Text(range.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isSelected ? .white : insightsOnSurfaceVariant)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(isSelected ? insightsPrimary : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        }
        .padding(3)
        .background(
            Capsule().fill(insightsSurfaceContainerHigh)
        )
    }

    // MARK: KPI Tiles

    private var kpiTilesRow: some View {
        let snapshot = stats
        return HStack(spacing: 16) {
            kpiTile(
                title: "SESSIONS",
                value: "\(snapshot.totalSessions)",
                subtitle: sessionsSubtitle(for: snapshot),
                iconName: "bubble.left.and.text.bubble.right"
            )
            kpiTile(
                title: "TIME LEARNING",
                value: formattedDuration(minutes: snapshot.totalMinutes),
                subtitle: "in the selected window",
                iconName: "clock"
            )
            kpiTile(
                title: "CURRENT STREAK",
                value: "\(snapshot.currentStreak)\(snapshot.currentStreak == 1 ? " day" : " days")",
                subtitle: snapshot.longestStreak > 0 ? "Longest: \(snapshot.longestStreak) days" : "Start today",
                iconName: "flame.fill"
            )
        }
    }

    private func kpiTile(title: String, value: String, subtitle: String, iconName: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(insightsNeutralGray400)
                    .tracking(1.5)
                Spacer()
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(insightsPrimary.opacity(0.7))
            }

            Text(value)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(insightsOnSurface)
                .tracking(-0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(insightsNeutralGray500)
                .lineLimit(1)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(insightsSurfaceLowest)
                .shadow(color: insightsOnSurface.opacity(0.04), radius: 8, y: 3)
        )
    }

    private func sessionsSubtitle(for stats: InsightsStats) -> String {
        switch stats.range {
        case .week:  return "in the last 7 days"
        case .month: return "in the last 30 days"
        case .all:   return "across all conversations"
        }
    }

    // MARK: Activity Heatmap

    private var activityHeatmapCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("ACTIVITY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(insightsPrimary)
                    .tracking(1.2)
                Spacer()
                heatmapLegend
            }
            activityHeatmapGrid
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(insightsSurfaceLowest)
                .shadow(color: insightsOnSurface.opacity(0.04), radius: 10, y: 4)
        )
    }

    private var heatmapLegend: some View {
        HStack(spacing: 6) {
            Text("Less")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(insightsNeutralGray400)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(heatmapColor(for: level))
                    .frame(width: 12, height: 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(insightsOutlineVariant.opacity(level == 0 ? 0.35 : 0), lineWidth: 1)
                    )
            }
            Text("More")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(insightsNeutralGray400)
        }
    }

    private var activityHeatmapGrid: some View {
        let snapshot = stats
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let totalDays = snapshot.range.heatmapDays
        let weekdayOfToday = calendar.component(.weekday, from: today) // 1 (Sun) ... 7 (Sat)
        let trailingBlanks = 7 - weekdayOfToday // cells after today to complete the final week
        let leadingOffset = totalDays + trailingBlanks
        let weekCount = Int(ceil(Double(leadingOffset) / 7.0))

        var cells: [[HeatmapCell]] = Array(repeating: Array(repeating: .empty, count: weekCount), count: 7)
        for dayIndex in 0..<totalDays {
            guard let date = calendar.date(byAdding: .day, value: -(totalDays - 1 - dayIndex), to: today) else { continue }
            let absoluteIndex = dayIndex + (leadingOffset - totalDays)
            let col = absoluteIndex / 7
            let row = absoluteIndex % 7
            guard row < 7, col < weekCount else { continue }
            let count = snapshot.sessionsPerDay[date] ?? 0
            cells[row][col] = .day(date: date, count: count)
        }

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(0..<7, id: \.self) { row in
                    Text(weekdayLabel(for: row))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(insightsNeutralGray400)
                        .frame(height: 14)
                        .opacity(row % 2 == 1 ? 1.0 : 0.0) // Mon / Wed / Fri visible
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                monthLabelRow(weekCount: weekCount, calendar: calendar, today: today, leadingOffset: leadingOffset)
                HStack(alignment: .top, spacing: 4) {
                    ForEach(0..<weekCount, id: \.self) { col in
                        VStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { row in
                                heatmapCellView(cells[row][col])
                            }
                        }
                    }
                }
            }
        }
    }

    private enum HeatmapCell {
        case empty
        case day(date: Date, count: Int)
    }

    @ViewBuilder
    private func heatmapCellView(_ cell: HeatmapCell) -> some View {
        switch cell {
        case .empty:
            Color.clear.frame(width: 14, height: 14)
        case .day(let date, let count):
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(heatmapColor(for: level(for: count)))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(insightsOutlineVariant.opacity(count == 0 ? 0.35 : 0), lineWidth: 1)
                )
                .frame(width: 14, height: 14)
                .help(heatmapTooltip(date: date, count: count))
        }
    }

    private func monthLabelRow(weekCount: Int, calendar: Calendar, today: Date, leadingOffset: Int) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        var labels: [(col: Int, text: String)] = []
        var lastMonth: Int = -1
        let totalDays = stats.range.heatmapDays
        for col in 0..<weekCount {
            let absoluteDayIndex = col * 7
            let dayOffsetFromStart = absoluteDayIndex - (leadingOffset - totalDays)
            guard dayOffsetFromStart >= 0,
                  let date = calendar.date(byAdding: .day, value: -(totalDays - 1 - dayOffsetFromStart), to: today)
            else { continue }
            let month = calendar.component(.month, from: date)
            if month != lastMonth {
                labels.append((col, formatter.string(from: date)))
                lastMonth = month
            }
        }

        return HStack(spacing: 0) {
            ForEach(0..<weekCount, id: \.self) { col in
                let match = labels.first(where: { $0.col == col })
                Text(match?.text ?? "")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(insightsNeutralGray400)
                    .frame(width: 18, alignment: .leading)
            }
        }
        .frame(height: 12)
    }

    private func heatmapColor(for level: Int) -> Color {
        switch level {
        case 0: return insightsSurfaceContainerLow
        case 1: return insightsPrimary.opacity(0.25)
        case 2: return insightsPrimary.opacity(0.45)
        case 3: return insightsPrimary.opacity(0.7)
        default: return insightsPrimary
        }
    }

    private func level(for count: Int) -> Int {
        switch count {
        case 0: return 0
        case 1: return 1
        case 2: return 2
        case 3: return 3
        default: return 4
        }
    }

    private func heatmapTooltip(date: Date, count: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let dayLabel = formatter.string(from: date)
        let sessionLabel = count == 1 ? "1 session" : "\(count) sessions"
        return "\(dayLabel) — \(sessionLabel)"
    }

    private func weekdayLabel(for row: Int) -> String {
        // row 0 = Sun, 1 = Mon, ...
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][row]
    }

    // MARK: Tool Breakdown + Streaks

    private var breakdownAndStreaksRow: some View {
        HStack(alignment: .top, spacing: 16) {
            toolBreakdownCard
                .frame(maxWidth: .infinity)
            streaksCard
                .frame(width: 260)
        }
    }

    private var toolBreakdownCard: some View {
        let snapshot = stats
        let breakdown = snapshot.toolBreakdown
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("TOOL BREAKDOWN")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(insightsPrimary)
                    .tracking(1.2)
                Spacer()
                if !breakdown.isEmpty {
                    Text("\(breakdown.count) tool\(breakdown.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(insightsNeutralGray400)
                }
            }

            if breakdown.isEmpty {
                emptyBreakdownState
            } else {
                toolBreakdownChart(breakdown: breakdown)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(insightsSurfaceLowest)
                .shadow(color: insightsOnSurface.opacity(0.04), radius: 10, y: 4)
        )
    }

    private var emptyBreakdownState: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.system(size: 18))
                .foregroundColor(insightsNeutralGray400)
            Text("No sessions in this window yet. Talk to Sparkle about a tool to populate this chart.")
                .font(.system(size: 12))
                .foregroundColor(insightsNeutralGray500)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }

    private func toolBreakdownChart(breakdown: [InsightsStats.ToolUsage]) -> some View {
        let maxSessions = max(breakdown.map { $0.sessions }.max() ?? 1, 1)
        let chartHeight = max(CGFloat(breakdown.count) * 28 + 20, 120)

        return Chart(breakdown) { usage in
            BarMark(
                x: .value("Sessions", usage.sessions),
                y: .value("Tool", usage.name)
            )
            .foregroundStyle(
                usage.name == "Other"
                    ? insightsNeutralGray400.opacity(0.6)
                    : insightsPrimary
            )
            .cornerRadius(4)
            .annotation(position: .trailing, alignment: .leading) {
                HStack(spacing: 6) {
                    Text("\(usage.sessions)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(insightsOnSurface)
                    if usage.minutes > 0 {
                        Text("· \(formattedDuration(minutes: usage.minutes))")
                            .font(.system(size: 11))
                            .foregroundColor(insightsNeutralGray400)
                    }
                }
                .padding(.leading, 6)
            }
        }
        .chartXScale(domain: 0...(Double(maxSessions) + 0.5))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel()
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(insightsOnSurfaceVariant)
            }
        }
        .chartPlotStyle { plot in
            plot.padding(.trailing, 60)
        }
        .frame(height: chartHeight)
    }

    private var streaksCard: some View {
        let snapshot = stats
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("STREAKS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(insightsPrimary)
                    .tracking(1.2)
                Spacer()
                Image(systemName: "flame.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#f97316"))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("\(snapshot.currentStreak)")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(insightsOnSurface)
                    .tracking(-1.5)
                Text(snapshot.currentStreak == 1 ? "day current streak" : "day current streak")
                    .font(.system(size: 12))
                    .foregroundColor(insightsOnSurfaceVariant)
            }

            Divider().background(insightsOutlineVariant.opacity(0.4))

            VStack(alignment: .leading, spacing: 6) {
                Text("LONGEST")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(insightsNeutralGray400)
                    .tracking(1.5)
                Text(snapshot.longestStreak == 0 ? "—" : "\(snapshot.longestStreak) day\(snapshot.longestStreak == 1 ? "" : "s")")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(insightsOnSurface)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(insightsSurfaceLowest)
                .shadow(color: insightsOnSurface.opacity(0.04), radius: 10, y: 4)
        )
    }

    // MARK: Helpers

    private func formattedDuration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let hours = Double(minutes) / 60.0
        if hours < 10 { return String(format: "%.1fh", hours) }
        return "\(Int(hours))h"
    }
}
