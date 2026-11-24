import Foundation

/// Marks a public type as part of the SwiftPort bridge surface.
///
/// `swiftport sync` scans `Core/Sources` for conformances to this protocol
/// and uses them to generate platform bindings (Kotlin/JNI on Android,
/// C-ABI + P/Invoke on Windows) in later phases. Apple and Linux consume
/// `AppCore` directly and need no generated glue.
///
/// Only conformance matters — the protocol has no requirements. Keep bridged
/// types `Sendable` and `Codable` so every platform can serialize them.
public protocol SwiftPortExported {}
