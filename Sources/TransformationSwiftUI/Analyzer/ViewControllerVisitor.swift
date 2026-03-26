// SPDX-License-Identifier: MIT
//
// ViewControllerVisitor.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: SwiftSyntax visitor that finds UIViewController subclasses in source files.
//

import SwiftSyntax

/// Visits class declarations and collects UIViewController subclasses.
public class ViewControllerVisitor: SyntaxVisitor {

    /// Discovered view controller declarations.
    public var controllers: [(name: String, node: ClassDeclSyntax)] = []

    /// Creates a visitor configured for source-accurate parsing.
    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    /// Records classes that inherit from UIViewController.
    override public func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.inheritanceClause?.inheritedTypes.contains(where: { UIKitElementType.isViewController(typeName: $0.type.description) }) == true {
            controllers.append((name: node.name.text, node: node))
        }
        return .visitChildren
    }

}
