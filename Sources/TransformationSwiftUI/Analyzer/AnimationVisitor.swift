// SPDX-License-Identifier: MIT
//
// AnimationVisitor.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: SwiftSyntax visitor that detects UIKit animation patterns
//              (UIView.animate, UIViewPropertyAnimator, CA* animations) and
//              extracts them into AnimationModel instances.
//

import Foundation
import SwiftSyntax

/// Visits SwiftSyntax trees to collect UIKit animation declarations.
public class AnimationVisitor: SyntaxVisitor {

    /// Collected animation models discovered during traversal.
    public private(set) var animations: [AnimationModel] = []

    /// The name of the function declaration currently being visited.
    private var currentFunctionName: String?

    /// Whether the current function has an `@objc` attribute.
    private var currentFunctionIsObjc: Bool = false

    /// Creates a visitor configured for source-accurate parsing.
    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Function context tracking

    override public func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        currentFunctionName = node.name.text
        currentFunctionIsObjc = node.attributes.contains { attr in
            attr.as(AttributeSyntax.self)?.attributeName.description.trimmingCharacters(in: .whitespaces) == Strings.objc
        }
        return .visitChildren
    }

    override public func visitPost(_ node: FunctionDeclSyntax) {
        currentFunctionName = nil
        currentFunctionIsObjc = false
    }

    // MARK: - Function call detection

    override public func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // UIView.animate(...) and UIView.transition(...)
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
           let base = memberAccess.base?.description.trimmingCharacters(in: .whitespacesAndNewlines),
           base == Strings.uiView {
            let methodName = memberAccess.declName.baseName.text
            if methodName == Strings.animate {
                parseUIViewAnimate(node)
                return .visitChildren
            } else if methodName == Strings.transition {
                parseUIViewTransition(node)
                return .visitChildren
            }
        }

        // UIViewPropertyAnimator(duration:curve:animations:)
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
            // handles UIViewPropertyAnimator(...) as initializer via member
            _ = memberAccess
        }
        if let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self),
           declRef.baseName.text == Strings.uiViewPropertyAnimator {
            parsePropertyAnimator(node)
            return .visitChildren
        }

        // CABasicAnimation, CAKeyframeAnimation, CASpringAnimation, CAAnimationGroup
        if let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            let name = declRef.baseName.text
            if [Strings.caBasicAnimation, Strings.caKeyframeAnimation, Strings.caSpringAnimation, Strings.caAnimationGroup].contains(name) {
                parseCAAnimation(node, calledName: name)
                return .visitChildren
            }
        }

        return .visitChildren
    }

    // MARK: - UIView.animate parsing

    private func parseUIViewAnimate(_ node: FunctionCallExprSyntax) {
        var duration: Double?
        var delay: Double?
        var dampingFraction: Double?
        var animationsClosure: ClosureExprSyntax?
        var hasCompletion = false

        for arg in node.arguments {
            let label = arg.label?.text ?? Strings.empty
            switch label {
            case Strings.withDuration:
                duration = parseDouble(arg.expression.description)
            case Strings.delay:
                delay = parseDouble(arg.expression.description)
            case Strings.usingSpringWithDamping:
                dampingFraction = parseDouble(arg.expression.description)
            case Strings.animations:
                animationsClosure = extractClosure(from: arg.expression)
            case Strings.completion:
                hasCompletion = true
            default:
                break
            }
        }
        // Trailing closure as animations block when no label
        if animationsClosure == nil {
            animationsClosure = node.trailingClosure
        }

        let isSpring = dampingFraction != nil
        let kind: AnimationKind = isSpring ? .uiViewSpringAnimate : .uiViewAnimate
        let timingCurve: AnimationTimingCurve
        if let d = dampingFraction {
            let response = duration ?? 0.35
            timingCurve = .spring(dampingFraction: d, response: response)
        } else {
            timingCurve = .easeInOut
        }

        let context = buildContext()
        let propertyChanges = animationsClosure.map { parseAnimationClosure($0) } ?? []

        // Group by target element name
        let byTarget = Dictionary(grouping: propertyChanges) { $0.0 }
        if byTarget.isEmpty {
            let model = AnimationModel(
                kind: kind,
                duration: duration,
                delay: delay,
                timingCurve: timingCurve,
                context: context,
                targetElementName: nil,
                propertyChanges: [],
                hasCompletion: hasCompletion
            )
            animations.append(model)
        } else {
            for (targetName, pairs) in byTarget {
                let changes = pairs.map { $0.1 }
                let model = AnimationModel(
                    kind: kind,
                    duration: duration,
                    delay: delay,
                    timingCurve: timingCurve,
                    context: context,
                    targetElementName: targetName,
                    propertyChanges: changes,
                    hasCompletion: hasCompletion
                )
                animations.append(model)
            }
        }
    }

    // MARK: - UIView.transition parsing

    private func parseUIViewTransition(_ node: FunctionCallExprSyntax) {
        var duration: Double?
        var hasCompletion = false

        for arg in node.arguments {
            let label = arg.label?.text ?? Strings.empty
            switch label {
            case Strings.duration:
                duration = parseDouble(arg.expression.description)
            case Strings.completion:
                hasCompletion = true
            default:
                break
            }
        }

        let model = AnimationModel(
            kind: .uiViewTransition,
            duration: duration,
            delay: nil,
            timingCurve: .easeInOut,
            context: buildContext(),
            targetElementName: nil,
            propertyChanges: [],
            hasCompletion: hasCompletion
        )
        animations.append(model)
    }

    // MARK: - UIViewPropertyAnimator parsing

    private func parsePropertyAnimator(_ node: FunctionCallExprSyntax) {
        var duration: Double?

        for arg in node.arguments {
            let label = arg.label?.text ?? Strings.empty
            if label == Strings.duration {
                duration = parseDouble(arg.expression.description)
            }
        }

        let model = AnimationModel(
            kind: .propertyAnimator,
            duration: duration,
            delay: nil,
            timingCurve: .custom,
            context: buildContext(),
            targetElementName: nil,
            propertyChanges: [],
            hasCompletion: false
        )
        animations.append(model)
    }

    // MARK: - CA* animation parsing

    private func parseCAAnimation(_ node: FunctionCallExprSyntax, calledName: String) {
        var keyPath: String = Strings.empty

        for arg in node.arguments {
            let label = arg.label?.text ?? Strings.empty
            if label == Strings.keyPath {
                // Strip surrounding quotes from string literal
                let raw = arg.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
                keyPath = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }

        let kind: AnimationKind
        switch calledName {
        case Strings.caBasicAnimation:
            kind = .caBasicAnimation(keyPath)
        case Strings.caKeyframeAnimation:
            kind = .caKeyframeAnimation(keyPath)
        case Strings.caSpringAnimation:
            kind = .caSpringAnimation(keyPath)
        default:
            kind = .caAnimationGroup
        }

        let model = AnimationModel(
            kind: kind,
            duration: nil,
            delay: nil,
            timingCurve: .custom,
            context: buildContext(),
            targetElementName: nil,
            propertyChanges: [],
            hasCompletion: false
        )
        animations.append(model)
    }

    // MARK: - Animation closure parsing

    /// Parses assignments inside an animation closure to extract (targetName, propertyChange) pairs.
    private func parseAnimationClosure(_ closure: ClosureExprSyntax) -> [(String?, AnimatedPropertyChange)] {
        var results: [(String?, AnimatedPropertyChange)] = []
        for statement in closure.statements {
            guard let exprStmt = statement.item.as(ExpressionStmtSyntax.self) else { continue }
            guard let infixExpr = exprStmt.expression.as(InfixOperatorExprSyntax.self) else { continue }
            guard infixExpr.operator.as(AssignmentExprSyntax.self) != nil else { continue }

            let lhs = infixExpr.leftOperand.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let rhs = infixExpr.rightOperand.description.trimmingCharacters(in: .whitespacesAndNewlines)

            let (targetName, propertyName) = parseAssignmentTarget(lhs)
            if let change = propertyChange(propertyName: propertyName, rhs: rhs) {
                results.append((targetName, change))
            }
        }
        return results
    }

    /// Splits `self.titleLabel.alpha` → (`"titleLabel"`, `"alpha"`)
    private func parseAssignmentTarget(_ lhs: String) -> (String?, String) {
        var parts = lhs.components(separatedBy: Strings.dot)
        // Strip leading "self"
        if parts.first == Strings.selfKeyword {
            parts.removeFirst()
        }
        if parts.count >= 2 {
            let property = parts.removeLast()
            let target = parts.joined(separator: Strings.dot)
            return (target, property)
        } else if parts.count == 1 {
            return (nil, parts[0])
        }
        return (nil, lhs)
    }

    /// Maps a property name and RHS expression to an `AnimatedPropertyChange`.
    private func propertyChange(propertyName: String, rhs: String) -> AnimatedPropertyChange? {
        switch propertyName {
        case Strings.alpha:
            let val = parseDouble(rhs) ?? 1.0
            return .alpha(val)
        case Strings.isHidden:
            let val = rhs == Strings.trueKeyword
            return .isHidden(val)
        case Strings.backgroundColor:
            return .backgroundColor(rhs)
        case Strings.transform:
            return .transform(parseTransform(rhs))
        case Strings.frame:
            return .frame
        default:
            return nil
        }
    }

    /// Parses a CGAffineTransform expression into an `AnimatedTransform`.
    private func parseTransform(_ rhs: String) -> AnimatedTransform {
        if rhs.contains(Strings.identity) { return .identity }
        if rhs.contains(Strings.scaleX) {
            return .scale(x: 1.0, y: 1.0) // values would need full AST extraction
        }
        if rhs.contains(Strings.rotationAngle) {
            return .rotation(0.0)
        }
        if rhs.contains(Strings.translationX) {
            return .translation(x: 0.0, y: 0.0)
        }
        return .identity
    }

    // MARK: - Helpers

    private func buildContext() -> AnimationContext {
        guard let name = currentFunctionName else { return .other(Strings.unknown) }
        switch name {
        case Strings.viewDidAppear: return .viewDidAppear
        case Strings.viewWillAppear: return .viewWillAppear
        case Strings.viewDidLoad: return .viewDidLoad
        default:
            if currentFunctionIsObjc { return .actionMethod(name) }
            return .other(name)
        }
    }

    private func extractClosure(from expr: ExprSyntax) -> ClosureExprSyntax? {
        if let closure = expr.as(ClosureExprSyntax.self) { return closure }
        return nil
    }

    private func parseDouble(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - String constants

    private enum Strings {
        static let empty = ""
        static let dot = "."
        static let uiView = "UIView"
        static let animate = "animate"
        static let transition = "transition"
        static let uiViewPropertyAnimator = "UIViewPropertyAnimator"
        static let caBasicAnimation = "CABasicAnimation"
        static let caKeyframeAnimation = "CAKeyframeAnimation"
        static let caSpringAnimation = "CASpringAnimation"
        static let caAnimationGroup = "CAAnimationGroup"
        static let withDuration = "withDuration"
        static let duration = "duration"
        static let delay = "delay"
        static let usingSpringWithDamping = "usingSpringWithDamping"
        static let animations = "animations"
        static let completion = "completion"
        static let keyPath = "keyPath"
        static let objc = "objc"
        static let selfKeyword = "self"
        static let trueKeyword = "true"
        static let alpha = "alpha"
        static let isHidden = "isHidden"
        static let backgroundColor = "backgroundColor"
        static let transform = "transform"
        static let frame = "frame"
        static let identity = "identity"
        static let scaleX = "scaleX"
        static let rotationAngle = "rotationAngle"
        static let translationX = "translationX"
        static let viewDidAppear = "viewDidAppear"
        static let viewWillAppear = "viewWillAppear"
        static let viewDidLoad = "viewDidLoad"
        static let unknown = "unknown"
    }
}
