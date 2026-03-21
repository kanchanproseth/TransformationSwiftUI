// SPDX-License-Identifier: MIT
//
// UIKitComponentVisitor.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: SwiftSyntax visitor that collects referenced UIKit component types from variable declarations.
//
import SwiftSyntax

/// Collects UIKit element types referenced in variable declarations.
public class UIKitComponentVisitor: SyntaxVisitor {

    /// Discovered UIKit component types.
    public var components: [UIKitElementType] = []

    /// Supported components considered by the analyzer.
    public let supportedComponents = UIKitElementType.supportedComponents

    /// Creates a visitor configured for source-accurate parsing.
    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    /// Visits variable declarations and records matching UIKit types.
    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {

        for binding in node.bindings {

            let typeName = binding.typeAnnotation?.type.description
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let inferredType = typeName ?? inferredTypeName(from: binding.initializer?.value)

            if let elementType = UIKitElementType.from(typeName: inferredType),
               supportedComponents.contains(elementType) {
                components.append(elementType)
            }

        }

        return .visitChildren
    }

    private func inferredTypeName(from expression: ExprSyntax?) -> String? {
        guard let expression else { return nil }
        if let call = expression.as(FunctionCallExprSyntax.self) {
            if let identifier = call.calledExpression.as(DeclReferenceExprSyntax.self) {
                return identifier.baseName.text
            }
            if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
                return member.declName.baseName.text
            }
        }
        return nil
    }

}
