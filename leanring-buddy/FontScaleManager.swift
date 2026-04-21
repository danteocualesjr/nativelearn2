//
//  FontScaleManager.swift
//  leanring-buddy
//
//  Owns the main-window zoom level that responds to ⌘+, ⌘-, and ⌘0.
//  The scale is applied via `ZoomableContainer`, which wraps the root
//  view in a GeometryReader and uses `scaleEffect` with a matching
//  inverse-sized frame so SwiftUI's layout still fills the window
//  correctly at any zoom level. The current scale is persisted to
//  UserDefaults so it survives relaunches.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class FontScaleManager: ObservableObject {
    static let shared = FontScaleManager()

    /// Persisted zoom level. 1.0 = 100%.
    @Published var scale: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(scale), forKey: Self.storageKey)
        }
    }

    /// Sensible bounds so the UI never becomes unusable.
    static let minScale: CGFloat = 0.7
    static let maxScale: CGFloat = 1.8
    static let step: CGFloat = 0.1
    private static let storageKey = "mainWindowFontScale"

    private init() {
        let stored = UserDefaults.standard.double(forKey: Self.storageKey)
        // Treat a missing key (0.0) as the default 1.0.
        let initial = stored == 0 ? 1.0 : stored
        self.scale = CGFloat(min(max(initial, Double(Self.minScale)), Double(Self.maxScale)))
    }

    func zoomIn() {
        setScale(scale + Self.step)
    }

    func zoomOut() {
        setScale(scale - Self.step)
    }

    func resetZoom() {
        setScale(1.0)
    }

    private func setScale(_ value: CGFloat) {
        // Round to the nearest step to avoid floating-point drift.
        let clamped = min(max(value, Self.minScale), Self.maxScale)
        let rounded = (clamped / Self.step).rounded() * Self.step
        if abs(rounded - scale) > 0.0001 {
            scale = rounded
        }
    }
}

// MARK: - Keyboard Monitor

/// Installs a local key-down monitor that routes ⌘+, ⌘=, ⌘-, and ⌘0
/// to the shared `FontScaleManager`. Returns the opaque monitor token,
/// which the caller keeps alive for the lifetime of the app.
@MainActor
enum FontScaleKeyboardMonitor {
    static func install() -> Any? {
        return NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command) else { return event }

            // Ignore if any other modifier that would indicate an unrelated
            // shortcut is held (control/option). Shift is allowed because
            // ⌘+ on most layouts is actually ⌘⇧=.
            let disallowed: NSEvent.ModifierFlags = [.control, .option]
            if !event.modifierFlags.isDisjoint(with: disallowed) { return event }

            guard let characters = event.charactersIgnoringModifiers else { return event }

            switch characters {
            case "+", "=":
                FontScaleManager.shared.zoomIn()
                return nil
            case "-", "_":
                FontScaleManager.shared.zoomOut()
                return nil
            case "0":
                FontScaleManager.shared.resetZoom()
                return nil
            default:
                return event
            }
        }
    }
}

// MARK: - Zoomable Container

/// Wraps `content` in a view that scales with `FontScaleManager.shared.scale`.
/// A `GeometryReader` measures the available space, the content is sized to
/// `size / scale`, then multiplied back up by `scaleEffect`. This preserves
/// the original layout math so everything (not just text) scales proportionally
/// while still filling the window at any zoom level.
struct ZoomableContainer<Content: View>: View {
    @ObservedObject private var fontScale = FontScaleManager.shared
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = fontScale.scale
            content()
                .frame(width: proxy.size.width / scale,
                       height: proxy.size.height / scale,
                       alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
        }
    }
}
