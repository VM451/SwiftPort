import AppKit
import AppCore
import AppUI
import Foundation
import SwiftUI

/// Renders every contract scenario across the verification matrix to PNG
/// for `swiftport verify`.
///
/// Matrix (PRD FR-7):
///   * themes:        light, dark
///   * viewports:     compact 480×360, standard 800×600, expanded 1200×800
///   * stress variants (standard viewport only):
///       rtl       — right-to-left layout direction
///       de        — German locale (long localized strings)
///       bold      — bold legibility weight (accessibility text stress)
///     NOTE: macOS ImageRenderer ignores `dynamicTypeSize`/`font` env keys,
///     so Dynamic Type coverage lands with the iOS capture path instead.
///
/// Usage: snapshot-runner --contracts-dir <dir> --output-dir <dir>
@main
struct SnapshotRunner {
    struct Viewport: Sendable {
        let name: String
        let size: CGSize
    }

    static let viewports = [
        Viewport(name: "compact", size: CGSize(width: 480, height: 360)),
        Viewport(name: "standard", size: CGSize(width: 800, height: 600)),
        Viewport(name: "expanded", size: CGSize(width: 1200, height: 800)),
    ]
    static let themes = ["light", "dark"]
    static let stressVariants = ["rtl", "de", "bold"]

    static func main() async throws {
        var contractsDir: String?
        var outputDir: String?
        var args = CommandLine.arguments.dropFirst().makeIterator()
        while let arg = args.next() {
            switch arg {
            case "--contracts-dir": contractsDir = args.next()
            case "--output-dir": outputDir = args.next()
            default: break
            }
        }
        guard let contractsDir, let outputDir else {
            FileHandle.standardError.write("usage: snapshot-runner --contracts-dir <dir> --output-dir <dir>\n".data(using: .utf8)!)
            Foundation.exit(2)
        }

        let scenarios = try ContractScenario.loadAll(from: URL(fileURLWithPath: contractsDir))
        guard !scenarios.isEmpty else {
            FileHandle.standardError.write("no contract scenarios found in \(contractsDir)\n".data(using: .utf8)!)
            Foundation.exit(1)
        }

        let output = URL(fileURLWithPath: outputDir)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        var rendered = 0
        for scenario in scenarios {
            let model = await MainActor.run { TaskListViewModel(fixture: scenario) }

            // Base grid: every theme × every viewport.
            for theme in themes {
                for viewport in viewports {
                    if await render(model: model, scenario: scenario, theme: theme,
                                    viewport: viewport, variant: nil, to: output) {
                        rendered += 1
                    }
                }
            }
            // Stress variants on the standard viewport.
            let standard = viewports[1]
            for theme in themes {
                for variant in stressVariants {
                    if await render(model: model, scenario: scenario, theme: theme,
                                    viewport: standard, variant: variant, to: output) {
                        rendered += 1
                    }
                }
            }
        }
        print("snapshot-runner: rendered \(rendered) image(s) → \(output.path)")
    }

    @MainActor
    static func render(
        model: TaskListViewModel,
        scenario: ContractScenario,
        theme: String,
        viewport: Viewport,
        variant: String?,
        to output: URL
    ) async -> Bool {
        var view = AnyView(
            TaskListView(model: model)
                .frame(width: viewport.size.width, height: viewport.size.height)
                .environment(\.colorScheme, theme == "dark" ? .dark : .light)
        )
        switch variant {
        case "rtl":
            view = AnyView(view.environment(\.layoutDirection, .rightToLeft))
        case "de":
            view = AnyView(view.environment(\.locale, Locale(identifier: "de_DE")))
        case "bold":
            view = AnyView(view.environment(\.legibilityWeight, .bold))
        default:
            break
        }

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let tag = variant.map { "__\($0)" } ?? ""
        let name = "\(scenario.id)__\(theme)__\(viewport.name)\(tag)"
        guard let nsImage = renderer.nsImage,
              let png = pngData(from: nsImage) else {
            FileHandle.standardError.write("render failed: \(name)\n".data(using: .utf8)!)
            return false
        }
        do {
            try png.write(to: output.appendingPathComponent("\(name).png"))
            return true
        } catch {
            FileHandle.standardError.write("write failed: \(name): \(error)\n".data(using: .utf8)!)
            return false
        }
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
