// SPDX-License-Identifier: MIT
//
// TransformationSwiftUIRunner.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Public facade that runs the full UIKit-to-SwiftUI conversion pipeline.
//

import Foundation

/// Public facade that runs the full UIKit-to-SwiftUI conversion pipeline.
public struct TransformationSwiftUIRunner {
    /// Runs the converter using CLI-style arguments.
    public static func run(
        arguments: [String],
        output: (String) -> Void = { print($0) }
    ) -> Int {
        if arguments.contains(Strings.aiSmokeTestFlag) {
            return runAISmokeTest(arguments: arguments, output: output)
        }

        guard arguments.count > 1 else {
            output(Strings.usageLine1)
            output(Strings.usageLine2)
            output(Strings.usageLine3)
            return 0
        }

        // Detect --create-project flag (creates a full Xcode-ready scaffold)
        let createProject = arguments.contains(Strings.createProjectFlag)
        // Detect optional --app-name <name>
        let appNameIndex = arguments.firstIndex(of: Strings.appNameFlag).map { $0 + 1 }
        let appName = appNameIndex.flatMap { $0 < arguments.count ? arguments[$0] : nil }

        return run(
            projectPath: arguments[1],
            createProject: createProject,
            appName: appName,
            aiProvider: nil,
            aiConfig: AIConversionConfig.fromEnvironment(),
            ragConfig: RAGConfig.fromEnvironment(),
            output: output
        )
    }

    /// Runs the converter for a project directory and returns a process exit code.
    public static func run(
        projectPath: String,
        createProject: Bool = false,
        appName: String? = nil,
        aiProvider: AIConversionProvider? = nil,
        aiConfig: AIConversionConfig = AIConversionConfig.fromEnvironment(),
        ragConfig: RAGConfig = RAGConfig.fromEnvironment(),
        output: (String) -> Void = { print($0) }
    ) -> Int {
        let allSources = FileScanner.findAllSourceFiles(at: projectPath)
        let files = allSources.swift
        let ibFiles = allSources.interfaceBuilder
        let outputDirectory = URL(fileURLWithPath: projectPath).appendingPathComponent(Strings.outputDirectoryName)

        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            output(Strings.failedToCreateOutputDirectoryPrefix + outputDirectory.path)
        }

        let resolvedProvider = aiProvider ?? (aiConfig.enabled ? Self.resolveProvider(output: output) : nil)
        let ragIndex: RAGIndex?
        if resolvedProvider != nil && ragConfig.enabled {
            let index = RAGIndex(config: ragConfig)
            output(Strings.ragIndexingBuildingPrefix + String(files.count) + Strings.ragIndexingFilesSuffix)
            let chunkCount = index.indexFiles(files)
            output(Strings.ragIndexingIndexedPrefix + String(chunkCount) + Strings.ragIndexingChunksSuffix)
            ragIndex = index
        } else {
            ragIndex = nil
        }

        output(Strings.analyzingCustomComponents)
        let componentRegistry = CustomComponentAnalyzer.buildRegistry(from: files)
        if !componentRegistry.components.isEmpty {
            output(Strings.discoveredComponentsPrefix + String(componentRegistry.components.count) + Strings.discoveredComponentsSuffix)
            for (_, component) in componentRegistry.components.sorted(by: { $0.key < $1.key }) {
                output(Strings.treePrefix + component.inheritanceChain.joined(separator: Strings.inheritanceSeparator))
                if component.drawingModel != nil {
                    output(Strings.treePrefix + Strings.customDrawingDetectedPrefix + component.name)
                }
                if !component.animations.isEmpty {
                    output(Strings.treePrefix + Strings.customAnimationsDetectedPrefix + component.name + Strings.openParen + String(component.animations.count) + Strings.closeParen)
                }
            }

            for (_, component) in componentRegistry.components.sorted(by: { $0.key < $1.key }) {
                let swiftUIDefinition = CustomComponentDefinitionGenerator.generate(for: component)
                let outputFile = outputDirectory.appendingPathComponent(component.name + Strings.viewFileSuffix)
                do {
                    try swiftUIDefinition.write(to: outputFile, atomically: true, encoding: .utf8)
                    output(Strings.customComponentSwiftUIPrefix + outputFile.path)
                } catch {
                    output(Strings.failedToWriteCustomComponentPrefix + component.name)
                }
            }
        } else {
            output(Strings.noCustomComponentsDetected)
        }

        // Collect list nodes (tableView/collectionView) for project scaffold cell stub generation
        var allListNodes: [(vcName: String, node: UIElementNode)] = []
        // Collect programmatic navigation calls from Swift source for graph enrichment
        var programmaticNavCalls: [(vcName: String, calls: [NavigationCall])] = []

        for file in files {
            do {
                let controllers = try SwiftParser.parseFile(file, componentRegistry: componentRegistry)

                for controller in controllers {
                    output(controller.name)
                    for element in controller.rootElements {
                        printNode(element, prefix: Strings.treePrefix, output: output)
                    }
                    if !controller.constraints.isEmpty {
                        output(Strings.constraintsHeader)
                        for constraint in controller.constraints {
                            output(Strings.treePrefix + formatConstraint(constraint))
                        }
                        printConstraintGraph(controller.constraints, output: output)

                        let patterns = LayoutPatternEngine.inferPatterns(from: controller.constraints)
                        if !patterns.isEmpty {
                            output(Strings.layoutSuggestionsHeader)
                            for pattern in patterns {
                                let elements = pattern.elements.joined(separator: Strings.elementsSeparator)
                                output(Strings.treePrefix + pattern.type.displayName + Strings.layoutSuggestionSeparator + elements)
                            }
                        }

                        let hints = LayoutPatternEngine.inferHints(from: controller.constraints)
                        if !hints.isEmpty {
                            output(Strings.layoutHintsHeader)
                            for hint in hints {
                                output(Strings.treePrefix + hint)
                            }
                        }
                    }

                    if !controller.animations.isEmpty {
                        output(Strings.animationsHeader)
                        for animation in controller.animations {
                            output(Strings.treePrefix + formatAnimation(animation))
                        }
                    }

                    // Log detected business logic
                    if !controller.controlActions.isEmpty {
                        output(Strings.businessLogicHeader)
                        for action in controller.controlActions {
                            output(Strings.treePrefix + action.kind.rawValue + Strings.colonSpace + action.handlerName + Strings.dashSpace + action.behaviorSummary)
                        }
                    }
                    if !controller.visibilityRules.isEmpty {
                        output(Strings.visibilityRulesHeader)
                        for rule in controller.visibilityRules {
                            output(Strings.treePrefix + rule.elementName + Strings.colonSpace + rule.kind.rawValue + (rule.condition.map { " (if \($0))" } ?? ""))
                        }
                    }

                    // Accumulate programmatic navigation for graph enrichment
                    if !controller.navigationCalls.isEmpty {
                        programmaticNavCalls.append((vcName: controller.name, calls: controller.navigationCalls))
                    }

                    // Collect list nodes for scaffold
                    collectListNodes(from: controller.rootElements, vcName: controller.name, into: &allListNodes)

                    let swiftUICode = SwiftUICodeGenerator.generate(
                        for: controller,
                        aiProvider: resolvedProvider,
                        config: aiConfig,
                        ragIndex: ragIndex,
                        ragConfig: ragConfig,
                        componentRegistry: componentRegistry
                    )
                    let outputFile = outputDirectory.appendingPathComponent(controller.name + Strings.viewFileSuffix)
                    do {
                        try swiftUICode.write(to: outputFile, atomically: true, encoding: .utf8)
                        output(Strings.swiftUIOutputPrefix + outputFile.path)
                    } catch {
                        output(Strings.failedToWriteSwiftUIPrefix + controller.name)
                    }
                    output(swiftUICode)
                }
            } catch {
                output(Strings.failedToParsePrefix + file.path)
            }
        }

        // Track all generated VC names for navigation injection
        var allGeneratedNames: Set<String> = []
        for file in files {
            if let controllers = try? SwiftParser.parseFile(file, componentRegistry: componentRegistry) {
                for controller in controllers { allGeneratedNames.insert(controller.name) }
            }
        }

        if !ibFiles.isEmpty {
            output(Strings.parsingInterfaceBuilderPrefix + String(ibFiles.count) + Strings.interfaceBuilderSuffix)

            for ibFile in ibFiles {
                let controllers = StoryboardParser.parseFile(ibFile, componentRegistry: componentRegistry)
                output(Strings.ibFilePrefix + ibFile.lastPathComponent + Strings.ibFileInfix + String(controllers.count) + Strings.ibFileSuffix)

                for controller in controllers {
                    allGeneratedNames.insert(controller.name)
                }

                for controller in controllers {
                    guard !allGeneratedNames.subtracting(controllers.map(\.name)).contains(controller.name) else {
                        output(Strings.skipSwiftSourcePrefix + controller.name + Strings.skipSwiftSourceSuffix)
                        continue
                    }

                    output(controller.name)
                    for element in controller.rootElements {
                        printNode(element, prefix: Strings.treePrefix, output: output)
                    }
                    if !controller.constraints.isEmpty {
                        output(Strings.constraintsHeader)
                        for constraint in controller.constraints {
                            output(Strings.treePrefix + formatConstraint(constraint))
                        }
                    }

                    let swiftUICode = SwiftUICodeGenerator.generate(
                        for: controller,
                        aiProvider: resolvedProvider,
                        config: aiConfig,
                        ragIndex: ragIndex,
                        ragConfig: ragConfig,
                        componentRegistry: componentRegistry
                    )
                    let outputFile = outputDirectory.appendingPathComponent(controller.name + Strings.viewFileSuffix)
                    do {
                        try swiftUICode.write(to: outputFile, atomically: true, encoding: .utf8)
                        output(Strings.swiftUIIBOutputPrefix + outputFile.path)
                    } catch {
                        output(Strings.failedToWriteSwiftUIPrefix + controller.name)
                    }
                    output(swiftUICode)
                }
            }
        }

        // Phase 5: Navigation flow detection and AppFlowView generation
        output(Strings.detectingNavigationFlow)

        // Build a merged navigation graph across all storyboard files
        var mergedGraph = NavigationGraph(initialViewControllerName: nil, edges: [], containers: [])
        for ibFile in ibFiles {
            if let graph = StoryboardParser.parseNavigationGraph(ibFile) {
                mergedGraph = mergedGraph.merging(graph)
                output(Strings.treePrefix + ibFile.lastPathComponent + Strings.navigationGraphSuffix
                       + String(graph.edges.count) + Strings.edgesSuffix
                       + String(graph.containers.count) + Strings.containersSuffix)
            }
        }

        // Enrich the graph with programmatic navigation calls found in Swift source
        for (vcName, calls) in programmaticNavCalls {
            mergedGraph = mergedGraph.addingProgrammaticEdges(from: calls, sourceVC: vcName)
        }
        if !programmaticNavCalls.isEmpty {
            output(Strings.programmaticNavPrefix + String(programmaticNavCalls.count) + Strings.programmaticNavSuffix)
        }

        let hasNavigation = !mergedGraph.edges.isEmpty || !mergedGraph.containers.isEmpty || !allGeneratedNames.isEmpty
        if hasNavigation {
            let appFlowCode = NavigationFlowGenerator.generateAppFlowView(
                graph: mergedGraph,
                allVCNames: allGeneratedNames
            )
            let appFlowFile = outputDirectory.appendingPathComponent(Strings.appFlowFileName)
            do {
                try appFlowCode.write(to: appFlowFile, atomically: true, encoding: .utf8)
                output(Strings.appFlowWrittenPrefix + appFlowFile.path)
            } catch {
                output(Strings.appFlowWriteFailed)
            }
            output(appFlowCode)
        } else {
            output(Strings.noNavigationDetected)
        }

        // Phase 6: Optional full Xcode project scaffold generation
        if createProject {
            output(Strings.creatingProjectScaffold)
            ProjectScaffoldGenerator.generate(
                projectPath: projectPath,
                appName: appName,
                migratedDir: outputDirectory,
                graph: mergedGraph,
                allVCNames: allGeneratedNames,
                listNodes: allListNodes,
                output: output
            )
        }

        return 0
    }

    private static func runAISmokeTest(arguments: [String], output: (String) -> Void) -> Int {
        let promptIndex = arguments.firstIndex(of: Strings.aiSmokeTestFlag).map { $0 + 1 }
        let prompt = promptIndex.flatMap { $0 < arguments.count ? arguments[$0] : nil } ?? Strings.defaultAISmokePrompt
        let outputIndex = arguments.firstIndex(of: Strings.aiSmokeOutputFlag).map { $0 + 1 }
        let outputPath = outputIndex.flatMap { $0 < arguments.count ? arguments[$0] : nil }

        let provider: AIConversionProvider? = CloudAIConversionProvider.fromEnvironment()
            ?? LocalAIConversionProvider.fromEnvironment()
        guard let provider else {
            output(Strings.aiSmokeTestEndpointMissing)
            return 1
        }

        let controller = ViewControllerModel(name: Strings.aiSmokeTestControllerName, rootElements: [], constraints: [])
        let request = AIConversionRequest(
            controller: controller,
            patterns: [],
            layoutHints: [],
            complexityScore: 0,
            promptOverride: prompt,
            contextChunks: []
        )

        do {
            let response = try provider.convert(request)
            output(Strings.aiSmokeTestPromptPrefix + prompt)
            if let response, !response.isEmpty {
                output(Strings.aiSmokeTestResponsePrefix + response)
                if let outputPath {
                    do {
                        try response.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
                        output(Strings.aiSmokeTestWrotePrefix + outputPath)
                    } catch {
                        output(Strings.aiSmokeTestWriteFailedPrefix + outputPath + Strings.aiSmokeTestWriteFailedSuffix + String(describing: error))
                    }
                }
            } else {
                output(Strings.aiSmokeTestEmptyResponse)
            }
        } catch {
            output(Strings.aiSmokeTestFailedPrefix + String(describing: error))
            return 1
        }

        return 0
    }

    private static func printNode(_ node: UIElementNode, prefix: String = Strings.empty, output: (String) -> Void) {
        output(prefix + node.name)
        for child in node.children {
            printNode(child, prefix: prefix + Strings.treePrefix, output: output)
        }
    }

    private static func formatConstraint(_ constraint: LayoutConstraint) -> String {
        let first = constraint.firstItem + Strings.dot + constraint.firstAttribute.rawValue
        if let secondItem = constraint.secondItem, let secondAttribute = constraint.secondAttribute {
            let second = secondItem + Strings.dot + secondAttribute.rawValue
            if let constant = constraint.constant {
                return first + Strings.constraintEqualsSeparator + second + Strings.constraintPlusSeparator + String(constant)
            }
            return first + Strings.constraintEqualsSeparator + second
        }
        if let constant = constraint.constant {
            return first + Strings.constraintEqualsSeparator + String(constant)
        }
        return first
    }

    private static func isVertical(_ attribute: ConstraintAttribute) -> Bool {
        switch attribute {
        case .top, .bottom, .centerY:
            return true
        default:
            return false
        }
    }

    private static func isHorizontal(_ attribute: ConstraintAttribute) -> Bool {
        switch attribute {
        case .leading, .trailing, .left, .right, .centerX:
            return true
        default:
            return false
        }
    }

    private static func printConstraintGraph(_ constraints: [LayoutConstraint], output: (String) -> Void) {
        let edges = constraints.compactMap { constraint -> (String, String, String)? in
            guard let secondItem = constraint.secondItem else { return nil }
            let direction: String
            if isVertical(constraint.firstAttribute) || isVertical(constraint.secondAttribute ?? .unknown) {
                direction = Strings.directionVertical
            } else if isHorizontal(constraint.firstAttribute) || isHorizontal(constraint.secondAttribute ?? .unknown) {
                direction = Strings.directionHorizontal
            } else {
                direction = Strings.directionOther
            }
            return (secondItem, constraint.firstItem, direction)
        }

        if edges.isEmpty {
            return
        }

        output(Strings.constraintsGraphHeader)
        for edge in edges {
            output(Strings.treePrefix + edge.0 + Strings.constraintGraphArrow + edge.1 + Strings.constraintGraphDirectionOpen + edge.2 + Strings.constraintGraphDirectionClose)
        }
    }

    /// Resolves the best available AI provider from environment variables.
    /// Cloud providers (Anthropic, OpenAI, Perplexity) take priority over local.
    private static func resolveProvider(output: (String) -> Void) -> AIConversionProvider? {
        if let cloud = CloudAIConversionProvider.fromEnvironment() {
            output(Strings.usingCloudProviderPrefix + cloud.formatName + Strings.closeParen)
            return cloud
        }
        if let local = LocalAIConversionProvider.fromEnvironment() {
            output(Strings.usingLocalProvider)
            return local
        }
        return nil
    }

    private static func formatAnimation(_ animation: AnimationModel) -> String {
        let kind: String
        switch animation.kind {
        case .uiViewAnimate:         kind = Strings.animKindUIViewAnimate
        case .uiViewSpringAnimate:   kind = Strings.animKindUIViewSpring
        case .uiViewTransition:      kind = Strings.animKindUIViewTransition
        case .propertyAnimator:      kind = Strings.animKindPropertyAnimator
        case .caBasicAnimation:      kind = Strings.animKindCABasic
        case .caKeyframeAnimation:   kind = Strings.animKindCAKeyframe
        case .caSpringAnimation:     kind = Strings.animKindCASpring
        case .caAnimationGroup:      kind = Strings.animKindCAGroup
        }

        let duration = animation.duration.map { Strings.animDurationPrefix + String($0) } ?? Strings.empty

        let ctx: String
        switch animation.context {
        case .viewDidAppear:         ctx = "viewDidAppear"
        case .viewWillAppear:        ctx = "viewWillAppear"
        case .viewDidLoad:           ctx = "viewDidLoad"
        case .actionMethod(let n):   ctx = n
        case .other(let n):          ctx = n
        }

        let changes = animation.propertyChanges.map { change -> String in
            switch change {
            case .alpha(let v):         return "alpha(\(v))"
            case .isHidden(let v):      return "isHidden(\(v))"
            case .backgroundColor(let c): return "bgColor(\(c))"
            case .frame:                return "frame"
            case .transform(let t):
                switch t {
                case .scale(let x, let y):       return "scale(\(x),\(y))"
                case .rotation(let r):           return "rotation(\(r))"
                case .translation(let x, let y): return "translation(\(x),\(y))"
                case .identity:                  return "identity"
                }
            }
        }.joined(separator: Strings.animChangesSeparator)

        return kind + duration + Strings.animContextPrefix + ctx + Strings.animChangesPrefix + changes + Strings.animChangesSuffix
    }

    private enum Strings {
        static let empty = ""
        static let dot = "."
        static let outputDirectoryName = "SwiftUIMigrated"
        static let viewFileSuffix = "View.swift"
        static let inheritanceSeparator = " : "
        static let elementsSeparator = ", "
        static let layoutSuggestionSeparator = ": "
        static let treePrefix = " └── "
        static let constraintEqualsSeparator = " = "
        static let constraintPlusSeparator = " + "
        static let constraintGraphArrow = " → "
        static let constraintGraphDirectionOpen = " ("
        static let constraintGraphDirectionClose = ")"

        static let aiSmokeTestFlag = "--ai-smoke-test"
        static let aiSmokeOutputFlag = "--ai-smoke-output"
        static let defaultAISmokePrompt = "Convert UIButton to SwiftUI."
        static let aiSmokeTestControllerName = "SmokeTest"

        static let usageLine1 = "Usage: TransformationSwiftUICLI <project-path>"
        static let usageLine2 = "       TransformationSwiftUICLI --ai-smoke-test \"Your prompt here\" [--ai-smoke-output /path/to/output.txt]"
        static let usageLine3 = "       TransformationSwiftUICLI <project-path> [--create-project] [--app-name <AppName>]"

        static let createProjectFlag = "--create-project"
        static let appNameFlag = "--app-name"

        static let failedToCreateOutputDirectoryPrefix = "Failed to create output directory at "
        static let ragIndexingBuildingPrefix = "RAG indexing: building index for "
        static let ragIndexingFilesSuffix = " files"
        static let ragIndexingIndexedPrefix = "RAG indexing: indexed "
        static let ragIndexingChunksSuffix = " chunks"
        static let analyzingCustomComponents = "Analyzing custom components..."
        static let discoveredComponentsPrefix = "Discovered "
        static let discoveredComponentsSuffix = " custom component(s):"
        static let customComponentSwiftUIPrefix = "Custom component SwiftUI → "
        static let failedToWriteCustomComponentPrefix = "Failed to write SwiftUI file for custom component "
        static let noCustomComponentsDetected = "No custom components detected."
        static let constraintsHeader = "Constraints"
        static let layoutSuggestionsHeader = "Layout Suggestions"
        static let layoutHintsHeader = "Layout Hints"
        static let swiftUIOutputPrefix = "SwiftUI → "
        static let swiftUIIBOutputPrefix = "SwiftUI (IB) → "
        static let failedToWriteSwiftUIPrefix = "Failed to write SwiftUI file for "
        static let failedToParsePrefix = "Failed to parse "
        static let parsingInterfaceBuilderPrefix = "Parsing "
        static let interfaceBuilderSuffix = " Interface Builder file(s)..."
        static let ibFilePrefix = "IB file: "
        static let ibFileInfix = " → "
        static let ibFileSuffix = " view controller(s)"
        static let skipSwiftSourcePrefix = "  Skipping "
        static let skipSwiftSourceSuffix = " (already generated from Swift source)"

        static let usingCloudProviderPrefix = "AI provider: cloud ("
        static let usingLocalProvider = "AI provider: local endpoint."
        static let aiSmokeTestEndpointMissing = "AI smoke test failed: no AI provider configured. Set TRANSFORMATION_SWIFTUI_ANTHROPIC_API_KEY, TRANSFORMATION_SWIFTUI_OPENAI_API_KEY, TRANSFORMATION_SWIFTUI_PERPLEXITY_API_KEY, or TRANSFORMATION_SWIFTUI_AI_ENDPOINT."
        static let aiSmokeTestPromptPrefix = "AI smoke test prompt: "
        static let aiSmokeTestResponsePrefix = "AI smoke test response:\n"
        static let aiSmokeTestWrotePrefix = "AI smoke test wrote response to "
        static let aiSmokeTestWriteFailedPrefix = "AI smoke test failed to write response to "
        static let aiSmokeTestWriteFailedSuffix = ": "
        static let aiSmokeTestEmptyResponse = "AI smoke test returned empty response."
        static let aiSmokeTestFailedPrefix = "AI smoke test failed with error: "

        static let constraintsGraphHeader = "Constraints Graph"
        static let directionVertical = "vertical"
        static let directionHorizontal = "horizontal"
        static let directionOther = "other"

        static let animationsHeader = "Animations"
        static let customDrawingDetectedPrefix = "[drawing] "
        static let customAnimationsDetectedPrefix = "[animations] "
        static let openParen = " ("
        static let closeParen = ")"
        static let animKindUIViewAnimate = "UIView.animate"
        static let animKindUIViewSpring = "UIView.spring"
        static let animKindUIViewTransition = "UIView.transition"
        static let animKindPropertyAnimator = "UIViewPropertyAnimator"
        static let animKindCABasic = "CABasicAnimation"
        static let animKindCAKeyframe = "CAKeyframeAnimation"
        static let animKindCASpring = "CASpringAnimation"
        static let animKindCAGroup = "CAAnimationGroup"
        static let animDurationPrefix = " duration="
        static let animContextPrefix = " ctx="
        static let animChangesPrefix = " changes=["
        static let animChangesSuffix = "]"
        static let animChangesSeparator = ", "

        static let detectingNavigationFlow = "Detecting navigation flow..."
        static let navigationGraphSuffix = " → graph: "
        static let edgesSuffix = " edge(s), "
        static let containersSuffix = " container(s)"
        static let appFlowFileName = "AppFlowView.swift"
        static let appFlowWrittenPrefix = "Navigation flow → "
        static let appFlowWriteFailed = "Failed to write AppFlowView.swift"
        static let noNavigationDetected = "No navigation connections detected."

        static let businessLogicHeader = "Business Logic"
        static let visibilityRulesHeader = "Visibility Rules"
        static let colonSpace = ": "
        static let dashSpace = " — "

        static let programmaticNavPrefix = "Programmatic navigation: enriched graph from "
        static let programmaticNavSuffix = " view controller(s)"

        static let creatingProjectScaffold = "Creating SwiftUI project scaffold..."
    }

    /// Recursively collects all tableView / collectionView nodes from an element tree.
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
