//
//  leanring_buddyApp.swift
//  leanring-buddy
//
//  Desktop app with a main window for conversation history and a menu
//  bar companion. The main window is created programmatically via
//  NSWindow + NSHostingView.
//

import ServiceManagement
import SwiftUI

@main
struct leanring_buddyApp: App {
    @NSApplicationDelegateAdaptor(CompanionAppDelegate.self) var appDelegate

    var body: some Scene {
        // The main window is created programmatically via NSWindow in the
        // app delegate, so this Settings scene is the only SwiftUI Scene we
        // declare. It stays as `EmptyView` because Sparkle's preferences
        // live in `ProfileDetailView` inside the main window, not in a
        // separate Settings panel.
        //
        // We replace the default `.appSettings` command group so that ⌘, (and
        // the "Settings…" menu item macOS auto-creates) routes the user into
        // the in-app Preferences instead of opening an empty Settings window.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Preferences…") {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        if let appDelegate = NSApplication.shared.delegate as? CompanionAppDelegate {
                            appDelegate.showMainWindow()
                        }
                        NotificationCenter.default.post(
                            name: .vibecademyOpenPreferences,
                            object: nil
                        )
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}

@MainActor
final class CompanionAppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarPanelManager: MenuBarPanelManager?
    private var mainWindow: NSWindow?
    private var fontScaleKeyMonitor: Any?
    let companionManager = CompanionManager()
    let conversationStore = ConversationStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🎯 Sparkle: Starting...")
        print("🎯 Sparkle: Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")

        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 0])

        VibecademyAnalytics.configure()
        VibecademyAnalytics.trackAppOpened()

        companionManager.conversationStore = conversationStore

        menuBarPanelManager = MenuBarPanelManager(companionManager: companionManager)
        companionManager.start()
        if !companionManager.hasCompletedOnboarding || !companionManager.allPermissionsGranted {
            menuBarPanelManager?.showPanelOnLaunch()
        }

        reassertOverlayWindows()

        registerAsLoginItemIfNeeded()
        createAndShowMainWindow()

        fontScaleKeyMonitor = FontScaleKeyboardMonitor.install()
    }

    /// Keep the app running when the main window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Re-assert overlay window levels whenever the app reactivates.
    func applicationDidBecomeActive(_ notification: Notification) {
        reassertOverlayWindows()
    }

    /// Reopen the main window when the Dock icon is clicked.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        companionManager.stop()
        if let monitor = fontScaleKeyMonitor {
            NSEvent.removeMonitor(monitor)
            fontScaleKeyMonitor = nil
        }
    }

    private func reassertOverlayWindows() {
        for window in NSApplication.shared.windows where window is OverlayWindow {
            window.level = .screenSaver
            window.orderFrontRegardless()
        }
    }

    // MARK: - Main Window

    private func createAndShowMainWindow() {
        let contentView = ZoomableContainer { [conversationStore, companionManager] in
            MainWindowView(
                conversationStore: conversationStore,
                companionManager: companionManager
            )
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Sparkle"
        window.minSize = NSSize(width: 800, height: 550)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.backgroundColor = NSColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1)
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.setFrameAutosaveName("VibecademyMainWindow")
        window.hidesOnDeactivate = false

        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        self.mainWindow = window
    }

    /// Show the main window when the menu bar icon is clicked while it's
    /// already open, or from any other entry point that needs to surface it.
    func showMainWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else {
            createAndShowMainWindow()
        }
    }

    private func registerAsLoginItemIfNeeded() {
        let loginItemService = SMAppService.mainApp
        if loginItemService.status != .enabled {
            do {
                try loginItemService.register()
                print("🎯 Sparkle: Registered as login item")
            } catch {
                print("⚠️ Sparkle: Failed to register as login item: \(error)")
            }
        }
    }
}
