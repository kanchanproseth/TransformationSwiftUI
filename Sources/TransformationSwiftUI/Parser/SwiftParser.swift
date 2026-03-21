// SPDX-License-Identifier: MIT
//
// SwiftParser.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Parses Swift source files into ViewControllerModel instances.
//

import Foundation
import SwiftSyntax
import SwiftParser

/// Parses Swift source files into view controller models.
public struct SwiftParser {

    /// Parses a Swift file URL into view controller models.
    public static func parseFile(_ url: URL) throws -> [ViewControllerModel] {
        try parseFile(url, componentRegistry: nil)
    }

    /// Parses a Swift file URL with optional custom component resolution.
    public static func parseFile(
        _ url: URL,
        componentRegistry: CustomComponentRegistry?
    ) throws -> [ViewControllerModel] {

        let source = try Parser.parse(source: String(contentsOf: url))

        let vcVisitor = ViewControllerVisitor()
        vcVisitor.walk(source)

        var results: [ViewControllerModel] = []

        for controller in vcVisitor.controllers {

            let hierarchyVisitor = ViewHierarchyVisitor(componentRegistry: componentRegistry)
            hierarchyVisitor.walk(controller.node)
            hierarchyVisitor.buildHierarchy()

            let autoLayoutVisitor = AutoLayoutVisitor()
            autoLayoutVisitor.walk(controller.node)

            let animationVisitor = AnimationVisitor()
            animationVisitor.walk(controller.node)

            // NEW: Visibility logic (isHidden, alpha, addSubview, removeFromSuperview)
            let visibilityVisitor = VisibilityLogicVisitor()
            visibilityVisitor.walk(controller.node)

            // NEW: Business logic (IBAction, target-action, delegate callbacks, navigation calls)
            let businessVisitor = BusinessLogicVisitor()
            businessVisitor.walk(controller.node)

            var model = ViewControllerModel(
                name: controller.name,
                rootElements: hierarchyVisitor.rootElements,
                constraints: autoLayoutVisitor.constraints
            )
            model.animations = animationVisitor.animations
            model.visibilityRules = visibilityVisitor.rules
            model.controlActions = businessVisitor.controlActions
            model.navigationCalls = businessVisitor.navigationCalls

            // Attach visibility rules and control actions to matching element nodes
            model.rootElements = attachMetadata(
                to: model.rootElements,
                visibilityRules: visibilityVisitor.rules,
                controlActions: businessVisitor.controlActions
            )

            results.append(model)
        }
        return results
    }

    /// Distributes visibility rules and control actions to matching element nodes by name.
    private static func attachMetadata(
        to nodes: [UIElementNode],
        visibilityRules: [VisibilityRule],
        controlActions: [ControlAction]
    ) -> [UIElementNode] {
        nodes.map { node in
            var updated = node
            updated.visibilityRules = visibilityRules.filter { $0.elementName == node.name }
            updated.controlActions = controlActions.filter { $0.controlName == node.name }
            updated.children = attachMetadata(
                to: node.children,
                visibilityRules: visibilityRules,
                controlActions: controlActions
            )
            // Detect nested list: a tableView or collectionView that contains another list node
            if node.type == .tableView || node.type == .collectionView {
                updated.hasNestedList = node.children.contains {
                    $0.type == .tableView || $0.type == .collectionView
                }
            }
            return updated
        }
    }
}
