// SPDX-License-Identifier: MIT
//
// LayoutPatternEngine.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Infers stack patterns and layout hints from Auto Layout constraints.
//

import Foundation

/// Stack pattern kinds inferred from constraints.
public enum LayoutPatternType: CaseIterable {
    /// Vertical stack pattern.
    case vStack
    /// Horizontal stack pattern.
    case hStack
    /// Z-axis overlay stack pattern.
    case zStack

    /// The SwiftUI container name for the pattern.
    public var displayName: String {
        switch self {
        case .vStack:
            return Strings.vStack
        case .hStack:
            return Strings.hStack
        case .zStack:
            return Strings.zStack
        }
    }

    private enum Strings {
        static let vStack = "VStack"
        static let hStack = "HStack"
        static let zStack = "ZStack"
    }
}

/// A detected layout pattern with ordered elements.
public struct LayoutPattern {
    /// The inferred stack type.
    public let type: LayoutPatternType
    /// The ordered element names participating in the pattern.
    public let elements: [String]

    public init(type: LayoutPatternType, elements: [String]) {
        self.type = type
        self.elements = elements
    }
}

/// Infers stack patterns and layout hints from constraints.
public struct LayoutPatternEngine {

    /// Returns layout patterns (VStack, HStack, ZStack) inferred from constraints.
    public static func inferPatterns(from constraints: [LayoutConstraint]) -> [LayoutPattern] {
        var patterns: [LayoutPattern] = []

        let verticalGraph = buildGraph(from: constraints, orientation: .vertical)
        let horizontalGraph = buildGraph(from: constraints, orientation: .horizontal)

        let verticalGroups = connectedComponents(in: verticalGraph)
        for group in verticalGroups where group.count >= 2 {
            let ordered = orderElements(in: group, orientation: .vertical, constraints: constraints)
            patterns.append(LayoutPattern(type: .vStack, elements: ordered))
        }

        let horizontalGroups = connectedComponents(in: horizontalGraph)
        for group in horizontalGroups where group.count >= 2 {
            let ordered = orderElements(in: group, orientation: .horizontal, constraints: constraints)
            patterns.append(LayoutPattern(type: .hStack, elements: ordered))
        }

        let zStackGroups = detectZStackGroups(from: constraints)
        for group in zStackGroups where group.count >= 2 {
            patterns.append(LayoutPattern(type: .zStack, elements: Array(group).sorted()))
        }

        return dedupe(patterns)
    }

    /// Returns SwiftUI modifier hints derived from constraints.
    public static func inferHints(from constraints: [LayoutConstraint]) -> [String] {
        var hints: [String] = []
        let containerNames: Set<String> = [Strings.containerView, Strings.containerContentView, Strings.containerSelfView]

        for constraint in constraints {
            let item = constraint.firstItem
            switch constraint.firstAttribute {
            case .width:
                if let constant = constraint.constant {
                    hints.append(item + Strings.frameWidthPrefix + format(constant) + Strings.closeParen)
                }
            case .height:
                if let constant = constraint.constant {
                    hints.append(item + Strings.frameHeightPrefix + format(constant) + Strings.closeParen)
                }
            case .leading, .trailing, .left, .right, .top, .bottom:
                if let secondItem = constraint.secondItem,
                   let constant = constraint.constant {
                    let edge = edgeName(for: constraint.firstAttribute)
                    let value = format(abs(constant))
                    if containerNames.contains(secondItem) {
                        hints.append(item + Strings.paddingPrefix + edge + Strings.paddingInfix + value + Strings.closeParen)
                    } else {
                        hints.append(item + Strings.paddingPrefix + edge + Strings.paddingInfix + value + Strings.closeParen + Strings.relativeToPrefix + secondItem)
                    }
                }
            default:
                continue
            }
        }

        return dedupeHints(hints)
    }

    private enum Orientation {
        case vertical
        case horizontal
    }

    private static func buildGraph(from constraints: [LayoutConstraint], orientation: Orientation) -> [String: Set<String>] {
        var graph: [String: Set<String>] = [:]
        for constraint in constraints {
            guard let secondItem = constraint.secondItem else { continue }

            let isMatch: Bool
            switch orientation {
            case .vertical:
                isMatch = isVertical(constraint.firstAttribute) || isVertical(constraint.secondAttribute ?? .unknown)
            case .horizontal:
                isMatch = isHorizontal(constraint.firstAttribute) || isHorizontal(constraint.secondAttribute ?? .unknown)
            }
            if !isMatch {
                continue
            }

            graph[constraint.firstItem, default: []].insert(secondItem)
            graph[secondItem, default: []].insert(constraint.firstItem)
        }
        return graph
    }

    private static func connectedComponents(in graph: [String: Set<String>]) -> [Set<String>] {
        var visited: Set<String> = []
        var components: [Set<String>] = []

        for node in graph.keys {
            if visited.contains(node) { continue }
            var stack: [String] = [node]
            var component: Set<String> = []

            while let current = stack.popLast() {
                if visited.contains(current) { continue }
                visited.insert(current)
                component.insert(current)
                for neighbor in graph[current] ?? [] {
                    if !visited.contains(neighbor) {
                        stack.append(neighbor)
                    }
                }
            }

            if !component.isEmpty {
                components.append(component)
            }
        }

        return components
    }

    private static func orderElements(
        in group: Set<String>,
        orientation: Orientation,
        constraints: [LayoutConstraint]
    ) -> [String] {
        var adjacency: [String: Set<String>] = [:]
        var indegree: [String: Int] = [:]

        for item in group {
            adjacency[item] = []
            indegree[item] = 0
        }

        for constraint in constraints {
            guard let secondItem = constraint.secondItem else { continue }
            if !group.contains(constraint.firstItem) || !group.contains(secondItem) {
                continue
            }

            let edge = edgeDirection(for: constraint, orientation: orientation)
            guard let edge else { continue }

            if !(adjacency[edge.from]?.contains(edge.to) ?? false) {
                adjacency[edge.from, default: []].insert(edge.to)
                indegree[edge.to, default: 0] += 1
            }
        }

        var queue = indegree.filter { $0.value == 0 }.map { $0.key }.sorted()
        var ordered: [String] = []

        while !queue.isEmpty {
            let node = queue.removeFirst()
            ordered.append(node)
            for neighbor in adjacency[node] ?? [] {
                indegree[neighbor, default: 0] -= 1
                if indegree[neighbor] == 0 {
                    queue.append(neighbor)
                    queue.sort()
                }
            }
        }

        if ordered.count == group.count {
            return ordered
        }

        return group.sorted()
    }

    private struct Edge {
        let from: String
        let to: String
    }

    private static func edgeDirection(
        for constraint: LayoutConstraint,
        orientation: Orientation
    ) -> Edge? {
        guard let secondItem = constraint.secondItem else { return nil }

        switch orientation {
        case .vertical:
            if constraint.firstAttribute == .top, constraint.secondAttribute == .bottom {
                return Edge(from: secondItem, to: constraint.firstItem)
            }
            if constraint.firstAttribute == .bottom, constraint.secondAttribute == .top {
                return Edge(from: constraint.firstItem, to: secondItem)
            }
            if constraint.firstAttribute == .centerY, constraint.secondAttribute == .centerY {
                return Edge(from: secondItem, to: constraint.firstItem)
            }
        case .horizontal:
            if constraint.firstAttribute == .leading, constraint.secondAttribute == .trailing {
                return Edge(from: secondItem, to: constraint.firstItem)
            }
            if constraint.firstAttribute == .trailing, constraint.secondAttribute == .leading {
                return Edge(from: constraint.firstItem, to: secondItem)
            }
            if constraint.firstAttribute == .left, constraint.secondAttribute == .right {
                return Edge(from: secondItem, to: constraint.firstItem)
            }
            if constraint.firstAttribute == .right, constraint.secondAttribute == .left {
                return Edge(from: constraint.firstItem, to: secondItem)
            }
            if constraint.firstAttribute == .centerX, constraint.secondAttribute == .centerX {
                return Edge(from: secondItem, to: constraint.firstItem)
            }
        }

        return nil
    }

    private static func detectZStackGroups(from constraints: [LayoutConstraint]) -> [Set<String>] {
        var pairCounts: [String: Int] = [:]

        for constraint in constraints {
            guard let secondItem = constraint.secondItem else { continue }

            let isOverlay = isOverlayAttribute(constraint.firstAttribute)
                && isOverlayAttribute(constraint.secondAttribute ?? .unknown)
            if !isOverlay { continue }

            let pairKey = [constraint.firstItem, secondItem].sorted().joined(separator: Strings.pairSeparator)
            pairCounts[pairKey, default: 0] += 1
        }

        var groups: [Set<String>] = []
        for (pairKey, count) in pairCounts where count >= 2 {
            let items = pairKey.split(separator: Strings.pairSeparatorCharacter).map(String.init)
            groups.append(Set(items))
        }

        return groups
    }

    private static func dedupe(_ patterns: [LayoutPattern]) -> [LayoutPattern] {
        var seen: Set<String> = []
        var result: [LayoutPattern] = []

        for pattern in patterns {
            let key = pattern.type.displayName + Strings.patternKeySeparator + pattern.elements.sorted().joined(separator: Strings.patternElementsSeparator)
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(pattern)
        }

        return result
    }

    private static func dedupeHints(_ hints: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for hint in hints {
            if seen.contains(hint) { continue }
            seen.insert(hint)
            result.append(hint)
        }
        return result
    }

    private static func edgeName(for attribute: ConstraintAttribute) -> String {
        switch attribute {
        case .leading, .left:
            return Strings.edgeLeading
        case .trailing, .right:
            return Strings.edgeTrailing
        case .top:
            return Strings.edgeTop
        case .bottom:
            return Strings.edgeBottom
        default:
            return Strings.edgeAll
        }
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
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

    private static func isOverlayAttribute(_ attribute: ConstraintAttribute) -> Bool {
        switch attribute {
        case .centerX, .centerY, .top, .bottom, .leading, .trailing, .left, .right:
            return true
        default:
            return false
        }
    }

    private enum Strings {
        static let containerView = "view"
        static let containerContentView = "contentView"
        static let containerSelfView = "self.view"

        static let frameWidthPrefix = ".frame(width: "
        static let frameHeightPrefix = ".frame(height: "
        static let paddingPrefix = ".padding(."
        static let paddingInfix = ", "
        static let relativeToPrefix = ") // relative to "
        static let closeParen = ")"

        static let pairSeparator = "|"
        static let pairSeparatorCharacter: Character = "|"

        static let patternKeySeparator = ":"
        static let patternElementsSeparator = ","

        static let edgeLeading = "leading"
        static let edgeTrailing = "trailing"
        static let edgeTop = "top"
        static let edgeBottom = "bottom"
        static let edgeAll = "all"
    }
}
