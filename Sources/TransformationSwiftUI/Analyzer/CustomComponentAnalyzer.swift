// SPDX-License-Identifier: MIT
//
// CustomComponentAnalyzer.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Analyzes Swift files to discover and resolve custom UIView/UIControl subclasses.
//

import Foundation
import SwiftSyntax
import SwiftParser

/// Analyzes all Swift files in a project to discover and fully resolve custom UIView/UIControl subclasses.
public struct CustomComponentAnalyzer {

    /// Performs multi-pass discovery across all files to build a complete registry.
    ///
    /// - Pass 1: Find classes that directly inherit from known UIKit base classes.
    /// - Pass 2+: Find classes that inherit from classes discovered in previous passes.
    /// - Repeats until no new classes are found (fixed-point iteration).
    ///
    /// This handles transitive inheritance chains like: SpecialButton → RoundedButton → UIButton.
    public static func buildRegistry(from files: [URL]) -> CustomComponentRegistry {
        let registry = CustomComponentRegistry()

        // Parse all files once and cache the syntax trees to avoid re-reading
        var parsedFiles: [(url: URL, syntax: SourceFileSyntax)] = []
        for file in files {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let tree = Parser.parse(source: source)
            parsedFiles.append((url: file, syntax: tree))
        }

        // Multi-pass discovery until no new custom components are found
        var knownViewClasses = CustomComponentRegistry.uiViewHierarchyBaseClasses
        var foundNewInLastPass = true

        while foundNewInLastPass {
            foundNewInLastPass = false

            for (file, syntax) in parsedFiles {
                let visitor = CustomComponentVisitor(knownViewClasses: knownViewClasses)
                visitor.walk(syntax)

                for discovery in visitor.discoveries {
                    // Skip if already registered
                    guard registry.lookup(discovery.name) == nil else { continue }

                    let chain = resolveInheritanceChain(
                        className: discovery.name,
                        superclassName: discovery.superclassName,
                        registry: registry
                    )

                    let baseType = resolveBaseUIKitType(from: chain)

                    let (elements, constraints) = analyzeInternalStructure(classNode: discovery.node)
                    let properties = extractExposedProperties(classNode: discovery.node)
                    let drawingModel = analyzeDrawingCommands(classNode: discovery.node, className: discovery.name)
                    let animations = analyzeAnimations(classNode: discovery.node)

                    let component = CustomComponentModel(
                        name: discovery.name,
                        superclassName: discovery.superclassName,
                        resolvedBaseType: baseType,
                        inheritanceChain: chain,
                        sourceFilePath: file.path,
                        internalElements: elements,
                        internalConstraints: constraints,
                        exposedProperties: properties,
                        syntaxNode: discovery.node,
                        drawingModel: drawingModel,
                        animations: animations
                    )

                    registry.register(component)
                    knownViewClasses.insert(discovery.name)
                    foundNewInLastPass = true
                }
            }
        }

        return registry
    }

    /// Builds the full inheritance chain from the class to its UIKit base.
    private static func resolveInheritanceChain(
        className: String,
        superclassName: String,
        registry: CustomComponentRegistry
    ) -> [String] {
        var chain = [className]
        var current = superclassName

        while let customParent = registry.lookup(current) {
            chain.append(current)
            current = customParent.superclassName
        }
        // Append the terminal UIKit base class
        chain.append(current)
        return chain
    }

    /// Walks the chain to find the first UIKitElementType match.
    private static func resolveBaseUIKitType(from chain: [String]) -> UIKitElementType {
        for className in chain.reversed() {
            if let type = UIKitElementType.from(typeName: className) {
                return type
            }
        }
        return .view
    }

    /// Reuses existing visitors to analyze the internal subview structure of a custom component.
    private static func analyzeInternalStructure(
        classNode: ClassDeclSyntax
    ) -> ([UIElementNode], [LayoutConstraint]) {
        let hierarchyVisitor = ViewHierarchyVisitor()
        hierarchyVisitor.walk(classNode)
        hierarchyVisitor.buildHierarchy()

        let layoutVisitor = AutoLayoutVisitor()
        layoutVisitor.walk(classNode)

        return (hierarchyVisitor.rootElements, layoutVisitor.constraints)
    }

    /// Extracts exposed (public/internal) properties from the class for SwiftUI parameter mapping.
    private static func extractExposedProperties(
        classNode: ClassDeclSyntax
    ) -> [CustomComponentProperty] {
        let visitor = PropertyExtractorVisitor()
        visitor.walk(classNode)
        return visitor.properties
    }

    /// Extracts drawing commands from a `draw(_ rect:)` override, if present.
    private static func analyzeDrawingCommands(
        classNode: ClassDeclSyntax,
        className: String
    ) -> DrawingModel? {
        let visitor = DrawingCommandVisitor(className: className)
        visitor.walk(classNode)
        visitor.buildModel()
        return visitor.drawingModel
    }

    /// Extracts UIKit animation calls from the class body.
    private static func analyzeAnimations(
        classNode: ClassDeclSyntax
    ) -> [AnimationModel] {
        let visitor = AnimationVisitor()
        visitor.walk(classNode)
        return visitor.animations
    }
}
