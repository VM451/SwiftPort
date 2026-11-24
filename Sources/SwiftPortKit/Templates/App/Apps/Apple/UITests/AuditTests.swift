import XCTest

/// Accessibility audit gate (PRD FR-7): launches the app once per contract
/// scenario × theme and runs XCUIAccessibilityAudit over the live AX tree.
/// Fails the suite if any contrast / hit-region / label / clipping issue
/// is reported.
///
/// `SWIFTPORT_ROOT` is injected by `swiftport verify` via xcodebuild's
/// `TEST_RUNNER_` environment prefix.
final class AuditTests: XCTestCase {

    func testAccessibilityAudits() throws {
        guard let root = ProcessInfo.processInfo.environment["SWIFTPORT_ROOT"],
              !root.isEmpty else {
            XCTFail("SWIFTPORT_ROOT not set — run via `swiftport verify`")
            return
        }
        let contractsDir = root + "/Verification/Contracts"
        let ids = try fixtureIDs(in: contractsDir)
        XCTAssertFalse(ids.isEmpty, "no contract fixtures at \(contractsDir)")

        var allIssues: [String] = []
        for id in ids {
            for theme in ["light", "dark"] {
                let app = XCUIApplication()
                app.launchEnvironment["SWIFTPORT_SCENARIO"] = id
                app.launchEnvironment["SWIFTPORT_THEME"] = theme
                app.launchEnvironment["SWIFTPORT_CONTRACTS_DIR"] = contractsDir
                app.launch()
                // Let the first frame + fixture load settle before auditing.
                sleep(1)

                var issues: [String] = []
                do {
                    try app.performAccessibilityAudit(for: .all) { issue in
                        issues.append(
                            "\(issue.compactDescription) — \(issue.detailedDescription)")
                        return true
                    }
                } catch {
                    issues.append("audit threw: \(error.localizedDescription)")
                }
                app.terminate()
                allIssues += issues.map { "\(id)/\(theme): \($0)" }
            }
        }
        XCTAssertTrue(
            allIssues.isEmpty,
            "\(allIssues.count) accessibility issue(s):\n"
                + allIssues.prefix(50).joined(separator: "\n"))
    }

    private func fixtureIDs(in dir: String) throws -> [String] {
        let names = try FileManager.default.contentsOfDirectory(atPath: dir)
        var ids: [String] = []
        for name in names where name.hasSuffix(".json") {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = obj["id"] as? String else { continue }
            ids.append(id)
        }
        return ids.sorted()
    }
}
