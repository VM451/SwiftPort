import Foundation
import Testing
@testable import AppCoreCABI

@Suite("C ABI bridge")
struct CABITests {

    private let populatedFixture = """
    {"id":"populated","phase":"loaded","errorMessage":null,"tasks":[
      {"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","title":"Ship it",
       "notes":"","isCompleted":false,"priority":"high",
       "createdAt":"2026-01-01T00:00:00Z"}
    ]}
    """

    @Test("fixture snapshot returns encoded TaskListSnapshot JSON")
    func fixtureSnapshot() throws {
        let json = try #require(Bridge.fixtureSnapshotJSON(populatedFixture))
        let snapshot = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        #expect(snapshot?["phase"] as? String == "loaded")
        let tasks = try #require(snapshot?["tasks"] as? [[String: Any]])
        #expect(tasks.count == 1)
        #expect(tasks[0]["title"] as? String == "Ship it")
        #expect(tasks[0]["priority"] as? String == "high")
        // ISO-8601 date strategy keeps createdAt a string, matching the
        // fixture wire format every platform parses.
        #expect(tasks[0]["createdAt"] as? String == "2026-01-01T00:00:00Z")
    }

    @Test("malformed fixture JSON returns nil")
    func malformedFixture() {
        #expect(Bridge.fixtureSnapshotJSON("not json") == nil)
        #expect(Bridge.fixtureSnapshotJSON("{}") == nil)
    }

    @Test("store mutations round-trip through snapshot JSON")
    func storeMutations() throws {
        _ = Bridge.resetStore()
        let before = try #require(Bridge.snapshotJSON())
        #expect(before.contains("\"phase\":\"loaded\""))

        let added = try #require(Bridge.addTask(title: "Bridge test", notes: "", priority: "low"))
        #expect(added.contains("Bridge test"))

        // First demo task id toggles to completed.
        let id = "11111111-1111-1111-1111-111111111111"
        let toggled = try #require(Bridge.toggleTask(id: id))
        #expect(toggled.contains("\"isCompleted\":true"))

        let deleted = try #require(Bridge.deleteTask(id: id))
        #expect(!deleted.contains(id))

        #expect(Bridge.toggleTask(id: "not-a-uuid") == nil)
    }
}
