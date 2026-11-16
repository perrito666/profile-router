import Foundation

public enum MatchKind: String, Codable, CaseIterable, Identifiable {
    case host, url
    public var id: String { rawValue }
    public var title: String { self == .host ? "Hostname glob" : "Full URL glob" }
}

public struct Rule: Codable, Identifiable, Equatable {
    public var id: UUID
    public var enabled: Bool
    public var kind: MatchKind
    public var pattern: String
    public var profileDirectory: String

    public init(id: UUID = UUID(), enabled: Bool = true, kind: MatchKind = .host,
                pattern: String = "", profileDirectory: String = "") {
        self.id = id
        self.enabled = enabled
        self.kind = kind
        self.pattern = pattern
        self.profileDirectory = profileDirectory
    }

    public var validationError: String? {
        guard !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Enter a pattern."
        }
        guard pattern == pattern.trimmingCharacters(in: .whitespacesAndNewlines),
              !pattern.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            return "Patterns cannot contain whitespace; use percent-encoded URLs."
        }
        if kind == .host && (pattern.contains("/") || pattern.contains(":") || pattern.contains("?") || pattern.contains("#")) {
            return "Hostname patterns contain only a hostname, for example *.example.com."
        }
        guard Self.validProfileDirectory(profileDirectory) else { return "Choose an existing Chrome profile." }
        return nil
    }

    public static func validProfileDirectory(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\") && !value.contains("\0")
    }

    public func matches(_ url: URL) -> Bool {
        guard enabled, validationError == nil else { return false }
        let candidate: String
        switch kind {
        case .host:
            guard let host = url.host else { return false }
            candidate = host.lowercased()
        case .url: candidate = url.absoluteString
        }
        let needle = kind == .host ? pattern.lowercased() : pattern
        // All characters except * are literal. Anchor at both ends to avoid partial-host matches.
        let expression = "\\A" + needle.components(separatedBy: "*")
            .map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: ".*") + "\\z"
        return candidate.range(of: expression, options: .regularExpression) != nil
    }
}

public struct Configuration: Codable, Equatable {
    public var version: Int
    public var rules: [Rule]
    public init(rules: [Rule] = []) { self.version = 1; self.rules = rules }

    public func matchingRule(for url: URL) -> Rule? {
        guard Self.isWebURL(url) else { return nil }
        return rules.first { $0.matches(url) }
    }

    public static func isWebURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && !(url.host ?? "").isEmpty
    }

    public static func decode(_ data: Data) throws -> Configuration {
        let config = try JSONDecoder().decode(Configuration.self, from: data)
        guard config.version == 1 else { throw ConfigurationError.unsupportedVersion }
        for (index, rule) in config.rules.enumerated() where rule.enabled {
            if let reason = rule.validationError {
                throw ConfigurationError.invalidRule(index + 1, reason)
            }
        }
        return config
    }
}

public enum ConfigurationError: LocalizedError {
    case unsupportedVersion
    case invalidRule(Int, String)
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "Unsupported configuration version. Update Profile Router or restore a version 1 configuration."
        case .invalidRule(let index, let reason): return "Invalid saved rule \(index): \(reason)"
        }
    }
}

/// Inputs the router cannot assign to a usable profile are delegated to Chrome unchanged.
public enum RoutingDecision: Equatable {
    case profile(Rule)
    case passthrough

    public static func resolve(_ url: URL, configuration: Configuration?, profiles: [ChromeProfile]) -> RoutingDecision {
        guard let rule = configuration?.matchingRule(for: url),
              profiles.contains(where: { $0.directory == rule.profileDirectory }) else { return .passthrough }
        return .profile(rule)
    }
}

public struct ChromeProfile: Identifiable, Equatable {
    public var directory: String
    public var name: String
    public var id: String { directory }
    public init(directory: String, name: String) { self.directory = directory; self.name = name }

    public static func discover(localState: Data, root: URL, fileManager: FileManager = .default) throws -> [ChromeProfile] {
        struct State: Decodable {
            struct Profile: Decodable {
                struct Info: Decodable { var name: String? }
                var info_cache: [String: Info]
            }
            var profile: Profile
        }
        let state = try JSONDecoder().decode(State.self, from: localState)
        return state.profile.info_cache.compactMap { directory, info in
            guard Rule.validProfileDirectory(directory) else { return nil }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.appendingPathComponent(directory).path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            return ChromeProfile(directory: directory, name: info.name ?? directory)
        }.sorted { ($0.name, $0.directory) < ($1.name, $1.directory) }
    }
}
