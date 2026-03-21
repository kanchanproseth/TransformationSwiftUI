// SPDX-License-Identifier: MIT
//
// AIConversionLayer.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: AI conversion configuration, request models, and scoring heuristics.
//

import Foundation

/// Configuration for the AI conversion layer.
public struct AIConversionConfig: Equatable {
    let enabled: Bool

    /// Minimum complexity score required before AI is considered.
    public let minimumComplexity: Int

    /// Forces AI conversion even when complexity is below the threshold.
    public let forceAI: Bool

    public init(enabled: Bool, minimumComplexity: Int, forceAI: Bool) {
        self.enabled = enabled
        self.minimumComplexity = minimumComplexity
        self.forceAI = forceAI
    }

    /// Default configuration when no environment values are provided.
    public static let `default` = AIConversionConfig(enabled: false, minimumComplexity: 12, forceAI: false)

    /// Builds a config from process environment variables.
    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AIConversionConfig {
        let enabled = parseBool(environment[Strings.aiEnabledKey]) ?? false
        let minimumComplexity = Int(environment[Strings.aiMinComplexityKey] ?? Strings.empty) ?? AIConversionConfig.default.minimumComplexity
        let forceAI = parseBool(environment[Strings.aiForceKey]) ?? false
        return AIConversionConfig(enabled: enabled, minimumComplexity: minimumComplexity, forceAI: forceAI)
    }

    private static func parseBool(_ raw: String?) -> Bool? {
        guard let raw else { return nil }
        switch raw.lowercased() {
        case Strings.boolTrueInt, Strings.boolTrue, Strings.boolYes, Strings.boolOn:
            return true
        case Strings.boolFalseInt, Strings.boolFalse, Strings.boolNo, Strings.boolOff:
            return false
        default:
            return nil
        }
    }

    private enum Strings {
        static let empty = ""
        static let aiEnabledKey = "TRANSFORMATION_SWIFTUI_AI_ENABLED"
        static let aiMinComplexityKey = "TRANSFORMATION_SWIFTUI_AI_MIN_COMPLEXITY"
        static let aiForceKey = "TRANSFORMATION_SWIFTUI_AI_FORCE"

        static let boolTrueInt = "1"
        static let boolTrue = "true"
        static let boolYes = "yes"
        static let boolOn = "on"
        static let boolFalseInt = "0"
        static let boolFalse = "false"
        static let boolNo = "no"
        static let boolOff = "off"
    }
}

/// Input snapshot for an AI conversion attempt.
public struct AIConversionRequest {
    /// The view controller model to convert.
    public let controller: ViewControllerModel

    /// Layout patterns inferred from constraints.
    public let patterns: [LayoutPattern]

    /// Modifier hints inferred from constraints.
    public let layoutHints: [String]

    /// Heuristic complexity score for the view controller.
    public let complexityScore: Int

    /// Optional override prompt for the AI provider.
    public let promptOverride: String?

    /// Retrieved context chunks used for RAG prompts.
    public let contextChunks: [CodeChunk]

    public init(
        controller: ViewControllerModel,
        patterns: [LayoutPattern],
        layoutHints: [String],
        complexityScore: Int,
        promptOverride: String?,
        contextChunks: [CodeChunk]
    ) {
        self.controller = controller
        self.patterns = patterns
        self.layoutHints = layoutHints
        self.complexityScore = complexityScore
        self.promptOverride = promptOverride
        self.contextChunks = contextChunks
    }
}

/// Protocol for AI-based conversion implementations.
public protocol AIConversionProvider {
    /// Converts a view controller model into SwiftUI code.
    func convert(_ request: AIConversionRequest) throws -> String?
}

/// Default provider used when no AI backend is wired up.
public struct NoOpAIConversionProvider: AIConversionProvider {
    public init() {}

    /// Returns nil to indicate no AI output is available.
    public func convert(_ request: AIConversionRequest) throws -> String? {
        nil
    }
}

/// Computes a heuristic complexity score to decide when to request AI assistance.
public struct AIConversionScorer {
    /// Produces a complexity score for a view controller model.
    public static func score(controller: ViewControllerModel) -> Int {
        let nodes = collectNodes(from: controller.rootElements)
        // Nodes with a resolved custom component name are not truly unknown — exclude from penalty
        let unknownCount = nodes.filter { $0.type == nil && $0.customComponentName == nil }.count
        let unsupportedCount = nodes.compactMap { $0.type }.filter { !UIKitElementType.supportedComponents.contains($0) }.count
        let depth = maxDepth(for: controller.rootElements, current: 1)
        let constraintCount = controller.constraints.count

        return nodes.count
            + constraintCount
            + (unknownCount * 3)
            + (unsupportedCount * 2)
            + (depth * 2)
    }

    private static func collectNodes(from roots: [UIElementNode]) -> [UIElementNode] {
        var result: [UIElementNode] = []
        for node in roots {
            result.append(node)
            result.append(contentsOf: collectNodes(from: node.children))
        }
        return result
    }

    private static func maxDepth(for nodes: [UIElementNode], current: Int) -> Int {
        guard !nodes.isEmpty else { return current }
        var maxValue = current
        for node in nodes {
            let childDepth = maxDepth(for: node.children, current: current + 1)
            maxValue = max(maxValue, childDepth)
        }
        return maxValue
    }
}

/// Routes conversion requests to the AI provider when heuristics indicate complexity.
public struct AIConversionRouter {
    /// The AI conversion provider to use when triggered.
    public let provider: AIConversionProvider

    /// The AI configuration used to decide when to route.
    public let config: AIConversionConfig

    public init(provider: AIConversionProvider, config: AIConversionConfig) {
        self.provider = provider
        self.config = config
    }

    /// Attempts AI generation based on configuration and heuristic complexity.
    public func generate(
        for controller: ViewControllerModel,
        patterns: [LayoutPattern],
        hints: [String],
        contextChunks: [CodeChunk]
    ) -> String? {
        guard config.enabled else { return nil }

        let complexity = AIConversionScorer.score(controller: controller)
        if !config.forceAI, complexity < config.minimumComplexity {
            return nil
        }

        let request = AIConversionRequest(
            controller: controller,
            patterns: patterns,
            layoutHints: hints,
            complexityScore: complexity,
            promptOverride: nil,
            contextChunks: contextChunks
        )

        return try? provider.convert(request)
    }
}
