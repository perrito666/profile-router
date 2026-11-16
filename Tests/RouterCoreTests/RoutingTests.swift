import XCTest
@testable import RouterCore

final class RoutingTests: XCTestCase {
    func testHostGlobHasDomainBoundariesAndIgnoresCase() {
        let rule = Rule(pattern: "*.Example.COM", profileDirectory: "Default")
        XCTAssertTrue(rule.matches(URL(string: "https://API.example.com/a")!))
        XCTAssertFalse(rule.matches(URL(string: "https://example.com")!))
        XCTAssertFalse(rule.matches(URL(string: "https://api.example.com.attacker.test")!))
        XCTAssertFalse(rule.matches(URL(string: "https://attacker.test/path/api.example.com")!))
        XCTAssertFalse(rule.matches(URL(string: "https://api.example.com@attacker.test/")!))
    }

    func testFullURLGlobsAreLiteralExceptStarAndCaseSensitive() {
        let rule = Rule(kind: .url, pattern: "https://github.com/ExampleOrg/*?a=1", profileDirectory: "Profile 1")
        XCTAssertTrue(rule.matches(URL(string: "https://github.com/ExampleOrg/API?a=1")!))
        XCTAssertFalse(rule.matches(URL(string: "https://github.com/exampleorg/API?a=1")!))
        XCTAssertFalse(rule.matches(URL(string: "https://githubXcom/ExampleOrg/API?a=1")!))
        XCTAssertFalse(rule.matches(URL(string: "https://github.com/ExampleOrg/API?a=12")!))
    }

    func testFirstEnabledMatchWinsAndNonWebInputsDoNotMatchProfileRules() {
        let config = Configuration(rules: [
            Rule(enabled: false, pattern: "example.com", profileDirectory: "Ignored"),
            Rule(pattern: "example.com", profileDirectory: "Work"),
            Rule(pattern: "*", profileDirectory: "Personal")
        ])
        XCTAssertEqual(config.matchingRule(for: URL(string: "https://example.com")!)?.profileDirectory, "Work")
        XCTAssertEqual(config.matchingRule(for: URL(string: "https://elsewhere.test")!)?.profileDirectory, "Personal")
        XCTAssertNil(config.matchingRule(for: URL(string: "file:///etc/passwd")!))
        XCTAssertNil(config.matchingRule(for: URL(string: "javascript:alert(1)")!))
        XCTAssertNil(config.matchingRule(for: URL(string: "ftp://example.com")!))
        XCTAssertNil(Configuration().matchingRule(for: URL(string: "https://example.com")!))
    }

    func testFilesAndOtherSchemesPassThroughEvenWithCatchAllWebRule() {
        let config = Configuration(rules: [Rule(pattern: "*", profileDirectory: "Work")])
        let profiles = [ChromeProfile(directory: "Work", name: "Work")]
        let inputs = [URL(fileURLWithPath: "/tmp/a report é.html"),
                      URL(string: "mailto:person@example.com")!, URL(string: "ftp://example.com/file")!,
                      URL(string: "chrome://settings/")!, URL(string: "custom-scheme:some-resource")!]
        for url in inputs {
            XCTAssertEqual(RoutingDecision.resolve(url, configuration: config, profiles: profiles), .passthrough)
        }
        XCTAssertEqual(RoutingDecision.resolve(URL(string: "https://example.com")!, configuration: config, profiles: profiles), .profile(config.rules[0]))
    }

    func testUnavailableConfigurationOrMissingTargetFallsBackWithoutSelectingAnotherRule() {
        let url = URL(string: "https://id.atlassian.com/")!
        let config = Configuration(rules: [Rule(pattern: "*.atlassian.com", profileDirectory: "Missing"),
                                           Rule(pattern: "*", profileDirectory: "Personal")])
        let profiles = [ChromeProfile(directory: "Personal", name: "Personal")]
        XCTAssertEqual(RoutingDecision.resolve(url, configuration: nil, profiles: profiles), .passthrough)
        XCTAssertEqual(RoutingDecision.resolve(url, configuration: config, profiles: profiles), .passthrough)
        XCTAssertEqual(RoutingDecision.resolve(url, configuration: config, profiles: []), .passthrough)
    }

    func testValidationRejectsInvalidPatternsAndProfileTraversal() {
        for pattern in ["", " ", "example.com/path", "https://example.com", " example.com", "example.com\n"] {
            XCTAssertNotNil(Rule(pattern: pattern, profileDirectory: "Default").validationError)
        }
        for directory in ["", ".", "..", "../Default", "/tmp/profile", "foo\\bar", "foo\0bar"] {
            XCTAssertNotNil(Rule(pattern: "example.com", profileDirectory: directory).validationError)
        }
        XCTAssertNil(Rule(pattern: "example.com", profileDirectory: "Profile 2").validationError)
    }

    func testConfigurationRoundTripAndVersionGuard() throws {
        let configuration = Configuration(rules: [Rule(pattern: "example.com", profileDirectory: "Default")])
        XCTAssertEqual(try Configuration.decode(JSONEncoder().encode(configuration)), configuration)
        XCTAssertThrowsError(try Configuration.decode(Data("{\"version\":2,\"rules\":[]}".utf8)))
        XCTAssertThrowsError(try Configuration.decode(Data("broken".utf8)))
        let invalid = Configuration(rules: [Rule(pattern: "example.com", profileDirectory: "../outside")])
        XCTAssertThrowsError(try Configuration.decode(JSONEncoder().encode(invalid)))
    }

    func testProfileDiscoveryExcludesStaleAndUnsafeEntries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Default"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Profile 1"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data(#"{"profile":{"info_cache":{"Default":{"name":"Personal"},"Profile 1":{"name":"Work"},"Profile 99":{"name":"Deleted"},"../outside":{"name":"Unsafe"}}}}"#.utf8)
        XCTAssertEqual(try ChromeProfile.discover(localState: data, root: root), [
            ChromeProfile(directory: "Default", name: "Personal"), ChromeProfile(directory: "Profile 1", name: "Work")
        ])
    }
}
