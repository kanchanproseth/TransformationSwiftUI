// SPDX-License-Identifier: MIT
//
// AutoLayoutVisitor.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: SwiftSyntax visitor that extracts Auto Layout constraint information
// from UIKit-style anchor-based calls into a normalized representation.
//

import SwiftSyntax

/// Visits SwiftSyntax trees to collect Auto Layout constraints.
public class AutoLayoutVisitor: SyntaxVisitor {

    /// Collected constraints discovered during traversal.
    public private(set) var constraints: [LayoutConstraint] = []

    /// Creates a visitor configured for source-accurate parsing.
    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    /// Captures anchor-based `constraint(...)` calls into LayoutConstraint models.
    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            return .visitChildren
        }

        if memberAccess.declName.baseName.text != Strings.constraintMember {
            return .visitChildren
        }

        guard let anchorAccess = memberAccess.base?.as(MemberAccessExprSyntax.self) else {
            return .visitChildren
        }

        let firstItemName = normalizedItemName(from: anchorAccess.base)
        let firstAttribute = attributeFromAnchorName(anchorAccess.declName.baseName.text)

        var secondItemName: String?
        var secondAttribute: ConstraintAttribute?
        var constantValue: Double?

        for argument in node.arguments {
            let label = argument.label?.text ?? Strings.empty
            if label == Strings.equalToLabel {
                if let secondAnchor = argument.expression.as(MemberAccessExprSyntax.self) {
                    secondItemName = normalizedItemName(from: secondAnchor.base)
                    secondAttribute = attributeFromAnchorName(secondAnchor.declName.baseName.text)
                }
            } else if label == Strings.equalToConstantLabel {
                constantValue = parseDouble(argument.expression.description)
            } else if label == Strings.constantLabel {
                constantValue = parseDouble(argument.expression.description)
            }
        }

        let constraint = LayoutConstraint(
            firstItem: firstItemName,
            firstAttribute: firstAttribute,
            relation: .equal,
            secondItem: secondItemName,
            secondAttribute: secondAttribute,
            constant: constantValue
        )
        constraints.append(constraint)

        return .visitChildren
    }

    private func normalizedItemName(from expr: ExprSyntax?) -> String {
        guard let expr else { return Strings.empty }
        let trimmed = expr.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(Strings.selfPrefix) {
            let withoutSelf = String(trimmed.dropFirst(Strings.selfPrefix.count))
            return stripSafeArea(from: withoutSelf)
        }
        return stripSafeArea(from: trimmed)
    }

    private func stripSafeArea(from text: String) -> String {
        if text.hasSuffix(Strings.safeAreaSuffix) {
            return String(text.dropLast(Strings.safeAreaSuffix.count))
        }
        return text
    }

    private func attributeFromAnchorName(_ name: String) -> ConstraintAttribute {
        switch name {
        case Strings.topAnchor:
            return .top
        case Strings.bottomAnchor:
            return .bottom
        case Strings.leadingAnchor:
            return .leading
        case Strings.trailingAnchor:
            return .trailing
        case Strings.leftAnchor:
            return .left
        case Strings.rightAnchor:
            return .right
        case Strings.centerXAnchor:
            return .centerX
        case Strings.centerYAnchor:
            return .centerY
        case Strings.widthAnchor:
            return .width
        case Strings.heightAnchor:
            return .height
        default:
            return .unknown
        }
    }

    private func parseDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(trimmed)
    }

    private enum Strings {
        static let empty = ""
        static let constraintMember = "constraint"
        static let equalToLabel = "equalTo"
        static let equalToConstantLabel = "equalToConstant"
        static let constantLabel = "constant"
        static let selfPrefix = "self."
        static let safeAreaSuffix = ".safeAreaLayoutGuide"

        static let topAnchor = "topAnchor"
        static let bottomAnchor = "bottomAnchor"
        static let leadingAnchor = "leadingAnchor"
        static let trailingAnchor = "trailingAnchor"
        static let leftAnchor = "leftAnchor"
        static let rightAnchor = "rightAnchor"
        static let centerXAnchor = "centerXAnchor"
        static let centerYAnchor = "centerYAnchor"
        static let widthAnchor = "widthAnchor"
        static let heightAnchor = "heightAnchor"
    }
}

