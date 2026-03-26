// SPDX-License-Identifier: MIT
//
// UIElementNode.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Model for a UI element node in the view hierarchy.
//

import Foundation

/// A node in the extracted view hierarchy.
public struct UIElementNode {
    /// The resolved name for this element.
    public let name: String

    /// The inferred UIKit element type.
    public var type: UIKitElementType?

    /// The custom component name when the element resolves to a custom class.
    public var customComponentName: String?

    /// Child elements nested inside this node.
    public var children: [UIElementNode] = []

    /// Key-value properties extracted from Interface Builder or Swift source.
    public var properties: [String: String] = [:]

    /// Visibility rules that affect this element (isHidden, alpha, addSubview, removeFromSuperview).
    public var visibilityRules: [VisibilityRule] = []

    /// Business logic actions bound to this element (IBAction, target-action, delegate callbacks).
    public var controlActions: [ControlAction] = []

    /// Cell item model name for tableView/collectionView data source (e.g. "ProductCell").
    public var cellTypeName: String?

    /// Whether this list element has a nested tableView or collectionView inside its cells.
    public var hasNestedList: Bool = false

    public init(
        name: String,
        type: UIKitElementType? = nil,
        customComponentName: String? = nil,
        children: [UIElementNode] = [],
        properties: [String: String] = [:]
    ) {
        self.name = name
        self.type = type
        self.customComponentName = customComponentName
        self.children = children
        self.properties = properties
    }
}
