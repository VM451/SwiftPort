import AppKit
import AppCore
import AppUI
import Foundation
import SwiftUI

/// Renders every contract scenario × theme to PNG for `swiftport verify`.
/// Usage: snapshot-runner --contracts-dir <dir> --output-dir <dir>
@main
struct SnapshotRunner {
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
            for theme in ["light", "dark"] {
                let model = await MainActor.run { TaskListViewModel(fixture: scenario) }
                let view = TaskListView(model: model)
                    .frame(width: 800, height: 600)
                    .environment(\.colorScheme, theme == "dark" ? .dark : .light)

                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let nsImage = renderer.nsImage,
                      let png = pngData(from: nsImage) else {
                    FileHandle.standardError.write("render failed: \(scenario.id)/\(theme)\n".data(using: .utf8)!)
                    continue
                }
                let file = output.appendingPathComponent("\(scenario.id)__\(theme).png")
                try png.write(to: file)
                rendered += 1
            }
        }
        print("snapshot-runner: rendered \(rendered) image(s) → \(output.path)")
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
