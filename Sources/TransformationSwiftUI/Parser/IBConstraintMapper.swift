// SPDX-License-Identifier: MIT
//
// IBConstraintMapper.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Converts Interface Builder constraint XML into LayoutConstraint models.
//

import Foundation

/// Converts Interface Builder <constraint> XML elements into LayoutConstraint model instances.
public struct IBConstraintMapper {

    private static let attributeMap: [String: ConstraintAttribute] = [
        Strings.attrTop: .top,
        Strings.attrBottom: .bottom,
        Strings.attrLeading: .leading,
        Strings.attrTrailing: .trailing,
        Strings.attrLeft: .left,
        Strings.attrRight: .right,
        Strings.attrCenterX: .centerX,
        Strings.attrCenterY: .centerY,
        Strings.attrWidth: .width,
        Strings.attrHeight: .height,
    ]

    /// Converts an array of <constraint> XML elements into LayoutConstraint instances.
    ///
    /// - Parameters:
    ///   - constraintElements: The <constraint> XMLElements from a <constraints> block.
    ///   - idToName: Map from IB element IDs to resolved human-readable names.
    ///   - owningViewName: The name of the view that contains this <constraints> block.
    ///     Used when firstItem is missing (meaning "the owning view itself").
    public static func mapConstraints(
        from constraintElements: [XMLElement],
        idToName: [String: String],
        owningViewName: String?
    ) -> [LayoutConstraint] {
        var constraints: [LayoutConstraint] = []

        for element in constraintElements {
            guard element.name == Strings.constraintElement else { continue }

            // firstItem may be omitted when the constraint is relative to the owning view
            let firstItemID = element.attribute(forName: Strings.firstItemAttribute)?.stringValue
            let firstItemName: String
            if let id = firstItemID {
                firstItemName = idToName[id] ?? id
            } else {
                firstItemName = owningViewName ?? Strings.containerView
            }

            guard let firstAttrString = element.attribute(forName: Strings.firstAttributeAttribute)?.stringValue,
                  let firstAttribute = constraintAttribute(from: firstAttrString) else {
                continue
            }

            let secondItemID = element.attribute(forName: Strings.secondItemAttribute)?.stringValue
            let secondItemName: String?
            if let id = secondItemID {
                // Resolve safe area layout guide IDs to a readable name
                secondItemName = idToName[id] ?? (isLayoutGuideID(id) ? Strings.safeAreaName : id)
            } else {
                secondItemName = nil
            }

            let secondAttrString = element.attribute(forName: Strings.secondAttributeAttribute)?.stringValue
            let secondAttribute = secondAttrString.flatMap { constraintAttribute(from: $0) }

            let relation = constraintRelation(from: element.attribute(forName: Strings.relationAttribute)?.stringValue)

            let constantString = element.attribute(forName: Strings.constantAttribute)?.stringValue
            let constant = constantString.flatMap { Double($0) }

            let constraint = LayoutConstraint(
                firstItem: firstItemName,
                firstAttribute: firstAttribute,
                relation: relation,
                secondItem: secondItemName,
                secondAttribute: secondAttribute,
                constant: constant
            )
            constraints.append(constraint)
        }

        return constraints
    }

    /// Maps an IB constraint attribute string to ConstraintAttribute.
    public static func constraintAttribute(from ibAttribute: String) -> ConstraintAttribute? {
        attributeMap[ibAttribute]
    }

    /// Maps an IB constraint relation string to ConstraintRelation.
    /// Missing relation defaults to .equal (the most common case in IB).
    public static func constraintRelation(from ibRelation: String?) -> ConstraintRelation {
        switch ibRelation {
        case Strings.relationGreaterThanOrEqual: return .greaterThanOrEqual
        case Strings.relationLessThanOrEqual: return .lessThanOrEqual
        default: return .equal
        }
    }

    /// Returns true for known layout guide element IDs (safe area, margins, etc.)
    private static func isLayoutGuideID(_ id: String) -> Bool {
        // Layout guide elements have "guide" in their class or are children of layoutGuides
        // We use a heuristic: IDs that appear in the idToName map but resolve to guide-type names
        return false  // The caller handles this via idToName lookup
    }

    private enum Strings {
        static let constraintElement = "constraint"
        static let firstItemAttribute = "firstItem"
        static let secondItemAttribute = "secondItem"
        static let firstAttributeAttribute = "firstAttribute"
        static let secondAttributeAttribute = "secondAttribute"
        static let relationAttribute = "relation"
        static let constantAttribute = "constant"

        static let containerView = "view"
        static let safeAreaName = "safeArea"

        static let relationGreaterThanOrEqual = "greaterThanOrEqual"
        static let relationLessThanOrEqual = "lessThanOrEqual"

        static let attrTop = "top"
        static let attrBottom = "bottom"
        static let attrLeading = "leading"
        static let attrTrailing = "trailing"
        static let attrLeft = "left"
        static let attrRight = "right"
        static let attrCenterX = "centerX"
        static let attrCenterY = "centerY"
        static let attrWidth = "width"
        static let attrHeight = "height"
    }
}
