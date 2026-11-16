import AppKit
import SwiftUI
import RouterCore

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var configuration = Configuration()
    @Published var profiles: [ChromeProfile] = []
    @Published var error: String?
    @Published var profileError: String?
    @Published var status = ""
    @Published var hasUnsavedChanges = false
    @Published var lastHandoff = "No links received since launch."
    @Published var defaultBrowserSummary = ""
    private var loadFailed = false
    private var window: NSWindow?
    private var latestHandoffID: UUID?
    private let folderAccess: ChromeFolderAccess

    let configurationURL: URL
    var chromeURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") }

    private init() {
        configurationURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Profile Router/config.json")
        folderAccess = ChromeFolderAccess(bookmarkURL: configurationURL.deletingLastPathComponent()
            .appendingPathComponent("chrome-folder.bookmark"))
        if FileManager.default.fileExists(atPath: configurationURL.path) {
            do { configuration = try Configuration.decode(Data(contentsOf: configurationURL)) }
            catch {
                loadFailed = true
                status = "Cannot load configuration. Inputs will pass through to Chrome. The file has been preserved. \(error.localizedDescription)"
            }
        }
        do {
            try folderAccess.restore()
            refreshProfiles()
        } catch {
            profileError = "Chrome folder access needs to be renewed. Choose Chrome Folder… to allow access. \(error.localizedDescription)"
        }
    }

    func chooseChromeFolder() {
        do {
            if try folderAccess.choose() { refreshProfiles() }
        } catch {
            profileError = "Could not authorize the Chrome folder. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func refreshProfiles() -> Bool {
        guard let chromeRoot = folderAccess.root else {
            profiles = []
            profileError = "Choose Chrome Folder… to allow macOS access to Chrome’s profile names."
            return false
        }
        do {
            profiles = try ChromeProfile.discover(
                localState: Data(contentsOf: chromeRoot.appendingPathComponent("Local State")), root: chromeRoot)
            profileError = profiles.isEmpty ? "No Chrome profiles found. Open Chrome and create a profile, then refresh." : nil
            return true
        } catch {
            profiles = []
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoPermissionError {
                profileError = "macOS denied access to Chrome’s profile list. Choose Chrome Folder… to renew access."
            } else {
                profileError = "Cannot read Chrome’s profile list. \(error.localizedDescription)"
            }
            return false
        }
    }

    func save() {
        guard !loadFailed else {
            error = "Configuration could not be loaded. Repair or move \(configurationURL.path), then restart. Saving is disabled to preserve your file."
            return
        }
        for (index, rule) in configuration.rules.enumerated() where rule.enabled {
            if let reason = rule.validationError { error = "Rule \(index + 1): \(reason)"; return }
            guard profiles.contains(where: { $0.directory == rule.profileDirectory }) else {
                error = "Rule \(index + 1) targets a missing profile. Refresh profiles and choose a target."
                return
            }
        }
        do {
            try FileManager.default.createDirectory(at: configurationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: configurationURL, options: .atomic)
            hasUnsavedChanges = false
            status = "Rules saved."
        } catch { self.error = "Cannot save rules: \(error.localizedDescription)" }
    }

    // Routing uses only the last successfully saved configuration, never half-edited rules.
    func savedConfiguration() throws -> Configuration {
        if loadFailed { throw RoutingError.invalidConfiguration }
        if !FileManager.default.fileExists(atPath: configurationURL.path) { return Configuration() }
        return try Configuration.decode(Data(contentsOf: configurationURL))
    }

    func route(_ urls: [URL]) {
        do {
            guard let app = chromeURL else { throw RoutingError.chromeMissing }
            for url in urls {
                let requestID = UUID()
                latestHandoffID = requestID
                // Do not inspect files or require access to Chrome's profile data for pass-through.
                let saved = Configuration.isWebURL(url) ? try? savedConfiguration() : nil
                if saved?.matchingRule(for: url) != nil { refreshProfiles() }
                let host = url.isFileURL ? "local file" : (url.host ?? "\(url.scheme ?? "unknown") URL")
                let time = Date().formatted(date: .omitted, time: .standard)
                switch RoutingDecision.resolve(url, configuration: saved, profiles: profiles) {
                case .profile(let rule):
                    let profileName = profiles.first { $0.directory == rule.profileDirectory }?.name ?? rule.profileDirectory
                    let summary = "\(time): \(host) → \(profileName) (\(rule.profileDirectory)); rule \(rule.pattern)"
                    lastHandoff = summary + "; sending to Chrome…"
                    let options = NSWorkspace.OpenConfiguration()
                    // Launch Services otherwise reuses Chrome without delivering new startup arguments.
                    // Chrome's own singleton forwards this launch to the existing browser process.
                    options.createsNewApplicationInstance = true
                    options.arguments = ["--profile-directory=\(rule.profileDirectory)", "--", url.absoluteString]
                    // Do not send the URL via open(_:withApplicationAt:). A separate URL Apple Event
                    // would let Chrome choose its last-used profile independently of the arguments.
                    NSWorkspace.shared.openApplication(at: app, configuration: options) { _, failure in
                        Task { @MainActor in
                            if let failure {
                                self.status = "Profile launch failed: \(failure.localizedDescription). Passing through to Chrome."
                                if self.latestHandoffID == requestID { self.lastHandoff = summary + "; handoff failed" }
                                self.passThrough(url, to: app, summary: summary + "; profile launch failed; passing through to Chrome")
                            } else if self.latestHandoffID == requestID {
                                self.lastHandoff = summary + "; launch request accepted"
                            }
                        }
                    }
                case .passthrough:
                    passThrough(url, to: app, summary: "\(time): \(host) → no usable profile rule; passing through to Chrome")
                }
            }
        } catch { report(error.localizedDescription) }
    }

    private func passThrough(_ url: URL, to application: URL, summary: String) {
        lastHandoff = summary
        // Explicit destination avoids reopening Profile Router via a default file/scheme handler.
        NSWorkspace.shared.open([url], withApplicationAt: application, configuration: .init()) { _, failure in
            if let failure {
                Task { @MainActor in self.report("Chrome could not open this item: \(failure.localizedDescription)") }
            }
        }
    }

    func refreshDefaultBrowser() {
        defaultBrowserSummary = ["http", "https"].map { scheme in
            let url = URL(string: "\(scheme)://example.com")!
            guard let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return "\(scheme.uppercased()): unknown" }
            return "\(scheme.uppercased()): \(app.deletingPathExtension().lastPathComponent)"
        }.joined(separator: " · ")
    }

    func report(_ message: String) { error = message; showSettings() }

    func makeDefault() {
        Task {
            do {
                for scheme in ["http", "https"] {
                    try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
                }
                status = "Profile Router is the default browser."
                refreshDefaultBrowser()
            } catch { self.error = "Could not change the default browser: \(error.localizedDescription)" }
        }
    }

    func showSettings() {
        refreshDefaultBrowser()
        if window == nil {
            let view = SettingsView(model: self)
            let controller = NSHostingController(rootView: view)
            let newWindow = NSWindow(contentViewController: controller)
            newWindow.title = "Profile Router"
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.setContentSize(NSSize(width: 820, height: 560))
            newWindow.minSize = NSSize(width: 720, height: 480)
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum RoutingError: LocalizedError {
    case chromeMissing, invalidConfiguration
    var errorDescription: String? {
        switch self {
        case .chromeMissing: return "Google Chrome is not installed. Install it before routing links."
        case .invalidConfiguration: return "The saved routing configuration could not be loaded."
        }
    }
}
