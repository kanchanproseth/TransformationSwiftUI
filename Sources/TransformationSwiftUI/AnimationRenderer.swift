// SPDX-License-Identifier: MIT
//
// AnimationRenderer.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Generates SwiftUI animation code (@State declarations, modifiers,
//              withAnimation blocks, .onAppear) from a collection of AnimationModel values.
//

import Foundation

/// Generates SwiftUI animation code from a collection of `AnimationModel` instances.
public struct AnimationRenderer {

    // MARK: - @State declarations

    /// Generates `@State` declarations for animated properties that require state variables.
    ///
    /// - Parameters:
    ///   - animations: The detected animations to process.
    ///   - existingElements: The root elements already in scope (to avoid duplicate state names).
    /// - Returns: Lines of Swift code for each required `@State` declaration.
    public static func buildAnimationStateDeclarations(
        from animations: [AnimationModel],
        existingElements: [UIElementNode]
    ) -> [String] {
        var lines: [String] = []
        var seen = Set<String>()

        for animation in animations {
            guard let target = animation.targetElementName else { continue }
            for change in animation.propertyChanges {
                let decls = stateDeclarations(for: change, elementName: target)
                for decl in decls {
                    if seen.insert(decl).inserted {
                        lines.append(decl)
                    }
                }
            }
        }
        return lines
    }

    private static func stateDeclarations(
        for change: AnimatedPropertyChange,
        elementName: String
    ) -> [String] {
        switch change {
        case .alpha:
            return ["\(Strings.statePrefix)\(elementName)\(Strings.opacitySuffix): Double = 1.0"]
        case .isHidden:
            return ["\(Strings.statePrefix)\(elementName)\(Strings.isVisibleSuffix): Bool = true"]
        case .backgroundColor:
            return ["\(Strings.statePrefix)\(elementName)\(Strings.bgColorSuffix): Color = .clear"]
        case .transform(let t):
            switch t {
            case .scale:
                return ["\(Strings.statePrefix)\(elementName)\(Strings.scaleSuffix): CGFloat = 1.0"]
            case .rotation:
                return ["\(Strings.statePrefix)\(elementName)\(Strings.rotationSuffix): Double = 0"]
            case .translation:
                return [
                    "\(Strings.statePrefix)\(elementName)\(Strings.offsetXSuffix): CGFloat = 0",
                    "\(Strings.statePrefix)\(elementName)\(Strings.offsetYSuffix): CGFloat = 0"
                ]
            case .identity:
                return ["\(Strings.statePrefix)\(elementName)\(Strings.scaleSuffix): CGFloat = 1.0"]
            }
        case .frame:
            return []
        }
    }

    // MARK: - Per-element modifier lines

    /// Generates SwiftUI modifier lines for a specific element name based on animations targeting it.
    ///
    /// - Parameters:
    ///   - elementName: The view element name to generate modifiers for.
    ///   - animations: All animations in the controller.
    ///   - indent: Indentation level.
    /// - Returns: Lines such as `.opacity(titleLabelOpacity)`, `.scaleEffect(...)`, etc.
    public static func modifierLines(
        for elementName: String,
        animations: [AnimationModel],
        indent: Int
    ) -> [String] {
        let prefix = SwiftUICodeGenerator.indentString(indent)
        var lines: [String] = []
        var seen = Set<String>()

        for animation in animations {
            guard animation.targetElementName == elementName else { continue }
            for change in animation.propertyChanges {
                let modifier = modifierLine(for: change, elementName: elementName)
                guard let modifier, seen.insert(modifier).inserted else { continue }
                lines.append("\(prefix)\(modifier)")
            }
        }
        return lines
    }

    private static func modifierLine(
        for change: AnimatedPropertyChange,
        elementName: String
    ) -> String? {
        switch change {
        case .alpha:
            return ".opacity(\(elementName)\(Strings.opacitySuffix))"
        case .isHidden:
            return ".opacity(\(elementName)\(Strings.isVisibleSuffix) ? 1 : 0)"
        case .backgroundColor:
            return ".background(\(elementName)\(Strings.bgColorSuffix))"
        case .transform(let t):
            switch t {
            case .scale:
                return ".scaleEffect(\(elementName)\(Strings.scaleSuffix))"
            case .rotation:
                return ".rotationEffect(.radians(\(elementName)\(Strings.rotationSuffix)))"
            case .translation:
                return ".offset(x: \(elementName)\(Strings.offsetXSuffix), y: \(elementName)\(Strings.offsetYSuffix))"
            case .identity:
                return ".scaleEffect(\(elementName)\(Strings.scaleSuffix))"
            }
        case .frame, .backgroundColor:
            return nil
        }
    }

    // MARK: - .onAppear block

    /// Generates `.onAppear { withAnimation { ... } }` blocks for appear-context animations.
    ///
    /// - Parameters:
    ///   - animations: All detected animations.
    ///   - indent: Indentation level for the modifier itself.
    /// - Returns: Lines forming the `.onAppear` modifier, or empty if no appear animations.
    public static func onAppearBlock(
        from animations: [AnimationModel],
        indent: Int
    ) -> [String] {
        let appearAnimations = animations.filter {
            switch $0.context {
            case .viewDidAppear, .viewWillAppear: return true
            default: return false
            }
        }
        guard !appearAnimations.isEmpty else { return [] }

        let outerPrefix = SwiftUICodeGenerator.indentString(indent)
        let innerPrefix = SwiftUICodeGenerator.indentString(indent + 1)
        let bodyPrefix = SwiftUICodeGenerator.indentString(indent + 2)

        var lines: [String] = []
        lines.append("\(outerPrefix).onAppear {")

        // Group by unique animation parameters
        let firstAnim = appearAnimations.first!
        let animExpr = swiftUIAnimationExpression(timingCurve: firstAnim.timingCurve, duration: firstAnim.duration)
        lines.append("\(innerPrefix)withAnimation(\(animExpr)) {")

        for animation in appearAnimations {
            guard let target = animation.targetElementName else { continue }
            for change in animation.propertyChanges {
                if let assignment = stateAssignment(for: change, elementName: target, animated: true) {
                    lines.append("\(bodyPrefix)\(assignment)")
                }
            }
        }

        lines.append("\(innerPrefix)}")
        lines.append("\(outerPrefix)}")
        return lines
    }

    private static func stateAssignment(
        for change: AnimatedPropertyChange,
        elementName: String,
        animated: Bool
    ) -> String? {
        switch change {
        case .alpha(let val):
            return "\(elementName)\(Strings.opacitySuffix) = \(formatDouble(val))"
        case .isHidden(let hidden):
            return "\(elementName)\(Strings.isVisibleSuffix) = \(!hidden)"
        case .transform(let t):
            switch t {
            case .scale(let x, _):
                return "\(elementName)\(Strings.scaleSuffix) = \(formatDouble(x))"
            case .rotation(let r):
                return "\(elementName)\(Strings.rotationSuffix) = \(formatDouble(r))"
            case .translation(let x, let y):
                return "\(elementName)\(Strings.offsetXSuffix) = \(formatDouble(x)); \(elementName)\(Strings.offsetYSuffix) = \(formatDouble(y))"
            case .identity:
                return "\(elementName)\(Strings.scaleSuffix) = 1.0"
            }
        default:
            return nil
        }
    }

    // MARK: - Animation expression helpers

    /// Returns a SwiftUI animation expression string for the given timing curve and duration.
    public static func swiftUIAnimationExpression(
        timingCurve: AnimationTimingCurve,
        duration: Double?
    ) -> String {
        let d = duration.map { formatDouble($0) }
        switch timingCurve {
        case .easeInOut:
            return d.map { ".easeInOut(duration: \($0))" } ?? ".easeInOut"
        case .easeIn:
            return d.map { ".easeIn(duration: \($0))" } ?? ".easeIn"
        case .easeOut:
            return d.map { ".easeOut(duration: \($0))" } ?? ".easeOut"
        case .linear:
            return d.map { ".linear(duration: \($0))" } ?? ".linear"
        case .spring(let damping, let response):
            return ".spring(response: \(formatDouble(response)), dampingFraction: \(formatDouble(damping)))"
        case .custom:
            return d.map { ".easeInOut(duration: \($0))" } ?? ".default"
        }
    }

    // MARK: - Private helpers

    private static func formatDouble(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.2f", value)
    }

    // MARK: - String constants

    private enum Strings {
        static let statePrefix = "@State private var "
        static let opacitySuffix = "Opacity"
        static let isVisibleSuffix = "IsVisible"
        static let bgColorSuffix = "BgColor"
        static let scaleSuffix = "Scale"
        static let rotationSuffix = "Rotation"
        static let offsetXSuffix = "OffsetX"
        static let offsetYSuffix = "OffsetY"
    }
}
