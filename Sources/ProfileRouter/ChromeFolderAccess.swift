import AppKit
import RouterCore

/// Keeps the user-selected folder's security scope alive for the app's lifetime.
/// The bookmark is local to this app, separate from portable routing rules.
@MainActor
final class ChromeFolderAccess {
    let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
    private let bookmarkURL: URL
    private(set) var root: URL?
    private var ownsScope = false

    init(bookmarkURL: URL) { self.bookmarkURL = bookmarkURL }

    func restore() throws {
        guard FileManager.default.fileExists(atPath: bookmarkURL.path) else { return }
        let data = try Data(contentsOf: bookmarkURL)
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        try activate(url)
        if stale { try persist(url) }
    }

    func choose() throws -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Allow access to Chrome profiles"
        panel.message = "Select the Chrome folder to read profile names. Select Open (Allow Access) to grant access to this folder."
        panel.prompt = "Allow Access"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = defaultRoot
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        try activate(url)
        try persist(url)
        return true
    }

    private func activate(_ url: URL) throws {
        // Chrome's launch flags below address the stable channel's default user-data directory.
        guard url.standardizedFileURL.path == defaultRoot.standardizedFileURL.path else {
            throw FolderError.wrongFolder(defaultRoot.path)
        }
        // Open panels may already activate access. A false return alone is not proof of denial
        // in this unsandboxed app; the actual read below decides whether the grant works.
        let startedScope = url.startAccessingSecurityScopedResource()
        do {
            // Verify access before replacing a working grant. Do not enumerate unrelated data.
            _ = try ChromeProfile.discover(localState: Data(contentsOf: url.appendingPathComponent("Local State")), root: url)
        } catch {
            if startedScope { url.stopAccessingSecurityScopedResource() }
            throw error
        }
        if ownsScope { root?.stopAccessingSecurityScopedResource() }
        root = url
        ownsScope = startedScope
    }

    private func persist(_ url: URL) throws {
        let data = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                        includingResourceValuesForKeys: nil, relativeTo: nil)
        try FileManager.default.createDirectory(at: bookmarkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: bookmarkURL, options: .atomic)
    }
}

private enum FolderError: LocalizedError {
    case wrongFolder(String)
    var errorDescription: String? {
        switch self {
        case .wrongFolder(let path): return "Select the Chrome folder at \(path)."
        }
    }
}
