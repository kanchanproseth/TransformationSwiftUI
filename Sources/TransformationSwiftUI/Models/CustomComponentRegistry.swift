// SPDX-License-Identifier: MIT
//
// CustomComponentRegistry.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Registry that resolves custom components alongside built-in UIKit types.
//

import Foundation

/// The result of resolving a type name against both the built-in UIKit types
/// and the custom component registry.
public enum ResolvedComponentType {
    /// A built-in UIKit element type.
    case builtIn(UIKitElementType)
    /// A custom component declared in the project.
    case custom(CustomComponentModel)
    /// An unknown or unsupported type.
    case unknown
}

/// Registry of all discovered custom UIView/UIControl subclasses in the project.
public final class CustomComponentRegistry {
    /// Creates an empty registry.
    public init() {}

    /// All discovered custom components, keyed by class name.
    public private(set) var components: [String: CustomComponentModel] = [:]

    /// Registers a discovered custom component.
    public func register(_ component: CustomComponentModel) {
        components[component.name] = component
    }

    /// Looks up a custom component by its class name.
    public func lookup(_ className: String) -> CustomComponentModel? {
        components[className]
    }

    /// Returns true if the given class name is a known custom component.
    public func isCustomComponent(_ className: String) -> Bool {
        components[className] != nil
    }

    /// Resolves a type name to either a UIKitElementType or a CustomComponentModel.
    public func resolveType(_ typeName: String?) -> ResolvedComponentType {
        guard let typeName else { return .unknown }
        let normalized = normalizeTypeName(typeName)

        if let uiKitType = UIKitElementType.from(typeName: normalized) {
            return .builtIn(uiKitType)
        }
        if let custom = components[normalized] {
            return .custom(custom)
        }
        return .unknown
    }

    /// All known UIView/UIControl base class names used to seed custom component discovery.
    public static let uiViewHierarchyBaseClasses: Set<String> = {
        var bases = Set(UIKitElementType.allCases.map { $0.typeName })
        bases.insert(Strings.uiView)
        bases.insert(Strings.uiControl)
        bases.insert(Strings.uiResponder)
        return bases
    }()

    private func normalizeTypeName(_ raw: String) -> String {
        var result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasSuffix(Strings.optionalSuffixQuestion) || result.hasSuffix(Strings.optionalSuffixExclamation) {
            result = String(result.dropLast())
        }
        if let genericIndex = result.firstIndex(of: Strings.genericStartCharacter) {
            result = String(result[..<genericIndex])
        }
        return result
    }

    private enum Strings {
        static let uiView = "UIView"
        static let uiControl = "UIControl"
        static let uiResponder = "UIResponder"
        static let optionalSuffixQuestion = "?"
        static let optionalSuffixExclamation = "!"
        static let genericStartCharacter: Character = "<"
    }
}
