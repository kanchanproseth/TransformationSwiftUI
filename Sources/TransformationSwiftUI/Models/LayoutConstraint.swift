// SPDX-License-Identifier: MIT
//
// LayoutConstraint.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Model types for Auto Layout constraint attributes and values.
//

import Foundation

/// Supported Auto Layout attributes used in constraint parsing.
public enum ConstraintAttribute: String, CaseIterable {
    /// The top edge of a view.
    case top
    /// The bottom edge of a view.
    case bottom
    /// The leading edge of a view.
    case leading
    /// The trailing edge of a view.
    case trailing
    /// The left edge of a view.
    case left
    /// The right edge of a view.
    case right
    /// The horizontal center of a view.
    case centerX
    /// The vertical center of a view.
    case centerY
    /// The width of a view.
    case width
    /// The height of a view.
    case height
    /// An attribute that could not be identified.
    case unknown
}

/// Constraint relation types supported by the parser.
public enum ConstraintRelation: CaseIterable {
    /// Equality relation (==).
    case equal
    /// Greater-than-or-equal relation (>=).
    case greaterThanOrEqual
    /// Less-than-or-equal relation (<=).
    case lessThanOrEqual
}

/// A normalized Auto Layout constraint between two UI elements.
public struct LayoutConstraint {
    /// The name of the first item in the constraint.
    public let firstItem: String

    /// The attribute on the first item.
    public let firstAttribute: ConstraintAttribute

    /// The relation between the first and second items.
    public let relation: ConstraintRelation

    /// The name of the second item, if present.
    public let secondItem: String?

    /// The attribute on the second item, if present.
    public let secondAttribute: ConstraintAttribute?

    /// The constant offset associated with the constraint, if present.
    public let constant: Double?

    public init(
        firstItem: String,
        firstAttribute: ConstraintAttribute,
        relation: ConstraintRelation,
        secondItem: String?,
        secondAttribute: ConstraintAttribute?,
        constant: Double?
    ) {
        self.firstItem = firstItem
        self.firstAttribute = firstAttribute
        self.relation = relation
        self.secondItem = secondItem
        self.secondAttribute = secondAttribute
        self.constant = constant
    }
}
