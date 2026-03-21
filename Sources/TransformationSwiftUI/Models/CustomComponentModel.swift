// SPDX-License-Identifier: MIT
//
// CustomComponentModel.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Model for a custom UIView/UIControl subclass discovered in the project.
//

import Foundation
import SwiftSyntax

/// Represents a custom UIView/UIControl subclass discovered in the project.
public struct CustomComponentModel: @unchecked Sendable {
    /// The class name as declared in source (e.g., RoundedButton).
    public let name: String

    /// The immediate superclass name from the declaration (e.g., UIButton).
    public let superclassName: String

    /// The resolved base UIKit type at the root of the inheritance chain.
    public let resolvedBaseType: UIKitElementType

    /// Full inheritance chain from this class to the UIKit base.
    /// Example: ["RoundedButton", "UIButton"] or ["AnimatedCard", "CardView", "UIView"].
    public let inheritanceChain: [String]

    /// The file path where this class is defined.
    public let sourceFilePath: String

    /// The internal view hierarchy (subviews added inside this component).
    public var internalElements: [UIElementNode]

    /// Internal constraints declared inside this component.
    public var internalConstraints: [LayoutConstraint]

    /// Declared properties that should become SwiftUI parameters or bindings.
    public var exposedProperties: [CustomComponentProperty]

    /// The raw ClassDeclSyntax node for advanced analysis.
    public let syntaxNode: ClassDeclSyntax

    /// Drawing model extracted from a `draw(_ rect:)` override, if present.
    public var drawingModel: DrawingModel?

    /// UIKit animations detected inside this component's implementation.
    public var animations: [AnimationModel]

    public init(
        name: String,
        superclassName: String,
        resolvedBaseType: UIKitElementType,
        inheritanceChain: [String],
        sourceFilePath: String,
        internalElements: [UIElementNode],
        internalConstraints: [LayoutConstraint],
        exposedProperties: [CustomComponentProperty],
        syntaxNode: ClassDeclSyntax,
        drawingModel: DrawingModel? = nil,
        animations: [AnimationModel] = []
    ) {
        self.name = name
        self.superclassName = superclassName
        self.resolvedBaseType = resolvedBaseType
        self.inheritanceChain = inheritanceChain
        self.sourceFilePath = sourceFilePath
        self.internalElements = internalElements
        self.internalConstraints = internalConstraints
        self.exposedProperties = exposedProperties
        self.syntaxNode = syntaxNode
        self.drawingModel = drawingModel
        self.animations = animations
    }
}

/// A property on a custom component that can be surfaced as a SwiftUI parameter or binding.
public struct CustomComponentProperty {
    /// The property name in the original class.
    public let name: String

    /// The Swift type name as declared.
    public let typeName: String

    /// True when the declaration has a default value.
    public let hasDefaultValue: Bool

    /// The access level parsed from the declaration.
    public let accessLevel: PropertyAccessLevel

    /// True when the property maps naturally to a SwiftUI binding (String, Bool, Double, etc.).
    public let isBindable: Bool

    public init(
        name: String,
        typeName: String,
        hasDefaultValue: Bool,
        accessLevel: PropertyAccessLevel,
        isBindable: Bool
    ) {
        self.name = name
        self.typeName = typeName
        self.hasDefaultValue = hasDefaultValue
        self.accessLevel = accessLevel
        self.isBindable = isBindable
    }
}

/// Access level extracted from a Swift property declaration.
public enum PropertyAccessLevel {
    /// Public access.
    case `public`

    /// Internal (module) access.
    case `internal`

    /// Private access limited to the enclosing type.
    case `private`

    /// File-private access limited to the declaring file.
    case `fileprivate`
}
