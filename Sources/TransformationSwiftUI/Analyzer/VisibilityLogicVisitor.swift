// SPDX-License-Identifier: MIT
//
// VisibilityLogicVisitor.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: SwiftSyntax visitor that detects UI show/hide and add/remove logic in view controllers.
//

import SwiftSyntax

// MARK: - VisibilityRule

/// Describes a single visibility mutation detected in UIKit source code.
public struct VisibilityRule {
    /// The UI element variable name being mutated.
    public let elementName: String
    /// The kind of visibility change.
    public let kind: VisibilityKind
    /// The Swift condition expression driving the change (e.g. `isLoggedIn`, `items.isEmpty`).
    public let condition: String?
    /// The source function or method where this mutation was found.
    public let context: String

    public init(elementName: String, kind: VisibilityKind, condition: String?, context: String) {
        self.elementName = elementName
        self.kind = kind
        self.condition = condition
        self.context = context
    }
}

// MARK: - VisibilityKind

/// The category of visibility or presence mutation.
public enum VisibilityKind: String {
    /// `view.isHidden = true` — maps to `.opacity(0)` or conditional rendering.
    case hidden
    /// `view.isHidden = false` — maps to `.opacity(1)` or always-visible.
    case visible
    /// `view.alpha = 0` — maps to `.opacity(0)`.
    case alphaZero
    /// `view.alpha = 1` — maps to `.opacity(1)`.
    case alphaOne
    /// `view.alpha = <value>` — maps to `.opacity(value)`.
    case alphaValue
    /// `containerView.addSubview(child)` — maps to conditional `if showChild { ChildView() }`.
    case addSubview
    /// `child.removeFromSuperview()` — maps to conditional removal of view.
    case removeFromSuperview
    /// `UIView.animate { view.isHidden = ... }` — animated visibility toggle.
    case animatedToggle
}

// MARK: - VisibilityLogicVisitor

/// Walks UIViewController AST nodes and extracts all UI show/hide, alpha, and
/// addSubview/removeFromSuperview mutations so the generator can produce correct
/// SwiftUI `@State`-driven conditional rendering.
public class VisibilityLogicVisitor: SyntaxVisitor {

    /// All detected visibility rules in the visited scope.
    public private(set) var rules: [VisibilityRule] = []

    /// The current enclosing function name for context labelling.
    private var currentFunction: String = "unknown"

    /// The current `if` condition text for attribution.
    private var currentCondition: String? = nil

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Function context tracking

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        currentFunction = node.name.text
        return .visitChildren
    }

    public override func visitPost(_ node: FunctionDeclSyntax) {
        currentFunction = "unknown"
    }

    // MARK: - If-condition context tracking

    public override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        currentCondition = node.conditions.description
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .visitChildren
    }

    public override func visitPost(_ node: IfExprSyntax) {
        currentCondition = nil
    }

    // MARK: - Assignment detection (view.isHidden = ..., view.alpha = ...)

    public override func visit(_ node: ExpressionStmtSyntax) -> SyntaxVisitorContinueKind {
        if let assignment = node.expression.as(SequenceExprSyntax.self) {
            handleSequenceExpression(assignment)
        }
        return .visitChildren
    }

    private func handleSequenceExpression(_ seq: SequenceExprSyntax) {
        let elements = Array(seq.elements)
        guard elements.count >= 3 else { return }

        // Pattern: <member-access> = <value>
        guard let lhs = elements[0].as(MemberAccessExprSyntax.self),
              elements[1].as(AssignmentExprSyntax.self) != nil else { return }

        let baseName = lhs.base?.description
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let memberName = lhs.declName.baseName.text
        let rhs = elements[2].description.trimmingCharacters(in: .whitespacesAndNewlines)

        switch memberName {
        case "isHidden":
            let kind: VisibilityKind = (rhs == "true") ? .hidden : .visible
            rules.append(VisibilityRule(
                elementName: baseName,
                kind: kind,
                condition: currentCondition,
                context: currentFunction
            ))

        case "alpha":
            let kind: VisibilityKind
            if rhs == "0" || rhs == "0.0" {
                kind = .alphaZero
            } else if rhs == "1" || rhs == "1.0" {
                kind = .alphaOne
            } else {
                kind = .alphaValue
            }
            rules.append(VisibilityRule(
                elementName: baseName,
                kind: kind,
                condition: currentCondition,
                context: currentFunction
            ))

        default:
            break
        }
    }

    // MARK: - Function call detection (addSubview, removeFromSuperview)

    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
            let methodName = member.declName.baseName.text
            let baseName = member.base?.description
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            switch methodName {
            case "addSubview":
                // containerView.addSubview(childView)
                if let firstArg = node.arguments.first {
                    let childName = firstArg.expression.description
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    rules.append(VisibilityRule(
                        elementName: childName,
                        kind: .addSubview,
                        condition: currentCondition,
                        context: currentFunction
                    ))
                }

            case "removeFromSuperview":
                // childView.removeFromSuperview()
                rules.append(VisibilityRule(
                    elementName: baseName,
                    kind: .removeFromSuperview,
                    condition: currentCondition,
                    context: currentFunction
                ))

            default:
                break
            }
        }
        return .visitChildren
    }
}
