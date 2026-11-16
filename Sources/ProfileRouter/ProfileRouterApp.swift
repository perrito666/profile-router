import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var receivedURL = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let smokeTest = URLReceiptSmokeTest.active {
            smokeTest.startTimeout()
            return
        }
        // URL events can arrive just after launch. Avoid opening Settings over a clicked link.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if !self.receivedURL { AppModel.shared.showSettings() }
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        receivedURL = true
        if let smokeTest = URLReceiptSmokeTest.active { smokeTest.receive(urls); return }
        AppModel.shared.route(urls)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if URLReceiptSmokeTest.active != nil { return false }
        AppModel.shared.showSettings()
        return true
    }
}

@main
struct ProfileRouterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra("Profile Router", systemImage: "arrow.triangle.branch") {
            Button("Settings…") { AppModel.shared.showSettings() }
            Button("Refresh Chrome Profiles") { AppModel.shared.refreshProfiles() }
            Divider()
            Button("Quit Profile Router") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }
    }
}
