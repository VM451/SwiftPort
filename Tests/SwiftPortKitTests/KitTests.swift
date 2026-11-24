import Foundation
import Testing
@testable import SwiftPortKit

@Suite("ProjectConfig")
struct ConfigTests {

    @Test func roundTrip() throws {
        var config = ProjectConfig()
        config.name = "Task Flow"
        config.bundleIDPrefix = "ai.example"
        config.platforms = [.apple, .linux]
        config.verify.snapshotTolerance = 0.002
        config.verify.themes = ["light", "dark", "hc"]

        let parsed = try ProjectConfig.parse(ProjectConfig.serialize(config))
        #expect(parsed == config)
    }

    @Test func parsesTemplateDefaults() throws {
        // The template's swiftport.toml (tokens already substituted in tests
        // via Template.render; here we test the literal shape).
        let toml = """
        [project]
        name = "Demo"
        bundle_id_prefix = "com.example"

        [targets]
        platforms = ["apple", "linux"]

        [verify]
        snapshot_tolerance = 0.001
        themes = ["light", "dark"]
        """
        let config = try ProjectConfig.parse(toml)
        #expect(config.name == "Demo")
        #expect(config.platforms == [.apple, .linux])
        #expect(config.verify.snapshotTolerance == 0.001)
        #expect(config.verify.themes == ["light", "dark"])
    }

    @Test func ignoresUnknownKeys() throws {
        let toml = """
        [project]
        name = "X"
        future_key = "whatever"
        """
        let config = try ProjectConfig.parse(toml)
        #expect(config.name == "X")
    }
}

@Suite("Lint")
struct LintTests {

    @Test func flagsForbiddenImport() {
        let source = """
        import Foundation
        import SwiftUI
        public struct Bad {}
        """
        let violations = Lint.scan(text: source, file: "Bad.swift")
        #expect(violations.count == 1)
        #expect(violations[0].module == "SwiftUI")
        #expect(violations[0].line == 2)
    }

    @Test func allowsCanImportGuard() {
        let source = """
        import Foundation
        #if canImport(SwiftUI)
        import SwiftUI
        #endif
        """
        #expect(Lint.scan(text: source, file: "OK.swift").isEmpty)
    }

    @Test func flagsUnconditionalAfterGuardedBlock() {
        let source = """
        #if canImport(AppKit)
        import AppKit
        #endif
        import UIKit
        """
        let violations = Lint.scan(text: source, file: "Bad.swift")
        #expect(violations.count == 1)
        #expect(violations[0].module == "UIKit")
    }

    @Test func flagsAttributedImport() {
        let source = "@_exported import Combine\n"
        let violations = Lint.scan(text: source, file: "Bad.swift")
        #expect(violations.count == 1)
        #expect(violations[0].module == "Combine")
    }

    @Test func cleanFoundationPasses() {
        let source = """
        import Foundation
        #if canImport(Darwin)
        import Darwin
        #endif
        public actor Store {}
        """
        #expect(Lint.scan(text: source, file: "Fine.swift").isEmpty)
    }
}

@Suite("Sync export scan")
struct SyncTests {

    @Test func findsExportedTypes() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("swiftport-sync-\(UUID().uuidString)")
        let sources = tmp.appendingPathComponent("Core/Sources/AppCore")
        try fm.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        public struct TaskItem: Sendable, Codable, SwiftPortExported {}
        public enum TaskPhase: String, SwiftPortExported { case a }
        extension TaskItem: SwiftPortExported {}
        struct InternalThing: SwiftPortExported {}
        """.write(to: sources.appendingPathComponent("Models.swift"),
                 atomically: true, encoding: .utf8)

        let exports = try Sync.scanExports(root: tmp)
        // TaskItem found via decl (extension adds a dup name — deduped).
        #expect(exports.contains { $0.name == "TaskItem" })
        #expect(exports.contains { $0.name == "TaskPhase" })
        #expect(exports.contains { $0.name == "InternalThing" })
        // Dedupe: TaskItem appears once despite two conformance sites.
        #expect(exports.filter { $0.name == "TaskItem" }.count == 1)
        try? fm.removeItem(at: tmp)
    }
}

@Suite("Template render")
struct TemplateTests {

    @Test func rendersAndSubstitutesTokens() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("swiftport-init-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }

        let dest = try Template.render(appName: "Task Flow", bundleIDPrefix: "com.example", to: tmp)

        // Config exists and parses.
        let config = try ProjectConfig.load(from: dest)
        #expect(config.name == "Task Flow")

        // Token substitution hit file contents.
        let readme = try String(contentsOf: dest.appendingPathComponent("README.md"), encoding: .utf8)
        #expect(readme.contains("Task Flow"))
        #expect(!readme.contains("__APP_NAME__"))

        // Token substitution hit file names.
        let linuxSources = dest.appendingPathComponent("Apps/Linux/Sources")
        let entries = try fm.contentsOfDirectory(atPath: linuxSources.path)
        #expect(entries.contains("Task_Flow"))

        // Key monorepo dirs exist.
        for dir in ["Core", "Apps/Apple", "Apps/Linux", "Apps/Android",
                    "Verification/Contracts", "Bridges", ".github/workflows"] {
            #expect(fm.fileExists(atPath: dest.appendingPathComponent(dir).path), "missing \(dir)")
        }

        // Core package manifest is valid SwiftPM.
        #expect(fm.fileExists(atPath: dest.appendingPathComponent("Core/Package.swift").path))

        // Android: bundle-id path dirs, Gradle files, substituted Kotlin.
        let pkgDir = dest.appendingPathComponent("Apps/Android/app/src/main/java/com/example/taskflow")
        #expect(fm.fileExists(atPath: pkgDir.appendingPathComponent("MainActivity.kt").path))
        #expect(fm.fileExists(atPath: dest.appendingPathComponent("Apps/Android/gradlew").path))
        #expect(fm.fileExists(atPath: dest.appendingPathComponent("Apps/Android/app/build.gradle.kts").path))
        let manifest = try String(
            contentsOf: dest.appendingPathComponent("Apps/Android/app/src/main/AndroidManifest.xml"),
            encoding: .utf8)
        #expect(manifest.contains("android:label=\"Task Flow\""))
        #expect(!manifest.contains("__APP_NAME__"))
        let activity = try String(contentsOf: pkgDir.appendingPathComponent("MainActivity.kt"), encoding: .utf8)
        #expect(activity.contains("package com.example.taskflow"))
    }

    @Test func rejectsExistingProject() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("swiftport-init-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        _ = try Template.render(appName: "One", bundleIDPrefix: "com.example", to: tmp)
        #expect(throws: (any Error).self) {
            try Template.render(appName: "Two", bundleIDPrefix: "com.example", to: tmp)
        }
    }

    @Test func validatesNames() {
        #expect(Template.validateAppName("TaskFlow"))
        #expect(Template.validateAppName("My App 2"))
        #expect(!Template.validateAppName(""))
        #expect(!Template.validateAppName("bad/name"))
        #expect(!Template.validateAppName("bad;rm -rf"))
    }
}

@Suite("Shell")
struct ShellTests {
    @Test func whichFindsGit() {
        #expect(Shell.which("git") != nil)
        #expect(Shell.which("definitely-not-a-real-tool-xyz") == nil)
    }

    @Test func runCapturesOutput() throws {
        let result = try Shell.run("echo", arguments: ["hello"])
        #expect(result.succeeded)
        #expect(result.stdout.contains("hello"))
    }
}
