// SPDX-License-Identifier: MIT
//
// PropertyExtractorVisitor.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Extracts stored properties from class declarations for SwiftUI parameter mapping.
//

import SwiftSyntax

/// Extracts stored properties from a class declaration for SwiftUI parameter mapping.
public class PropertyExtractorVisitor: SyntaxVisitor {

    /// Properties collected from the visited class.
    public private(set) var properties: [CustomComponentProperty] = []

    /// Value types whose UIKit controls naturally use bindings in SwiftUI.
    private static let bindablePropertyTypes: Set<String> = [
        Strings.typeString,
        Strings.typeBool,
        Strings.typeDouble,
        Strings.typeFloat,
        Strings.typeInt,
        Strings.typeCGFloat
    ]

    /// Creates a visitor configured for source-accurate parsing.
    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    /// Visits variable declarations and records eligible properties.
    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = parseAccessLevel(from: node.modifiers)

        // Skip private/fileprivate — they won't become parameters
        if accessLevel == .private || accessLevel == .fileprivate {
            return .visitChildren
        }

        for binding in node.bindings {
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }

            let name = identifier.identifier.text
            let typeName = binding.typeAnnotation?.type.description
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? Strings.typeAny
            let hasDefault = binding.initializer != nil

            // Skip UIKit view properties — these are internal subviews, not parameters
            if UIKitElementType.from(typeName: typeName) != nil {
                continue
            }

            let baseTypeName = typeName
                .replacingOccurrences(of: Strings.optionalMark, with: Strings.empty)
                .replacingOccurrences(of: Strings.implicitlyUnwrappedMark, with: Strings.empty)
            let isBindable = Self.bindablePropertyTypes.contains(baseTypeName)

            properties.append(CustomComponentProperty(
                name: name,
                typeName: typeName,
                hasDefaultValue: hasDefault,
                accessLevel: accessLevel,
                isBindable: isBindable
            ))
        }

        return .visitChildren
    }

    private func parseAccessLevel(from modifiers: DeclModifierListSyntax) -> PropertyAccessLevel {
        for modifier in modifiers {
            switch modifier.name.text {
            case Strings.accessPublic: return .public
            case Strings.accessPrivate: return .private
            case Strings.accessFilePrivate: return .fileprivate
            case Strings.accessInternal: return .internal
            default: continue
            }
        }
        return .internal
    }

    private enum Strings {
        static let empty = ""
        static let optionalMark = "?"
        static let implicitlyUnwrappedMark = "!"

        static let typeAny = "Any"
        static let typeString = "String"
        static let typeBool = "Bool"
        static let typeDouble = "Double"
        static let typeFloat = "Float"
        static let typeInt = "Int"
        static let typeCGFloat = "CGFloat"

        static let accessPublic = "public"
        static let accessPrivate = "private"
        static let accessFilePrivate = "fileprivate"
        static let accessInternal = "internal"
    }
}
