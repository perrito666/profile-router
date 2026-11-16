import AppKit

/// Explicit integration-test mode: receive URL events without opening Chrome or reading profiles.
/// Only hostnames and input kinds are stored in the temporary output file named on the command line.
@MainActor
final class URLReceiptSmokeTest {
    static let active: URLReceiptSmokeTest? = {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--url-receipt-smoke-test"), args.indices.contains(index + 1) else { return nil }
        let output = URL(fileURLWithPath: args[index + 1]).resolvingSymlinksInPath()
        let temporaryRoot = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path + "/"
        // Test mode cannot turn arbitrary external URLs into writes outside the temporary directory.
        guard output.path.hasPrefix(temporaryRoot), output.lastPathComponent == "url-receipts.jsonl" else { return nil }
        return URLReceiptSmokeTest(output: output)
    }()

    private let output: URL
    private var count = 0
    private init(output: URL) { self.output = output }

    func startTimeout() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { NSApp.terminate(nil) }
    }

    func receive(_ urls: [URL]) {
        for url in urls {
            do {
                var data = try JSONSerialization.data(withJSONObject: ["host": url.host ?? "", "kind": url.isFileURL ? "file" : "url"])
                data.append(0x0a)
                if !FileManager.default.fileExists(atPath: output.path) {
                    guard FileManager.default.createFile(atPath: output.path, contents: nil) else { return }
                }
                let handle = try FileHandle(forWritingTo: output)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                count += 1
            } catch { fputs("URL event smoke-test recorder failed: \(error.localizedDescription)\n", stderr) }
        }
        if count >= 3 { DispatchQueue.main.async { NSApp.terminate(nil) } }
    }
}
