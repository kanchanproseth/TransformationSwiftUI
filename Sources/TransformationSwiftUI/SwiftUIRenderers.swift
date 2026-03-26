// SPDX-License-Identifier: MIT
//
// SwiftUIRenderers.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: SwiftUI render strategy interfaces and component renderers.
//

import Foundation

/// Strategy interface for rendering SwiftUI view fragments.
public protocol SwiftUIRenderStrategy: Sendable {
    /// Renders the SwiftUI lines for a node at the given indentation.
    func render(
        node: UIElementNode,
        constraints: [LayoutConstraint],
        patterns: [LayoutPattern],
        indent: Int
    ) -> [String]
}

/// Renders UILabel nodes as SwiftUI Text.
public struct LabelRenderer: SwiftUIRenderStrategy {
    public init() {}

    /// Renders a Text view for the provided node.
    public func render(node: UIElementNode, constraints: [LayoutConstraint], patterns: [LayoutPattern], indent: Int) -> [String] {
        let indentString = SwiftUICodeGenerator.indentString(indent)
        let displayText = node.properties[Strings.textKey] ?? node.name
        var lines = [indentString + Strings.textPrefix + displayText + Strings.textSuffix]
        lines.append(contentsOf: SwiftUICodeGenerator.modifierLines(for: node.name, constraints: constraints, indent: indent))
        return lines
    }
}

/// Renders UIButton nodes as SwiftUI Button.
public struct ButtonRenderer: SwiftUIRenderStrategy {
    public init() {}

    /// Renders a Button view for the provided node.
    public func render(node: UIElementNode, constraints: [LayoutConstraint], patterns: [LayoutPattern], indent: Int) -> [String] {
        let indentString = SwiftUICodeGenerator.indentString(indent)
        let displayTitle = node.properties[Strings.titleKey] ?? node.name
        var lines = [indentString + Strings.buttonPrefix + displayTitle + Strings.buttonSuffix]
        lines.append(contentsOf: SwiftUICodeGenerator.modifierLines(for: node.name, constraints: constraints, indent: indent))
        return lines
    }
}

/// Renders UIImageView nodes as SwiftUI Image.
public struct ImageViewRenderer: SwiftUIRenderStrategy {
    public init() {}

    /// Renders an Image view for the provided node.
    public func render(node: UIElementNode, constraints: [LayoutConstraint], patterns: [LayoutPattern], indent: Int) -> [String] {
        let indentString = SwiftUICodeGenerator.indentString(indent)
        let imageName = node.properties[Strings.imageNameKey] ?? node.name
        var lines = [
            indentString + Strings.imagePrefix + imageName + Strings.imageSuffix,
            indentString + Strings.resizableModifier,
        ]
        lines.append(contentsOf: SwiftUICodeGenerator.modifierLines(for: node.name, constraints: constraints, indent: indent))
        return lines
    }
}

/// Renders UIStackView nodes using SwiftUI stacks.
public struct StackViewRenderer: SwiftUIRenderStrategy {
    public init() {}

    /// Renders a stack view with inferred modifiers and axis.
    public func render(node: UIElementNode, constraints: [LayoutConstraint], patterns: [LayoutPattern], indent: Int) -> [String] {
        let modifiers = SwiftUICodeGenerator.modifierLines(for: node.name, constraints: constraints, indent: indent)
        // Pass the IB-declared axis (if present) so the generator can use it directly
        return SwiftUICodeGenerator.renderStackView(node: node, constraints: constraints, patterns: patterns, indent: indent, modifiers: modifiers)
    }
}

/// Renders generic UIView nodes as SwiftUI containers.
public struct ViewRenderer: SwiftUIRenderStrategy {
    public init() {}

    /// Renders a container view based on inferred layout patterns.
    public func render(node: UIElementNode, constraints: [LayoutConstraint], patterns: [LayoutPattern], indent: Int) -> [String] {
        let modifiers = SwiftUICodeGenerator.modifierLines(for: node.name, constraints: constraints, indent: indent)
        let containerName = SwiftUICodeGenerator.containerName(for: node.children, patterns: patterns)
        return SwiftUICodeGenerator.renderContainer(name: containerName, node: node, constraints: constraints, patterns: patterns, indent: indent, modifiers: modifiers)
    }
}

/// Renders UIScrollView nodes as SwiftUI ScrollView.
public struct ScrollViewRenderer: SwiftUIRenderStrategy {
    public init() {}

    /// Renders a ScrollView container.
    public func render(node: UIElementNode, constraints: [LayoutConstraint], patterns: [LayoutPattern], indent: Int) -> [String] {
        let modifiers = SwiftUICodeGenerator.modifierLines(for: node.name, constraints: constraints, indent: indent)
        return SwiftUICodeGenerator.renderContainer(name: Strings.scrollViewName, node: node, constraints: constraints, patterns: patterns, indent: indent, modifiers: modifiers)
    }
}

/// Renders UITextField nodes as SwiftUI TextField.
public struct TextFieldRenderer: SwiftUIRenderStrategy {
    public init() {}

    /// Renders a TextField with a generated binding.
    public func render(node: UIElementNode, constraints: [LayoutConstraint], patterns: [LayoutPattern], indent: Int) -> [String] {
        let indentString = SwiftUICodeGenerator.indentString(indent)
        let bindingName = SwiftUICodeGenerator.sanitizedIdentifier(node.name) + Strings.stateSuffixText
        let placeholder = node.properties[Strings.placeholderKey] ?? node.name
        var lines = [indentString + Strings.textFieldPrefix + placeholder + Strings.textFieldInfix + bindingName + Strings.textFieldSuffix]
        lines.append(contentsOf: SwiftUICodeGenerator.modifierLines(for: node.name, constraints: constraints, indent: indent))
        return lines
    }
}

/// Renders UITextView nodes as SwiftUI TextEditor.
public struct TextViewRenderer: SwiftUIRenderStrategy {
    public init() {}

    /// Renders a TextEditor with a generated binding.
    public func render(node: UIElementNode, constraints: [LayoutConstraint], patterns: [LayoutPattern], indent: Int) -> [String] {
        let indentString = SwiftUICodeGenerator.indentString(indent)
        let bindingName = SwiftUICodeGenerator.sanitizedIdentifier(node.name) + Strings.stateSuffixText
        var lines = [indentString + Strings.textEditorPrefix + bindingName + Strings.textEditorSuffix]
        lines.append(contentsOf: SwiftUICodeGenerator.modifierLines(for: node.name, constraints: constraints, indent: indent))
        return lines
    }
}

/// Renders UISwitch nodes as SwiftUI Toggle.
public struct ToggleRenderer: SwiftUIRenderStrategy {
    public init() {}

    /// Renders a Toggle with a generated binding.
    public func render(node: UIElementNode, constraints: [LayoutConstraint], patterns: [LayoutPattern], indent: Int) -> [String] {
        let indentString = SwiftUICodeGenerator.indentString(indent)
        let bindingName = SwiftUICodeGenerator.sanitizedIdentifier(node.name) + Strings.stateSuffixIsOn
        var lines = [indentString + Strings.togglePrefix + node.name + Strings.toggleInfix + bindingName + Strings.toggleSuffix]
        lines.append(contentsOf: SwiftUICodeGenerator.modifierLines(for: node.name, constraints: constraints, indent: indent))
        return lines
    }
}

/// Renders UISlider nodes as SwiftUI Slider.
public struct SliderRenderer: SwiftUIRenderStrategy {
    public init() {}

    /// Renders a Slider with a generated binding.
    public func render(node: UIElementNode, constraints: [LayoutConstraint], patterns: [LayoutPattern], indent: Int) -> [String] {
        let indentString = SwiftUICodeGenerator.indentString(indent)
        let bindingName = SwiftUICodeGenerator.sanitizedIdentifier(node.name) + Strings.stateSuffixValue
        var lines = [indentString + Strings.sliderPrefix + bindingName + Strings.sliderSuffix]
        lines.append(contentsOf: SwiftUICodeGenerator.modifierLines(for: node.name, constraints: constraints, indent: indent))
        return lines
    }
}

/// Renders UIProgressView nodes as SwiftUI ProgressView.
public struct ProgressViewRenderer: SwiftUIRenderStrategy {
    public init() {}

    /// Renders a ProgressView with a generated binding or value.
    public func render(node: UIElementNode, constraints: [LayoutConstraint], patterns: [LayoutPattern], indent: Int) -> [String] {
        let indentString = SwiftUICodeGenerator.indentString(indent)
        let valueName = SwiftUICodeGenerator.sanitizedIdentifier(node.name) + Strings.stateSuffixProgress
        var lines = [indentString + Strings.progressViewPrefix + valueName + Strings.progressViewSuffix]
        lines.append(contentsOf: SwiftUICodeGenerator.modifierLines(for: node.name, constraints: constraints, indent: indent))
        return lines
    }
}

/// Renders UITableView and UICollectionView nodes as SwiftUI List or LazyVGrid.
/// Handles nested tables/collections inside cells, and wires `.onTapGesture` for
/// didSelect business logic.
public struct ListRenderer: SwiftUIRenderStrategy {
    public init() {}

    /// Renders a List (tableView) or LazyVGrid (collectionView) with proper cell structure.
    public func render(node: UIElementNode, constraints: [LayoutConstraint], patterns: [LayoutPattern], indent: Int) -> [String] {
        let modifiers = SwiftUICodeGenerator.modifierLines(for: node.name, constraints: constraints, indent: indent)
        let indentStr = SwiftUICodeGenerator.indentString(indent)
        let innerIndent = SwiftUICodeGenerator.indentString(indent + 1)
        let cellIndent = SwiftUICodeGenerator.indentString(indent + 2)

        let isCollectionView = node.type == .collectionView
        let cellType = node.cellTypeName ?? (isCollectionView ? "Item" : "Item")
        let hasDidSelect = node.controlActions.contains {
            $0.kind == .collectionViewDidSelect || $0.kind == .tableViewDidSelect
        }

        var lines: [String] = []

        if isCollectionView {
            // LazyVGrid for collectionView
            lines.append(indentStr + "let columns = [GridItem(.adaptive(minimum: 150))]")
            lines.append(indentStr + "LazyVGrid(columns: columns, spacing: 16) {")
            lines.append(innerIndent + "ForEach(items) { item in")
            if node.hasNestedList {
                lines.append(cellIndent + "VStack {")
                lines.append(SwiftUICodeGenerator.indentString(indent + 3) + "Text(item.title)")
                lines.append(SwiftUICodeGenerator.indentString(indent + 3) + "// TODO: Nested \(cellType)NestedView(item: item)")
                lines.append(cellIndent + "}")
            } else {
                lines.append(cellIndent + "\(cellType)CellView(item: item)")
            }
            if hasDidSelect {
                lines.append(cellIndent + ".onTapGesture { selectedItem = item }")
            }
            lines.append(innerIndent + "}")
            lines.append(indentStr + "}")
        } else {
            // List for tableView
            lines.append(indentStr + "List {")
            lines.append(innerIndent + "ForEach(items) { item in")
            if node.hasNestedList {
                lines.append(cellIndent + "VStack(alignment: .leading) {")
                lines.append(SwiftUICodeGenerator.indentString(indent + 3) + "Text(item.title)")
                lines.append(SwiftUICodeGenerator.indentString(indent + 3) + "// TODO: Nested \(cellType)NestedView(item: item)")
                lines.append(cellIndent + "}")
            } else {
                lines.append(cellIndent + "\(cellType)CellView(item: item)")
            }
            if hasDidSelect {
                lines.append(cellIndent + ".onTapGesture { selectedItem = item }")
            }
            lines.append(innerIndent + "}")
            lines.append(indentStr + "}")
        }

        lines.append(contentsOf: modifiers)
        return lines
    }
}

/// Renders UIActivityIndicatorView nodes as SwiftUI ProgressView().
public struct ActivityIndicatorRenderer: SwiftUIRenderStrategy {
    public init() {}

    /// Renders a ProgressView with default styling.
    public func render(node: UIElementNode, constraints: [LayoutConstraint], patterns: [LayoutPattern], indent: Int) -> [String] {
        let indentString = SwiftUICodeGenerator.indentString(indent)
        var lines = [indentString + Strings.progressViewEmpty]
        lines.append(contentsOf: SwiftUICodeGenerator.modifierLines(for: node.name, constraints: constraints, indent: indent))
        return lines
    }
}

/// Renders UISegmentedControl nodes as a segmented Picker.
public struct SegmentedControlRenderer: SwiftUIRenderStrategy {
    public init() {}

    /// Renders a segmented Picker from available segment titles.
    public func render(node: UIElementNode, constraints: [LayoutConstraint], patterns: [LayoutPattern], indent: Int) -> [String] {
        let indentString = SwiftUICodeGenerator.indentString(indent)
        let bindingName = SwiftUICodeGenerator.sanitizedIdentifier(node.name) + Strings.stateSuffixSelection
        var lines: [String] = []
        lines.append(indentString + Strings.pickerPrefix + node.name + Strings.pickerInfix + bindingName + Strings.openBrace)
        // Use actual segment titles from IB when available
        let segments: [String]
        if let titlesString = node.properties[Strings.segmentTitlesKey] {
            segments = titlesString.components(separatedBy: Strings.comma).filter { !$0.isEmpty }
        } else {
            segments = [Strings.segmentDefaultFirst, Strings.segmentDefaultSecond]
        }
        for (index, title) in segments.enumerated() {
            lines.append(indentString + Strings.indentUnit + Strings.textPrefix + title + Strings.textSuffix + Strings.tagPrefix + String(index) + Strings.tagSuffix)
        }
        lines.append(indentString + Strings.closingBrace)
        lines.append(indentString + Strings.pickerStyleSegmented)
        lines.append(contentsOf: SwiftUICodeGenerator.modifierLines(for: node.name, constraints: constraints, indent: indent))
        return lines
    }
}

/// Renders UIPageControl nodes as a basic TabView.
public struct PageControlRenderer: SwiftUIRenderStrategy {
    public init() {}

    /// Renders a TabView with placeholder pages.
    public func render(node: UIElementNode, constraints: [LayoutConstraint], patterns: [LayoutPattern], indent: Int) -> [String] {
        let indentString = SwiftUICodeGenerator.indentString(indent)
        var lines: [String] = []
        lines.append(indentString + Strings.tabViewOpen)
        lines.append(indentString + Strings.indentUnit + Strings.textPrefix + Strings.pageDefaultOne + Strings.textSuffix)
        lines.append(indentString + Strings.indentUnit + Strings.textPrefix + Strings.pageDefaultTwo + Strings.textSuffix)
        lines.append(indentString + Strings.closingBrace)
        lines.append(indentString + Strings.tabViewStylePage)
        lines.append(contentsOf: SwiftUICodeGenerator.modifierLines(for: node.name, constraints: constraints, indent: indent))
        return lines
    }
}

/// Renders UIVisualEffectView nodes as a material background.
public struct VisualEffectRenderer: SwiftUIRenderStrategy {
    public init() {}

    /// Renders a Rectangle with a material background as a placeholder.
    public func render(node: UIElementNode, constraints: [LayoutConstraint], patterns: [LayoutPattern], indent: Int) -> [String] {
        let indentString = SwiftUICodeGenerator.indentString(indent)
        var lines = [indentString + Strings.visualEffectMaterial]
        lines.append(contentsOf: SwiftUICodeGenerator.modifierLines(for: node.name, constraints: constraints, indent: indent))
        return lines
    }
}

private enum Strings {
    static let textKey = "text"
    static let titleKey = "title"
    static let imageNameKey = "imageName"
    static let placeholderKey = "placeholder"
    static let segmentTitlesKey = "segmentTitles"

    static let scrollViewName = "ScrollView"

    static let indentUnit = "    "

    static let textPrefix = "Text(\""
    static let textSuffix = "\")"
    static let buttonPrefix = "Button(\""
    static let buttonSuffix = "\") { }"
    static let imagePrefix = "Image(\""
    static let imageSuffix = "\")"
    static let resizableModifier = "    .resizable()"
    static let textFieldPrefix = "TextField(\""
    static let textFieldInfix = "\", text: $"
    static let textFieldSuffix = ")"
    static let textEditorPrefix = "TextEditor(text: $"
    static let textEditorSuffix = ")"
    static let togglePrefix = "Toggle(\""
    static let toggleInfix = "\", isOn: $"
    static let toggleSuffix = ")"
    static let sliderPrefix = "Slider(value: $"
    static let sliderSuffix = ")"
    static let progressViewPrefix = "ProgressView(value: "
    static let progressViewSuffix = ")"
    static let progressViewEmpty = "ProgressView()"

    static let pickerPrefix = "Picker(\""
    static let pickerInfix = "\", selection: $"
    static let pickerStyleSegmented = ".pickerStyle(.segmented)"

    static let tabViewOpen = "TabView {"
    static let tabViewStylePage = ".tabViewStyle(.page)"

    static let tagPrefix = "    .tag("
    static let tagSuffix = ")"

    static let openBrace = " {"
    static let closingBrace = "}"

    static let stateSuffixText = "Text"
    static let stateSuffixIsOn = "IsOn"
    static let stateSuffixValue = "Value"
    static let stateSuffixProgress = "Progress"
    static let stateSuffixSelection = "Selection"

    static let segmentDefaultFirst = "First"
    static let segmentDefaultSecond = "Second"

    static let pageDefaultOne = "Page 1"
    static let pageDefaultTwo = "Page 2"

    static let visualEffectMaterial = "Rectangle().fill(.ultraThinMaterial)"

    static let comma = ","
}
