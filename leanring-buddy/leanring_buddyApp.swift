//
//  leanring_buddyApp.swift
//  leanring-buddy
//
//  Menu bar-only companion app. No dock icon, no main window — just an
//  always-available status item in the macOS menu bar. Clicking the icon
//  opens a floating panel with companion voice controls.
//

import ServiceManagement
import SwiftUI

@main
struct leanring_buddyApp: App {
    @NSApplicationDelegateAdaptor(CompanionAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainWindowView(
                conversationStore: appDelegate.conversationStore,
                companionManager: appDelegate.companionManager
            )
            .frame(minWidth: 800, minHeight: 550)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 650)
    }
}

@MainActor
final class CompanionAppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarPanelManager: MenuBarPanelManager?
    let companionManager = CompanionManager()
    let conversationStore = ConversationStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🎯 NativeLearn: Starting...")
        print("🎯 NativeLearn: Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")

        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 0])

        NativeLearnAnalytics.configure()
        NativeLearnAnalytics.trackAppOpened()

        companionManager.conversationStore = conversationStore

        menuBarPanelManager = MenuBarPanelManager(companionManager: companionManager)
        companionManager.start()
        if !companionManager.hasCompletedOnboarding || !companionManager.allPermissionsGranted {
            menuBarPanelManager?.showPanelOnLaunch()
        }
        registerAsLoginItemIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        companionManager.stop()
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
