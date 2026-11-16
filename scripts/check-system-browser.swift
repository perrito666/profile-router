// Run in Terminal: swift scripts/check-system-browser.swift
// Uses the same NSWorkspace URL-opening API used by Slack's Electron runtime.
import AppKit

let url = URL(string: "https://id.atlassian.com/")!
let workspace = NSWorkspace.shared
print("Resolved browser: \(workspace.urlForApplication(toOpen: url)?.path ?? "unknown")")
workspace.open(url, configuration: NSWorkspace.OpenConfiguration()) { application, error in
    if let error {
        print("Open failed: \(error.localizedDescription)")
        exit(1)
    }
    print("Opened application: \(application?.bundleURL?.path ?? "unknown")")
    exit(0)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
    print("Timed out waiting for the macOS URL-opening result.")
    exit(1)
}
RunLoop.main.run()
