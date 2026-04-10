//
//  leanring_buddyApp.swift
//  leanring-buddy
//
//  Menu bar companion app with a separate main window for conversation
//  history. LSUIElement=true keeps the app out of the Dock so the cursor
//  overlay works correctly across all apps. The main window is created
//  programmatically via NSWindow + NSHostingView.
//

import ServiceManagement
import SwiftUI

@main
struct leanring_buddyApp: App {
    @NSApplicationDelegateAdaptor(CompanionAppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class CompanionAppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarPanelManager: MenuBarPanelManager?
    private var mainWindow: NSWindow?
    let companionManager = CompanionManager()
    let conversationStore = ConversationStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🎯 NativeLearn: Starting...")
        print("🎯 NativeLearn: Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")

        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 0])

        NativeLearnAnalytics.configure()
        NativeLearnAnalytics.trackAppOpened()

        companionManager.conversationStore = conversationStore

        // 1) Start companion in accessory mode (LSUIElement=true) so the
        //    overlay windows are created with the correct window levels.
        menuBarPanelManager = MenuBarPanelManager(companionManager: companionManager)
        companionManager.start()
        if !companionManager.hasCompletedOnboarding || !companionManager.allPermissionsGranted {
            menuBarPanelManager?.showPanelOnLaunch()
        }

        // 2) Switch to regular app AFTER overlay is set up. This gives us
        //    Dock icon, menu bar, and proper full-screen support.
        NSApplication.shared.setActivationPolicy(.regular)

        // 3) Re-assert overlay window levels after the policy switch,
        //    since changing activation policy can reset window ordering.
        reassertOverlayWindows()

        registerAsLoginItemIfNeeded()
        createAndShowMainWindow()
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
    }

    private func reassertOverlayWindows() {
        for window in NSApplication.shared.windows where window is OverlayWindow {
            window.level = .screenSaver
            window.orderFrontRegardless()
        }
    }

    // MARK: - Main Window

    private func createAndShowMainWindow() {
        let contentView = MainWindowView(
            conversationStore: conversationStore,
            companionManager: companionManager
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "NativeLearn"
        window.minSize = NSSize(width: 800, height: 550)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.backgroundColor = NSColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1)
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.setFrameAutosaveName("NativeLearnMainWindow")
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
                print("🎯 NativeLearn: Registered as login item")
            } catch {
                print("⚠️ NativeLearn: Failed to register as login item: \(error)")
            }
        }
    }
}
