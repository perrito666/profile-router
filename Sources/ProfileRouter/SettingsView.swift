import SwiftUI
import AppKit
import RouterCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var testURL = ""
    @State private var testResult = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profile Router").font(.title2.bold())
                    Text("Send each link to the right Chrome profile.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Set as Default Browser") { model.makeDefault() }
            }
            Text(model.defaultBrowserSummary).font(.caption).foregroundStyle(.secondary)
            if let message = model.profileError {
                HStack(alignment: .top) {
                    Text(message).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                    Spacer()
                    Button("Choose Chrome Folder…") { model.chooseChromeFolder() }
                }
            }
            HStack {
                Text("Routing rules").font(.headline)
                Text("First matching enabled rule wins.").foregroundStyle(.secondary)
                Spacer()
                Button("Refresh Profiles") { model.refreshProfiles() }
            }
            ScrollView {
                VStack(spacing: 10) {
                    if model.configuration.rules.isEmpty {
                        Text("No rules yet. All links use Chrome’s normal profile selection.")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100)
                    }
                    ForEach($model.configuration.rules) { $rule in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Toggle("Enabled", isOn: $rule.enabled).labelsHidden()
                                    .help("Enable this rule").accessibilityLabel("Enable rule")
                                Picker("Match", selection: $rule.kind) {
                                    ForEach(MatchKind.allCases) { kind in Text(kind.title).tag(kind) }
                                }.labelsHidden().frame(width: 145)
                                TextField(rule.kind == .host ? "*.example.com" : "https://github.com/company/*", text: $rule.pattern)
                                    .textFieldStyle(.roundedBorder).accessibilityLabel("URL pattern")
                                Picker("Profile", selection: $rule.profileDirectory) {
                                    Text("Choose profile").tag("")
                                    ForEach(model.profiles) { profile in
                                        Text("\(profile.name) (\(profile.directory))").tag(profile.directory)
                                    }
                                    if !rule.profileDirectory.isEmpty && !model.profiles.contains(where: { $0.directory == rule.profileDirectory }) {
                                        Text("Missing: \(rule.profileDirectory)").tag(rule.profileDirectory)
                                    }
                                }.labelsHidden().frame(width: 190)
                            }
                            HStack {
                                if let error = rule.validationError {
                                    Text(error).font(.caption).foregroundStyle(.orange)
                                }
                                Spacer()
                                Button { move(rule.id, by: -1) } label: { Image(systemName: "arrow.up") }
                                    .help("Move rule up").accessibilityLabel("Move rule up")
                                    .disabled(model.configuration.rules.first?.id == rule.id)
                                Button { move(rule.id, by: 1) } label: { Image(systemName: "arrow.down") }
                                    .help("Move rule down").accessibilityLabel("Move rule down")
                                    .disabled(model.configuration.rules.last?.id == rule.id)
                                Button(role: .destructive) {
                                    model.configuration.rules.removeAll { $0.id == rule.id }
                                } label: { Image(systemName: "trash") }
                                    .help("Delete rule").accessibilityLabel("Delete rule")
                            }
                        }.padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }.frame(minHeight: 130)
            HStack {
                Button("Add Rule", systemImage: "plus") {
                    model.configuration.rules.append(Rule(profileDirectory: model.profiles.first?.directory ?? ""))
                }
                Spacer()
                if model.hasUnsavedChanges { Text("Unsaved changes").foregroundStyle(.orange) }
                Button("Save Rules") { model.save() }.keyboardShortcut("s")
            }
            Divider()
            Text("No match → Chrome chooses the profile, normally using its most recently active window. When Chrome is closed, its startup settings apply.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Use * for any characters. Hostnames ignore case; full URLs are case-sensitive. *.example.com excludes example.com itself.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Paste a URL to test draft rules", text: $testURL).textFieldStyle(.roundedBorder)
                    .onSubmit { test() }
                Button("Test URL") { test() }
                Button("Open Test URL") { openTest() }
                    .help("Open the URL through the same saved-rule routing used for external links")
            }
            if !testResult.isEmpty { Text(testResult).font(.callout).textSelection(.enabled) }
            Text("Last handoff: \(model.lastHandoff)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if !model.status.isEmpty { Text(model.status).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(20)
        .onChange(of: model.configuration) { _ in
            model.hasUnsavedChanges = true
            model.status = ""
            testResult = ""
        }
        .alert("Profile Router", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = model.configuration.rules.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard model.configuration.rules.indices.contains(target) else { return }
        model.configuration.rules.swapAt(index, target)
    }

    private func test() {
        guard let url = testInputURL else {
            testResult = "Enter a complete URL or an absolute file path."; return
        }
        if let rule = model.configuration.matchingRule(for: url) {
            let profile = model.profiles.first { $0.directory == rule.profileDirectory }
            testResult = profile.map { "\(model.hasUnsavedChanges ? "Draft rule" : "Rule") matched \(rule.pattern) → \($0.name) (\($0.directory))\(model.hasUnsavedChanges ? ". Save Rules before opening links." : "")" }
                ?? "Matched \(rule.pattern), but profile \(rule.profileDirectory) is missing → pass through to Chrome."
        } else { testResult = "No match → Chrome’s normal profile selection." }
    }

    private func openTest() {
        guard !model.hasUnsavedChanges else {
            testResult = "Save Rules first. Open Test URL uses the saved rules, just like external links."
            return
        }
        guard let url = testInputURL else {
            testResult = "Enter a complete URL or an absolute file path."
            return
        }
        model.route([url])
    }

    private var testInputURL: URL? {
        if testURL.hasPrefix("/") { return URL(fileURLWithPath: testURL) }
        guard let url = URL(string: testURL), url.scheme != nil else { return nil }
        return url
    }
}
