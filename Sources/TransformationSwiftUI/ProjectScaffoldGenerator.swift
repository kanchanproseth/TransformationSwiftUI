// SPDX-License-Identifier: MIT
//
// ProjectScaffoldGenerator.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Generates a complete, runnable SwiftUI Xcode project scaffold
//              from the migrated view files and navigation graph.
//

import Foundation

/// Generates a new, runnable SwiftUI Xcode project scaffold from converted view files.
///
/// The generator writes:
/// - `<AppName>App.swift`      — `@main` entry point
/// - `ContentView.swift`       — thin wrapper that hosts `AppFlowView` or the initial VC view
/// - `Models/`                 — placeholder item models for detected tableView / collectionView
/// - `Views/CellViews/`        — stub cell views for each detected list cell type
/// - `Assets.xcassets/`        — minimal asset catalog directory marker
/// - An Xcode `.xcodeproj` package manifest comment in `README.md`
///
/// The output is placed in `<projectPath>/SwiftUIProject/<AppName>/`.
public struct ProjectScaffoldGenerator {

    // MARK: - Public API

    /// Creates a new SwiftUI project scaffold.
    ///
    /// - Parameters:
    ///   - projectPath: Root path of the source UIKit project being migrated.
    ///   - appName: The app name used for file and type naming. Defaults to the last
    ///     path component of `projectPath`.
    ///   - migratedDir: URL to the `SwiftUIMigrated` directory containing the generated view files.
    ///   - graph: The resolved navigation graph (may be empty for simple projects).
    ///   - allVCNames: All converted view controller names.
    ///   - listNodes: All tableView / collectionView nodes that need cell view stubs.
    ///   - output: Logging closure.
    /// - Returns: URL of the generated project root directory.
    @discardableResult
    public static func generate(
        projectPath: String,
        appName: String? = nil,
        migratedDir: URL,
        graph: NavigationGraph,
        allVCNames: Set<String>,
        listNodes: [(vcName: String, node: UIElementNode)],
        output: (String) -> Void = { print($0) }
    ) -> URL {
        let resolvedAppName = sanitize(appName ?? URL(fileURLWithPath: projectPath).lastPathComponent)
        let projectRoot = URL(fileURLWithPath: projectPath)
            .appendingPathComponent("SwiftUIProject")
            .appendingPathComponent(resolvedAppName)

        createDirectory(at: projectRoot, output: output)
        createDirectory(at: projectRoot.appendingPathComponent("Models"), output: output)
        createDirectory(at: projectRoot.appendingPathComponent("Views"), output: output)
        createDirectory(at: projectRoot.appendingPathComponent("Views/CellViews"), output: output)
        createDirectory(at: projectRoot.appendingPathComponent("Assets.xcassets"), output: output)

        // Write @main entry point
        writeFile(
            content: appEntryPoint(appName: resolvedAppName),
            to: projectRoot.appendingPathComponent("\(resolvedAppName)App.swift"),
            output: output
        )

        // Write ContentView.swift — wraps AppFlowView or first VC
        let entryViewName: String
        if let initial = graph.initialViewControllerName, allVCNames.contains(initial) {
            entryViewName = initial + "View"
        } else if let first = allVCNames.sorted().first {
            entryViewName = first + "View"
        } else {
            entryViewName = "AppFlowView"
        }
        writeFile(
            content: contentView(entryViewName: entryViewName),
            to: projectRoot.appendingPathComponent("ContentView.swift"),
            output: output
        )

        // Copy or reference migrated views (write import stubs listing them)
        writeFile(
            content: migratedViewsIndex(vcNames: allVCNames),
            to: projectRoot.appendingPathComponent("Views/MigratedViews.swift"),
            output: output
        )

        // Write item model stubs for each unique cell type
        var writtenModels: Set<String> = []
        for (_, node) in listNodes {
            let cellType = node.cellTypeName ?? "Item"
            if writtenModels.insert(cellType).inserted {
                writeFile(
                    content: itemModel(typeName: cellType),
                    to: projectRoot.appendingPathComponent("Models/\(cellType)Model.swift"),
                    output: output
                )
                writeFile(
                    content: cellView(typeName: cellType, isCollection: node.type == .collectionView),
                    to: projectRoot.appendingPathComponent("Views/CellViews/\(cellType)CellView.swift"),
                    output: output
                )
            }
        }

        // Minimal Assets.xcassets Contents.json
        writeFile(
            content: assetsContentsJSON(),
            to: projectRoot.appendingPathComponent("Assets.xcassets/Contents.json"),
            output: output
        )

        // Project README with Xcode instructions
        writeFile(
            content: projectReadme(appName: resolvedAppName, vcNames: allVCNames),
            to: projectRoot.appendingPathComponent("README.md"),
            output: output
        )

        output("Project scaffold created at: \(projectRoot.path)")
        return projectRoot
    }

    // MARK: - File Content Generators

    private static func appEntryPoint(appName: String) -> String {
        """
        import SwiftUI

        @main
        struct \(appName)App: App {
            var body: some Scene {
                WindowGroup {
                    ContentView()
                }
            }
        }
        """
    }

    private static func contentView(entryViewName: String) -> String {
        """
        import SwiftUI

        struct ContentView: View {
            var body: some View {
                \(entryViewName)()
            }
        }

        #Preview {
            ContentView()
        }
        """
    }

    private static func migratedViewsIndex(vcNames: Set<String>) -> String {
        let sorted = vcNames.sorted()
        let list = sorted.map { "//   - \($0)View.swift" }.joined(separator: "\n")
        return """
        // MigratedViews.swift
        // This file documents the migrated SwiftUI views generated from UIKit source.
        // Copy all *View.swift files from SwiftUIMigrated/ into this Views/ directory.
        //
        // Migrated views:
        \(list)
        //
        // Each view is a standalone SwiftUI struct conforming to View.
        // Navigation wiring is handled by AppFlowView.swift.

        import SwiftUI
        """
    }

    private static func itemModel(typeName: String) -> String {
        """
        import Foundation

        /// Auto-generated placeholder model for \(typeName) items.
        /// Replace with your actual data model.
        struct \(typeName)Model: Identifiable {
            let id: UUID
            let title: String
            let subtitle: String?

            init(id: UUID = UUID(), title: String, subtitle: String? = nil) {
                self.id = id
                self.title = title
                self.subtitle = subtitle
            }

            /// Sample data for SwiftUI previews.
            static let samples: [\(typeName)Model] = [
                \(typeName)Model(title: "Sample 1", subtitle: "Detail"),
                \(typeName)Model(title: "Sample 2", subtitle: "Detail"),
                \(typeName)Model(title: "Sample 3"),
            ]
        }
        """
    }

    private static func cellView(typeName: String, isCollection: Bool) -> String {
        if isCollection {
            return """
            import SwiftUI

            /// Auto-generated cell view for \(typeName) collection items.
            struct \(typeName)CellView: View {
                let item: \(typeName)Model

                var body: some View {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title)
                            .font(.headline)
                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            #Preview {
                \(typeName)CellView(item: \(typeName)Model.samples[0])
                    .padding()
            }
            """
        } else {
            return """
            import SwiftUI

            /// Auto-generated cell view for \(typeName) list rows.
            struct \(typeName)CellView: View {
                let item: \(typeName)Model

                var body: some View {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline)
                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            #Preview {
                List {
                    \(typeName)CellView(item: \(typeName)Model.samples[0])
                }
            }
            """
        }
    }

    private static func assetsContentsJSON() -> String {
        """
        {
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
    }

    private static func projectReadme(appName: String, vcNames: Set<String>) -> String {
        let sorted = vcNames.sorted()
        let viewList = sorted.map { "- `\($0)View.swift`" }.joined(separator: "\n")
        return """
        # \(appName) — Migrated SwiftUI Project

        This directory was auto-generated by **TransformationSwiftUI**.

        ## Getting Started

        1. Open Xcode and create a new **SwiftUI App** project named `\(appName)`.
        2. Copy all `*.swift` files from `SwiftUIMigrated/` into your new project.
        3. Copy the files from this `SwiftUIProject/\(appName)/` directory as well.
        4. Resolve any TODOs marked in the generated files.

        ## Migrated Screens

        \(viewList)

        ## Architecture Notes

        - `AppFlowView.swift` wires all navigation (NavigationStack, TabView, sheets, fullScreenCover).
        - Views that had `isHidden` / `alpha` mutations use `@State` booleans + `.opacity()` modifiers.
        - `IBAction` / target-action handlers are translated to button closures or `.onTapGesture`.
        - `tableView(_:didSelectRowAt:)` becomes `.onTapGesture` on list rows.
        - `collectionView(_:didSelectItemAt:)` becomes `.onTapGesture` on grid cells.

        ## Next Steps

        - Replace `ItemModel` placeholders with your actual data models and view models.
        - Wire up your networking / persistence layer to the `@State` / `@StateObject` bindings.
        - Review `// TODO:` comments for any patterns that required manual attention.
        """
    }

    // MARK: - Helpers

    private static func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let result = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character("_") }
        var s = String(result)
        if s.isEmpty { s = "MigratedApp" }
        if let first = s.first, first.isNumber { s = "App" + s }
        // PascalCase first letter
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    private static func createDirectory(at url: URL, output: (String) -> Void) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            output("Warning: could not create directory \(url.path): \(error)")
        }
    }

    private static func writeFile(content: String, to url: URL, output: (String) -> Void) {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            output("  Scaffold → \(url.path)")
        } catch {
            output("Warning: could not write \(url.path): \(error)")
        }
    }
}
