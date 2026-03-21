// SPDX-License-Identifier: MIT
//
// AIPromptBuilder.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Shared prompt construction for AI conversion providers.
//

import Foundation

/// Builds structured prompts for AI-based UIKit-to-SwiftUI conversion.
/// Used by both local and cloud AI providers.
public struct AIPromptBuilder {

    /// System prompt instructing the model how to perform UIKit-to-SwiftUI conversion.
    public static var systemPrompt: String {
        Strings.systemPrompt
    }

    /// Builds the user prompt from an `AIConversionRequest`.
    /// Returns `request.promptOverride` directly when one is present.
    public static func buildUserPrompt(from request: AIConversionRequest) -> String {
        if let override = request.promptOverride, !override.isEmpty {
            return override
        }

        let rootNames = request.controller.rootElements.map { $0.name }
            .joined(separator: Strings.commaSpace)
        let hintText = request.layoutHints.joined(separator: Strings.newline)
        let patternText = request.patterns.map {
            $0.type.displayName + Strings.patternSeparator + $0.elements.joined(separator: Strings.commaSpace)
        }.joined(separator: Strings.newline)
        let contextText = formatContext(request.contextChunks)

        return """
        Convert this UIKit view controller to SwiftUI.
        Controller: \(request.controller.name)
        Root elements: \(rootNames)
        Complexity score: \(request.complexityScore)
        Layout patterns:
        \(patternText)
        Layout hints:
        \(hintText)
        Related code snippets:
        \(contextText)
        """
    }

    // MARK: - Private helpers

    private static func formatContext(_ chunks: [CodeChunk]) -> String {
        guard !chunks.isEmpty else { return Strings.noneText }
        let entries = chunks.prefix(Strings.maxContextChunks).map { chunk -> String in
            let trimmed = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet: String
            if trimmed.count > Strings.maxContextCharacters {
                snippet = String(trimmed.prefix(Strings.maxContextCharacters)) + Strings.ellipsis
            } else {
                snippet = trimmed
            }
            return Strings.contextOpen + chunk.filePath + Strings.contextColon
                + String(chunk.startLine) + Strings.contextDash
                + String(chunk.endLine) + Strings.contextClose
                + Strings.newline + snippet
        }
        return entries.joined(separator: Strings.contextEntrySeparator)
    }

    // MARK: - String constants

    private enum Strings {
        static let systemPrompt = "You are an expert iOS developer specialising in UIKit-to-SwiftUI migration. Given a description of a UIKit view controller, produce a complete, compilable SwiftUI View struct. Use idiomatic SwiftUI: @State for local state, @Binding for passed-in mutable state, VStack/HStack/ZStack for layout, and .padding/.frame modifiers for spacing. Respond with Swift source code only — no markdown fences, no explanations."

        static let noneText = "None"
        static let ellipsis = "..."
        static let newline = "\n"
        static let commaSpace = ", "
        static let patternSeparator = ": "

        static let maxContextChunks = 3
        static let maxContextCharacters = 400

        static let contextOpen = "["
        static let contextColon = ":"
        static let contextDash = "-"
        static let contextClose = "]"
        static let contextEntrySeparator = "\n---\n"
    }
}
