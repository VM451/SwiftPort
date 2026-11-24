import Foundation

// C ABI surface for the Android (JNI shim), Windows (P/Invoke) and Linux
// bridges. All strings are UTF-8 `char*` allocated with malloc — callers
// must release them with `swiftport_free_string`. JSON in, JSON out:
// Codable is the single wire format across every platform.

/// Copies a Swift string into a malloc'd C string. Pair with
/// `swiftport_free_string`.
private func cStringCopy(_ string: String) -> UnsafeMutablePointer<CChar>? {
    var bytes = Array(string.utf8)
    bytes.append(0)
    return bytes.withUnsafeMutableBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return nil }
        guard let ptr = malloc(buffer.count) else { return nil }
        memcpy(ptr, base, buffer.count)
        return ptr.assumingMemoryBound(to: CChar.self)
    }
}

private func cString(_ pointer: UnsafePointer<CChar>?) -> String {
    pointer.map { String(cString: $0) } ?? ""
}

@_cdecl("swiftport_abi_version")
public func swiftportABIVersion() -> Int32 {
    Bridge.abiVersion
}

@_cdecl("swiftport_free_string")
public func swiftportFreeString(_ pointer: UnsafeMutablePointer<CChar>?) {
    free(pointer)
}

/// Contract fixture JSON in → `TaskListSnapshot` JSON out.
@_cdecl("swiftport_fixture_snapshot_json")
public func swiftportFixtureSnapshotJSON(
    _ fixtureJSON: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    Bridge.fixtureSnapshotJSON(cString(fixtureJSON)).flatMap(cStringCopy)
}

/// Live store snapshot JSON.
@_cdecl("swiftport_store_snapshot_json")
public func swiftportStoreSnapshotJSON() -> UnsafeMutablePointer<CChar>? {
    Bridge.snapshotJSON().flatMap(cStringCopy)
}

/// Adds a task; returns the updated snapshot JSON.
@_cdecl("swiftport_store_add_task")
public func swiftportStoreAddTask(
    _ title: UnsafePointer<CChar>?,
    _ notes: UnsafePointer<CChar>?,
    _ priority: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    let priorityString = cString(priority)
    return Bridge.addTask(
        title: cString(title),
        notes: cString(notes),
        priority: priorityString.isEmpty ? "medium" : priorityString
    ).flatMap(cStringCopy)
}

/// Toggles completion by task UUID string; returns updated snapshot JSON.
@_cdecl("swiftport_store_toggle_task")
public func swiftportStoreToggleTask(
    _ id: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    Bridge.toggleTask(id: cString(id)).flatMap(cStringCopy)
}

/// Deletes a task by UUID string; returns updated snapshot JSON.
@_cdecl("swiftport_store_delete_task")
public func swiftportStoreDeleteTask(
    _ id: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    Bridge.deleteTask(id: cString(id)).flatMap(cStringCopy)
}

/// Resets the store to its seeded demo state; returns snapshot JSON.
@_cdecl("swiftport_store_reset")
public func swiftportStoreReset() -> UnsafeMutablePointer<CChar>? {
    Bridge.resetStore().flatMap(cStringCopy)
}
