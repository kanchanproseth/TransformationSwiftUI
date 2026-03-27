// SPDX-License-Identifier: MIT
//
// ConversionSession.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Library-friendly async API for running the UIKit → SwiftUI conversion
//              pipeline with streaming progress events. Use this instead of the CLI
//              runner when embedding TransformationSwiftUI in an iOS or macOS app.
//

import Foundation

// MARK: - Public types

/// A single conversion progress snapshot streamed during a session.
public struct ConversionProgress: Sendable {
    /// Number of items fully converted so far.
    public let completed: Int

    /// Total items to convert (components + Swift controllers + IB controllers).
    public let total: Int

    /// 0.0 … 1.0 fraction.
    public var fraction: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }

    /// Integer percentage 0 … 100.
    public var percent: Int {
        total > 0 ? (completed * 100) / total : 0
    }

    /// Human-readable label for the item currently being processed.
    public let currentItem: String

    /// Source file being processed (may be nil for custom component phase).
    public let sourceFile: String?

    /// Output file written on disk (nil if write not yet attempted or failed).
    public let outputFile: String?
}

/// Events emitted by ``ConversionSession/start()``.
public enum ConversionEvent: Sendable {
    /// Emitted once scanning is complete and total count is known.
    case prepared(totalItems: Int)

    /// Emitted as each file begins converting.
    case progress(ConversionProgress)

    /// Emitted when an item is skipped (IB controller shadowed by Swift source).
    case skipped(ConversionProgress)

    /// A diagnostic / log line (mirrors what the CLI prints).
    case log(String)

    /// Emitted once for every successfully written output file.
    case fileWritten(outputPath: String, swiftUICode: String)

    /// Emitted when the entire session finishes successfully.
    case completed(outputDirectory: String, totalWritten: Int)

    /// Emitted when a non-recoverable error stops the session early.
    case failed(Error)
}

/// Errors thrown or emitted by a ``ConversionSession``.
public enum ConversionError: Error, Sendable {
    case outputDirectoryCreationFailed(String)
    case noSourceFilesFound(String)
}

// MARK: - ConversionSession

/// Runs the full UIKit → SwiftUI pipeline and streams ``ConversionEvent`` values.
///
/// **Usage:**
/// ```swift
/// let session = ConversionSession(projectPath: "/path/to/UIKitProject")
///
/// for await event in session.start() {
///     switch event {
///     case .progress(let p):
///         print("\(p.percent)% — \(p.currentItem)")
///     case .fileWritten(let path, _):
///         print("Wrote → \(path)")
///     case .completed(let dir, let count):
///         print("Done: \(count) files in \(dir)")
///     default:
///         break
///     }
/// }
/// ```
public struct ConversionSession: Sendable {
    /// Absolute path to the UIKit project root to convert.
    public let projectPath: String

    /// Whether to generate a full Xcode project scaffold after conversion.
    public let createProject: Bool

    /// Optional app name used when `createProject` is `true`.
    public let appName: String?

    /// Optional AI provider. Pass `nil` to use environment-variable config.
    public let aiProvider: (any AIConversionProvider)?

    /// AI conversion configuration. Defaults to reading from environment variables.
    public let aiConfig: AIConversionConfig

    /// RAG configuration. Defaults to reading from environment variables.
    public let ragConfig: RAGConfig

    public init(
        projectPath: String,
        createProject: Bool = false,
        appName: String? = nil,
        aiProvider: (any AIConversionProvider)? = nil,
        aiConfig: AIConversionConfig = .fromEnvironment(),
        ragConfig: RAGConfig = .fromEnvironment()
    ) {
        self.projectPath = projectPath
        self.createProject = createProject
        self.appName = appName
        self.aiProvider = aiProvider
        self.aiConfig = aiConfig
        self.ragConfig = ragConfig
    }

    /// Starts the conversion and returns an `AsyncStream` of ``ConversionEvent`` values.
    ///
    /// The stream is finite: it ends with either `.completed` or `.failed`.
    /// All work runs on a detached background task so the call site is never blocked.
    public func start() -> AsyncStream<ConversionEvent> {
        // Capture all properties as locals so the closure is Sendable
        let projectPath = self.projectPath
        let createProject = self.createProject
        let appName = self.appName
        let aiProvider = self.aiProvider
        let aiConfig = self.aiConfig
        let ragConfig = self.ragConfig

        return AsyncStream { continuation in
            Task.detached {
                await Self.run(
                    projectPath: projectPath,
                    createProject: createProject,
                    appName: appName,
                    aiProvider: aiProvider,
                    aiConfig: aiConfig,
                    ragConfig: ragConfig,
                    continuation: continuation
                )
                continuation.finish()
            }
        }
    }

    // MARK: - Internal pipeline

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private static func run(
        projectPath: String,
        createProject: Bool,
        appName: String?,
        aiProvider: (any AIConversionProvider)?,
        aiConfig: AIConversionConfig,
        ragConfig: RAGConfig,
        continuation: AsyncStream<ConversionEvent>.Continuation
    ) async {
        func log(_ message: String) { continuation.yield(.log(message)) }

        // ── Scan ─────────────────────────────────────────────────────────────
        let allSources = FileScanner.findAllSourceFiles(at: projectPath)
        let swiftFiles = allSources.swift
        let ibFiles = allSources.interfaceBuilder

        let outputDirectory = URL(fileURLWithPath: projectPath)
            .appendingPathComponent("SwiftUIMigrated")

        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            continuation.yield(.failed(ConversionError.outputDirectoryCreationFailed(outputDirectory.path)))
            return
        }

        // ── AI / RAG setup ───────────────────────────────────────────────────
        let resolvedProvider: (any AIConversionProvider)?
        if let explicit = aiProvider {
            resolvedProvider = explicit
        } else if aiConfig.enabled {
            resolvedProvider = CloudAIConversionProvider.fromEnvironment()
                ?? LocalAIConversionProvider.fromEnvironment()
        } else {
            resolvedProvider = nil
        }

        let ragIndex: RAGIndex?
        if resolvedProvider != nil && ragConfig.enabled {
            let index = RAGIndex(config: ragConfig)
            log("RAG indexing: building index for \(swiftFiles.count) files")
            let chunkCount = index.indexFiles(swiftFiles)
            log("RAG indexing: indexed \(chunkCount) chunks")
            ragIndex = index
        } else {
            ragIndex = nil
        }

        // ── Custom component registry ────────────────────────────────────────
        log("Analyzing custom components...")
        let componentRegistry = CustomComponentAnalyzer.buildRegistry(from: swiftFiles)

        // ── Pre-scan: count total work units ─────────────────────────────────
        let componentCount = componentRegistry.components.count
        let swiftControllerCount = swiftFiles.reduce(0) { acc, file in
            acc + ((try? SwiftParser.parseFile(file, componentRegistry: componentRegistry))?.count ?? 0)
        }
        let ibControllerCount = ibFiles.reduce(0) { acc, ibFile in
            acc + StoryboardParser.parseFile(ibFile, componentRegistry: componentRegistry).count
        }
        let total = componentCount + swiftControllerCount + ibControllerCount
        var completed = 0
        var totalWritten = 0

        continuation.yield(.prepared(totalItems: total))

        // ── Phase 1 & 2: Custom components ──────────────────────────────────
        if !componentRegistry.components.isEmpty {
            log("Discovered \(componentCount) custom component(s)")
            for (_, component) in componentRegistry.components.sorted(by: { $0.key < $1.key }) {
                completed += 1
                let label = component.name + "View.swift"
                let progress = ConversionProgress(
                    completed: completed,
                    total: total,
                    currentItem: label,
                    sourceFile: nil,
                    outputFile: nil
                )
                continuation.yield(.progress(progress))

                let swiftUIDefinition = CustomComponentDefinitionGenerator.generate(for: component)
                let outputFile = outputDirectory.appendingPathComponent(label)
                do {
                    try swiftUIDefinition.write(to: outputFile, atomically: true, encoding: .utf8)
                    totalWritten += 1
                    continuation.yield(.fileWritten(outputPath: outputFile.path, swiftUICode: swiftUIDefinition))
                } catch {
                    log("Failed to write SwiftUI file for custom component \(component.name)")
                }
            }
        } else {
            log("No custom components detected.")
        }

        // ── Phase 3: Swift source files ──────────────────────────────────────
        var allListNodes: [(vcName: String, node: UIElementNode)] = []
        var programmaticNavCalls: [(vcName: String, calls: [NavigationCall])] = []

        for file in swiftFiles {
            do {
                let controllers = try SwiftParser.parseFile(file, componentRegistry: componentRegistry)
                for controller in controllers {
                    completed += 1
                    let label = file.lastPathComponent + " → " + controller.name
                    let progress = ConversionProgress(
                        completed: completed,
                        total: total,
                        currentItem: label,
                        sourceFile: file.path,
                        outputFile: nil
                    )
                    continuation.yield(.progress(progress))
                    log(controller.name)

                    if !controller.navigationCalls.isEmpty {
                        programmaticNavCalls.append((vcName: controller.name, calls: controller.navigationCalls))
                    }
                    collectListNodes(from: controller.rootElements, vcName: controller.name, into: &allListNodes)

                    let swiftUICode = SwiftUICodeGenerator.generate(
                        for: controller,
                        aiProvider: resolvedProvider,
                        config: aiConfig,
                        ragIndex: ragIndex,
                        ragConfig: ragConfig,
                        componentRegistry: componentRegistry
                    )
                    let outputFile = outputDirectory.appendingPathComponent(controller.name + "View.swift")
                    do {
                        try swiftUICode.write(to: outputFile, atomically: true, encoding: .utf8)
                        totalWritten += 1
                        continuation.yield(.fileWritten(outputPath: outputFile.path, swiftUICode: swiftUICode))
                    } catch {
                        log("Failed to write SwiftUI file for \(controller.name)")
                    }
                }
            } catch {
                log("Failed to parse \(file.path)")
            }
        }

        // ── Track generated names for deduplication ──────────────────────────
        var allGeneratedNames: Set<String> = []
        for file in swiftFiles {
            if let controllers = try? SwiftParser.parseFile(file, componentRegistry: componentRegistry) {
                for controller in controllers { allGeneratedNames.insert(controller.name) }
            }
        }

        // ── Phase 4: Interface Builder files ─────────────────────────────────
        for ibFile in ibFiles {
            let controllers = StoryboardParser.parseFile(ibFile, componentRegistry: componentRegistry)
            for controller in controllers { allGeneratedNames.insert(controller.name) }

            for controller in controllers {
                completed += 1
                let label = ibFile.lastPathComponent + " → " + controller.name

                let isSkipped = allGeneratedNames
                    .subtracting(controllers.map(\.name))
                    .contains(controller.name)

                let progress = ConversionProgress(
                    completed: completed,
                    total: total,
                    currentItem: label,
                    sourceFile: ibFile.path,
                    outputFile: nil
                )

                if isSkipped {
                    continuation.yield(.skipped(progress))
                    continue
                }

                continuation.yield(.progress(progress))
                log(controller.name)

                let swiftUICode = SwiftUICodeGenerator.generate(
                    for: controller,
                    aiProvider: resolvedProvider,
                    config: aiConfig,
                    ragIndex: ragIndex,
                    ragConfig: ragConfig,
                    componentRegistry: componentRegistry
                )
                let outputFile = outputDirectory.appendingPathComponent(controller.name + "View.swift")
                do {
                    try swiftUICode.write(to: outputFile, atomically: true, encoding: .utf8)
                    totalWritten += 1
                    continuation.yield(.fileWritten(outputPath: outputFile.path, swiftUICode: swiftUICode))
                } catch {
                    log("Failed to write SwiftUI file for \(controller.name)")
                }
            }
        }

        // ── Phase 5: Navigation flow ─────────────────────────────────────────
        log("Detecting navigation flow...")
        var mergedGraph = NavigationGraph(initialViewControllerName: nil, edges: [], containers: [])
        for ibFile in ibFiles {
            if let graph = StoryboardParser.parseNavigationGraph(ibFile) {
                mergedGraph = mergedGraph.merging(graph)
            }
        }
        for (vcName, calls) in programmaticNavCalls {
            mergedGraph = mergedGraph.addingProgrammaticEdges(from: calls, sourceVC: vcName)
        }

        let hasNavigation = !mergedGraph.edges.isEmpty
            || !mergedGraph.containers.isEmpty
            || !allGeneratedNames.isEmpty
        if hasNavigation {
            let appFlowCode = NavigationFlowGenerator.generateAppFlowView(
                graph: mergedGraph,
                allVCNames: allGeneratedNames
            )
            let appFlowFile = outputDirectory.appendingPathComponent("AppFlowView.swift")
            do {
                try appFlowCode.write(to: appFlowFile, atomically: true, encoding: .utf8)
                totalWritten += 1
                continuation.yield(.fileWritten(outputPath: appFlowFile.path, swiftUICode: appFlowCode))
            } catch {
                log("Failed to write AppFlowView.swift")
            }
        }

        // ── Phase 6: Optional Xcode scaffold ─────────────────────────────────
        if createProject {
            log("Creating SwiftUI project scaffold...")
            ProjectScaffoldGenerator.generate(
                projectPath: projectPath,
                appName: appName,
                migratedDir: outputDirectory,
                graph: mergedGraph,
                allVCNames: allGeneratedNames,
                listNodes: allListNodes,
                output: { log($0) }
            )
        }

        continuation.yield(.completed(outputDirectory: outputDirectory.path, totalWritten: totalWritten))
    }

    // MARK: - Helpers

    private static func collectListNodes(
        from nodes: [UIElementNode],
        vcName: String,
        into accumulator: inout [(vcName: String, node: UIElementNode)]
    ) {
        for node in nodes {
            if node.type == .tableView || node.type == .collectionView {
                accumulator.append((vcName: vcName, node: node))
            }
            collectListNodes(from: node.children, vcName: vcName, into: &accumulator)
        }
    }
}
