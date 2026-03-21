// SPDX-License-Identifier: MIT
//
// ViewHierarchyVisitor.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: SwiftSyntax visitor that builds a UI element hierarchy from UIKit view declarations and relationships.
//

import SwiftSyntax

/// Builds a UI element hierarchy by visiting view declarations and addSubview calls.
public class ViewHierarchyVisitor: SyntaxVisitor {

    // Tracks variable name → UIElementNode
    private var hierarchy: [String: UIElementNode] = [:]

    // Tracks child → parent relationship
    private var parentMap: [String: String] = [:]

    /// Root elements after `buildHierarchy()` is called.
    public var rootElements: [UIElementNode] = []

    /// Optional registry for resolving custom UIView/UIControl subclasses.
    private let componentRegistry: CustomComponentRegistry?

    /// Creates a visitor with optional custom component resolution.
    public init(componentRegistry: CustomComponentRegistry? = nil) {
        self.componentRegistry = componentRegistry
        super.init(viewMode: .sourceAccurate)
    }

    /// Records variable declarations that correspond to view instances.
    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            if let identifierPattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                let name = identifierPattern.identifier.text
                let typeName = binding.typeAnnotation?.type.description
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let inferredType = typeName ?? inferredTypeName(from: binding.initializer?.value)

                let elementType: UIKitElementType?
                var customName: String? = nil

                if let registry = componentRegistry, let typeString = inferredType {
                    let resolved = registry.resolveType(typeString)
                    switch resolved {
                    case .builtIn(let uiKitType):
                        elementType = uiKitType
                    case .custom(let component):
                        elementType = component.resolvedBaseType
                        customName = component.name
                    case .unknown:
                        elementType = defaultType(for: name)
                    }
                } else {
                    elementType = UIKitElementType.from(typeName: inferredType) ?? defaultType(for: name)
                }

                if var existingNode = hierarchy[name] {
                    if existingNode.type == nil {
                        existingNode.type = elementType
                        existingNode.customComponentName = customName
                        hierarchy[name] = existingNode
                    }
                } else {
                    var newNode = UIElementNode(name: name, type: elementType)
                    newNode.customComponentName = customName
                    hierarchy[name] = newNode
                }
            }
        }
        return .visitChildren
    }

    private func normalizedName(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(Strings.selfPrefix) {
            return String(trimmed.dropFirst(Strings.selfPrefix.count))
        }
        return trimmed
    }

    private func inferredTypeName(from expression: ExprSyntax?) -> String? {
        guard let expression else { return nil }
        if let call = expression.as(FunctionCallExprSyntax.self) {
            if let identifier = call.calledExpression.as(DeclReferenceExprSyntax.self) {
                return identifier.baseName.text
            }
            if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
                return member.declName.baseName.text
            }
        }
        return nil
    }

    private func defaultType(for name: String) -> UIKitElementType? {
        switch name {
        case Strings.containerView, Strings.containerContentView:
            return .view
        default:
            return nil
        }
    }

    /// Records view hierarchy edges from addSubview and addArrangedSubview calls.
    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {

        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            return .visitChildren
        }

        let methodName = memberAccess.declName.baseName.text

        if methodName == Strings.addSubview || methodName == Strings.addArrangedSubview {

            guard
                let parentExpr = memberAccess.base?.description,
                let argument = node.arguments.first?.expression.description
            else { return .visitChildren }

            let parentName = normalizedName(parentExpr)
            let childName = normalizedName(argument)

            parentMap[childName] = parentName
        }

        return .visitChildren
    }

    /// Builds the final root element list by linking parents and children.
    public func buildHierarchy() {
        // Attach children to parents
        for (childName, parentName) in parentMap {
            if var parentNode = hierarchy[parentName] {
                if let childNode = hierarchy[childName] {
                    parentNode.children.append(childNode)
                    hierarchy[parentName] = parentNode
                }
            }
        }

        // Roots are nodes that never appear as a child
        let childNames = Set(parentMap.keys)
        rootElements = hierarchy.values.filter { !childNames.contains($0.name) }
    }

    private enum Strings {
        static let selfPrefix = "self."
        static let addSubview = "addSubview"
        static let addArrangedSubview = "addArrangedSubview"
        static let containerView = "view"
        static let containerContentView = "contentView"
    }
}
