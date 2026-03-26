// SPDX-License-Identifier: MIT
//
// CustomComponentRenderer.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Generates SwiftUI view definitions for custom components.
//

import Foundation

/// Generates a standalone SwiftUI View struct definition for a custom component.
public struct CustomComponentDefinitionGenerator {

    /// Generates a SwiftUI file string for the given custom component.
    public static func generate(for component: CustomComponentModel) -> String {
        var lines: [String] = []
        lines.append(Strings.importSwiftUI)
        lines.append(Strings.empty)
        lines.append(Strings.convertedFromPrefix + component.name + Strings.convertedFromSeparator + component.inheritanceChain.dropFirst().joined(separator: Strings.inheritanceSeparator))
        lines.append(Strings.structPrefix + component.name + Strings.viewTypeSuffix)

        // Generate exposed properties as SwiftUI parameters
        for prop in component.exposedProperties {
            if prop.isBindable {
                lines.append(Strings.indentUnit + Strings.bindingVarPrefix + prop.name + Strings.bindingVarInfix + prop.typeName)
            } else if prop.hasDefaultValue {
                lines.append(Strings.indentUnit + Strings.varPrefix + prop.name + Strings.bindingVarInfix + prop.typeName)
            } else {
                lines.append(Strings.indentUnit + Strings.letPrefix + prop.name + Strings.bindingVarInfix + prop.typeName)
            }
        }

        // Generate @State for internal interactive controls
        let stateLines = SwiftUICodeGenerator.buildStateDeclarations(from: component.internalElements)
        if !stateLines.isEmpty {
            if !component.exposedProperties.isEmpty {
                lines.append(Strings.empty)
            }
            lines.append(contentsOf: stateLines.map { Strings.indentUnit + $0 })
        }

        // Generate @State for animation-driven properties
        let animStateLines = AnimationRenderer.buildAnimationStateDeclarations(
            from: component.animations,
            existingElements: component.internalElements
        )
        if !animStateLines.isEmpty {
            lines.append(contentsOf: animStateLines.map { Strings.indentUnit + $0 })
        }

        lines.append(Strings.empty)
        lines.append(Strings.bodyLine)

        // If the component has custom drawing, delegate to DrawingRenderer
        if let drawingModel = component.drawingModel, !drawingModel.segments.isEmpty {
            let drawingLines = drawingBodyLines(for: drawingModel, indent: 2)
            lines.append(contentsOf: drawingLines)
        } else {
            // Render internal subview structure if available
            let patterns = LayoutPatternEngine.inferPatterns(from: component.internalConstraints)
            let bodyLines = SwiftUICodeGenerator.renderNodes(
                component.internalElements,
                constraints: component.internalConstraints,
                patterns: patterns,
                indent: 2
            )

            if bodyLines.isEmpty {
                // Fallback: render a sensible default based on the resolved UIKit base type
                lines.append(contentsOf: renderBaseTypeFallback(component: component, indent: 2))
            } else {
                lines.append(contentsOf: bodyLines)
            }
        }

        // Append .onAppear for component-level animations
        let onAppearLines = AnimationRenderer.onAppearBlock(from: component.animations, indent: 2)
        lines.append(contentsOf: onAppearLines)

        lines.append(Strings.indentUnit + Strings.closingBrace)
        lines.append(Strings.closingBrace)
        lines.append(Strings.empty)
        lines.append(Strings.structPrefix + component.name + Strings.previewSuffix)
        lines.append(Strings.previewStaticLine)
        // Provide default init args for bindable properties
        let bindableProps = component.exposedProperties.filter { $0.isBindable }
        if bindableProps.isEmpty {
            lines.append(Strings.doubleIndent + component.name + Strings.viewInit)
        } else {
            let args = bindableProps.map { prop -> String in
                let constant = bindableConstant(for: prop.typeName)
                return prop.name + Strings.bindingConstantInfix + constant + Strings.closeParen
            }.joined(separator: Strings.commaSpace)
            lines.append(Strings.doubleIndent + component.name + Strings.viewOpen + args + Strings.closeParen)
        }
        lines.append(Strings.indentUnit + Strings.closingBrace)
        lines.append(Strings.closingBrace)
        return lines.joined(separator: Strings.newline)
    }

    /// Generates body lines that embed a DrawingRenderer output for a component with custom drawing.
    private static func drawingBodyLines(for drawingModel: DrawingModel, indent: Int) -> [String] {
        // For simple shapes: wrap Shape in a body that uses it with fill/stroke
        // For complex Canvas: inline the Canvas body
        if drawingModel.isSimpleShape {
            let pad = SwiftUICodeGenerator.indentString(indent)
            let fillColor = drawingModel.segments.first?.fillColor ?? "Color.primary"
            return ["\(pad)\(drawingModel.className)().fill(\(fillColor))"]
        } else {
            let pad = SwiftUICodeGenerator.indentString(indent)
            let pad3 = SwiftUICodeGenerator.indentString(indent + 1)
            return [
                "\(pad)Canvas { context, size in",
                "\(pad3)// Custom drawing — see \(drawingModel.className)View generated file",
                "\(pad)}",
            ]
        }
    }

    private static func renderBaseTypeFallback(component: CustomComponentModel, indent: Int) -> [String] {
        let pad = SwiftUICodeGenerator.indentString(indent)
        switch component.resolvedBaseType {
        case .button:
            return [pad + Strings.buttonPrefix + component.name + Strings.buttonSuffix]
        case .label:
            return [pad + Strings.textPrefix + component.name + Strings.textSuffix]
        case .imageView, .image:
            return [
                pad + Strings.imagePrefix + component.name + Strings.imageSuffix,
                pad + Strings.resizableModifier,
            ]
        case .textField:
            return [pad + Strings.textFieldPrefix + component.name + Strings.textFieldInfix + Strings.emptyStringLiteral + Strings.textFieldSuffix]
        case .textView:
            return [pad + Strings.textEditorPrefix + Strings.emptyStringLiteral + Strings.textEditorSuffix]
        case .toggleSwitch:
            return [pad + Strings.togglePrefix + component.name + Strings.toggleInfix + Strings.falseLiteral + Strings.toggleSuffix]
        case .slider:
            return [pad + Strings.sliderPrefix + Strings.zeroLiteral + Strings.sliderSuffix]
        case .progressView:
            return [pad + Strings.progressViewEmpty]
        case .scrollView:
            return [pad + Strings.scrollViewOpen + Strings.emptyView + Strings.scrollViewClose]
        default:
            return [
                pad + Strings.customComponentCommentPrefix + component.name + Strings.customComponentCommentInfix + component.resolvedBaseType.typeName,
                pad + Strings.emptyView,
            ]
        }
    }

    private static func bindableConstant(for typeName: String) -> String {
        let base = typeName.replacingOccurrences(of: Strings.optionalMark, with: Strings.empty)
            .replacingOccurrences(of: Strings.implicitlyUnwrappedMark, with: Strings.empty)
        switch base {
        case Strings.typeString: return Strings.emptyStringLiteral
        case Strings.typeBool: return Strings.falseLiteral
        case Strings.typeDouble, Strings.typeFloat, Strings.typeCGFloat: return Strings.zeroLiteral
        case Strings.typeInt: return Strings.zeroLiteral
        default: return Strings.placeholderLiteral
        }
    }

    private enum Strings {
        static let empty = ""
        static let newline = "\n"
        static let commaSpace = ", "
        static let indentUnit = "    "
        static let doubleIndent = "        "

        static let importSwiftUI = "import SwiftUI"
        static let convertedFromPrefix = "/// Converted from "
        static let convertedFromSeparator = " : "
        static let inheritanceSeparator = " : "
        static let structPrefix = "struct "
        static let viewTypeSuffix = "View: View {"
        static let previewSuffix = "View_Previews: PreviewProvider {"
        static let previewStaticLine = "    static var previews: some View {"
        static let bodyLine = "    var body: some View {"
        static let viewInit = "View()"
        static let viewOpen = "View("
        static let closingBrace = "}"

        static let bindingVarPrefix = "@Binding var "
        static let varPrefix = "var "
        static let letPrefix = "let "
        static let bindingVarInfix = ": "
        static let bindingConstantInfix = ": .constant("

        static let textPrefix = "Text(\""
        static let textSuffix = "\")"
        static let buttonPrefix = "Button(\""
        static let buttonSuffix = "\") { }"
        static let imagePrefix = "Image(\""
        static let imageSuffix = "\")"
        static let resizableModifier = "    .resizable()"
        static let textFieldPrefix = "TextField(\""
        static let textFieldInfix = "\", text: .constant("
        static let textFieldSuffix = "))"
        static let textEditorPrefix = "TextEditor(text: .constant("
        static let textEditorSuffix = "))"
        static let togglePrefix = "Toggle(\""
        static let toggleInfix = "\", isOn: .constant("
        static let toggleSuffix = "))"
        static let sliderPrefix = "Slider(value: .constant("
        static let sliderSuffix = "))"
        static let progressViewEmpty = "ProgressView()"
        static let scrollViewOpen = "ScrollView { "
        static let scrollViewClose = " }"
        static let emptyView = "EmptyView()"

        static let customComponentCommentPrefix = "// Custom component: "
        static let customComponentCommentInfix = " based on "

        static let optionalMark = "?"
        static let implicitlyUnwrappedMark = "!"

        static let typeString = "String"
        static let typeBool = "Bool"
        static let typeDouble = "Double"
        static let typeFloat = "Float"
        static let typeCGFloat = "CGFloat"
        static let typeInt = "Int"

        static let closeParen = ")"

        static let emptyStringLiteral = "\"\""
        static let falseLiteral = "false"
        static let zeroLiteral = "0"
        static let placeholderLiteral = "/* value */"
    }
}

/// SwiftUIRenderStrategy that renders a reference to a custom component's SwiftUI view
/// when it appears inside a UIViewController's view hierarchy.
struct CustomComponentReferenceRenderer: SwiftUIRenderStrategy {
    let component: CustomComponentModel

    func render(
        node: UIElementNode,
        constraints: [LayoutConstraint],
        patterns: [LayoutPattern],
        indent: Int
    ) -> [String] {
        let pad = SwiftUICodeGenerator.indentString(indent)
        var lines: [String] = []

        let bindableProps = component.exposedProperties.filter { $0.isBindable }

        if component.exposedProperties.isEmpty {
            lines.append(pad + Strings.viewInitPrefix + component.name + Strings.viewInitSuffix)
        } else if bindableProps.isEmpty {
            // All properties have defaults or are non-bindable; use a simplified call
            lines.append(pad + Strings.viewInitPrefix + component.name + Strings.viewInitSuffix)
        } else {
            // Provide placeholder bindings for bindable properties
            var args: [String] = []
            for prop in bindableProps {
                let constant = placeholderConstant(for: prop.typeName)
                args.append(prop.name + Strings.bindingConstantInfix + constant + Strings.closeParen)
            }
            let argString = args.joined(separator: Strings.commaSpace)
            lines.append(pad + Strings.viewInitPrefix + component.name + Strings.viewOpen + argString + Strings.closeParen)
        }

        lines.append(contentsOf: SwiftUICodeGenerator.modifierLines(
            for: node.name,
            constraints: constraints,
            indent: indent
        ))

        return lines
    }

    private func placeholderConstant(for typeName: String) -> String {
        let base = typeName.replacingOccurrences(of: Strings.optionalMark, with: Strings.empty)
            .replacingOccurrences(of: Strings.implicitlyUnwrappedMark, with: Strings.empty)
        switch base {
        case Strings.typeString: return Strings.emptyStringLiteral
        case Strings.typeBool: return Strings.falseLiteral
        case Strings.typeDouble, Strings.typeFloat, Strings.typeCGFloat: return Strings.zeroLiteral
        case Strings.typeInt: return Strings.zeroLiteral
        default: return Strings.placeholderLiteral
        }
    }

    private enum Strings {
        static let empty = ""
        static let commaSpace = ", "

        static let viewInitPrefix = ""
        static let viewInitSuffix = "View()"
        static let viewOpen = "View("
        static let bindingConstantInfix = ": .constant("
        static let closeParen = ")"

        static let optionalMark = "?"
        static let implicitlyUnwrappedMark = "!"

        static let typeString = "String"
        static let typeBool = "Bool"
        static let typeDouble = "Double"
        static let typeFloat = "Float"
        static let typeCGFloat = "CGFloat"
        static let typeInt = "Int"

        static let emptyStringLiteral = "\"\""
        static let falseLiteral = "false"
        static let zeroLiteral = "0"
        static let placeholderLiteral = "/* value */"
    }
}
