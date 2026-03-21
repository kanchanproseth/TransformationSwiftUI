// SPDX-License-Identifier: MIT
//
// CustomComponentVisitor.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: SwiftSyntax visitor that discovers custom UIView/UIControl subclasses.
//

import SwiftSyntax

/// Discovers custom UIView/UIControl subclasses in Swift source files.
public class CustomComponentVisitor: SyntaxVisitor {

    /// Discovered custom component declarations.
    public private(set) var discoveries: [(name: String, superclassName: String, node: ClassDeclSyntax)] = []

    /// Known UIView hierarchy base classes to match against. Grows across passes.
    private let knownViewClasses: Set<String>

    /// Creates a visitor with a known set of base view classes.
    public init(knownViewClasses: Set<String> = CustomComponentRegistry.uiViewHierarchyBaseClasses) {
        self.knownViewClasses = knownViewClasses
        super.init(viewMode: .sourceAccurate)
    }

    /// Records classes that inherit from known UIView/UIControl types.
    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let inheritanceClause = node.inheritanceClause else {
            return .visitChildren
        }

        let className = node.name.text

        // Skip classes that are themselves known UIKit types
        if CustomComponentRegistry.uiViewHierarchyBaseClasses.contains(className) {
            return .visitChildren
        }

        // Skip UIViewController subclasses (handled by ViewControllerVisitor)
        for inheritedType in inheritanceClause.inheritedTypes {
            let typeName = inheritedType.typeName.description
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if UIKitElementType.isViewController(typeName: typeName) {
                return .visitChildren
            }
        }

        // Check each inherited type against known view classes
        for inheritedType in inheritanceClause.inheritedTypes {
            let superName = inheritedType.typeName.description
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if knownViewClasses.contains(superName) {
                discoveries.append((name: className, superclassName: superName, node: node))
                break
            }
        }

        return .visitChildren
    }
}
