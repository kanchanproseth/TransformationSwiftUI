// SPDX-License-Identifier: MIT
//
// SwiftUICodeGenerator.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Generates SwiftUI source code from parsed UIKit view controller models.
//

import Foundation
import SwiftUI

/// Generates SwiftUI source code from parsed UIKit view controller models.
public struct SwiftUICodeGenerator {
    /// Active registry for custom component resolution during a generation pass.
    /// Set before calling generateRuleBased and cleared after.
    nonisolated(unsafe) static var activeRegistry: CustomComponentRegistry?

    /// Active animations for the current generation pass.
    /// Set before calling renderNodes/renderNode so modifiers can be appended per element.
    nonisolated(unsafe) static var activeAnimations: [AnimationModel] = []

    /// Builds a SwiftUI view file as a single string.
    static func generate(for controller: ViewControllerModel) -> String {
        generate(for: controller, aiProvider: nil, config: .default, ragIndex: nil, ragConfig: .default, componentRegistry: nil)
    }

    /// Builds a SwiftUI view file, allowing an AI layer to override rule-based output.
    public static func generate(
        for controller: ViewControllerModel,
        aiProvider: AIConversionProvider?,
        config: AIConversionConfig = .default,
        ragIndex: RAGIndex? = nil,
        ragConfig: RAGConfig = .default,
        componentRegistry: CustomComponentRegistry? = nil
    ) -> String {
        activeRegistry = componentRegistry
        activeAnimations = controller.animations
        defer {
            activeRegistry = nil
            activeAnimations = []
        }

        let patterns = LayoutPatternEngine.inferPatterns(from: controller.constraints)
        let hints = LayoutPatternEngine.inferHints(from: controller.constraints)

        if let aiProvider {
            let router = AIConversionRouter(provider: aiProvider, config: config)
            let contextChunks: [CodeChunk]
            if let ragIndex, ragConfig.enabled {
                let query = RAGQueryBuilder.build(for: controller)
                contextChunks = ragIndex.retrieve(query: query, topK: ragConfig.topK)
            } else {
                contextChunks = []
            }
            if let aiOutput = router.generate(for: controller, patterns: patterns, hints: hints, contextChunks: contextChunks) {
                return aiOutput
            }
        }

        return generateRuleBased(for: controller, patterns: patterns)
    }

    private static func generateRuleBased(for controller: ViewControllerModel, patterns: [LayoutPattern]) -> String {
        var lines: [String] = []
        lines.append(Strings.importSwiftUI)
        lines.append(Strings.empty)
        lines.append(Strings.structPrefix + controller.name + Strings.viewTypeSuffix)

        let stateLines = buildStateDeclarations(from: controller.rootElements)
        let animStateLines = AnimationRenderer.buildAnimationStateDeclarations(
            from: controller.animations,
            existingElements: controller.rootElements
        )
        // Visibility @State declarations (isHidden → Bool, alpha → opacity)
        let visibilityStateLines = buildVisibilityStateDeclarations(from: controller.visibilityRules)
        // List item selection state for tableView/collectionView didSelect
        let listStateLines = buildListStateDeclarations(from: controller.rootElements, controlActions: controller.controlActions)

        let allStateLines = stateLines + animStateLines + visibilityStateLines + listStateLines
        if !allStateLines.isEmpty {
            lines.append(contentsOf: allStateLines.map { Strings.indentUnit + $0 })
            lines.append(Strings.empty)
        }

        // Business logic action summary as a comment block
        if !controller.controlActions.isEmpty {
            lines.append(Strings.indentUnit + "// MARK: - Actions (migrated from UIKit)")
            for action in controller.controlActions {
                lines.append(Strings.indentUnit + "// \(action.kind.rawValue): \(action.handlerName) — \(action.behaviorSummary)")
            }
            lines.append(Strings.empty)
        }

        lines.append(Strings.bodyLine)
        let bodyLines = renderNodes(controller.rootElements, constraints: controller.constraints, patterns: patterns, indent: 2)
        if bodyLines.isEmpty {
            lines.append(Strings.doubleIndent + Strings.emptyView)
        } else {
            lines.append(contentsOf: bodyLines)
        }
        // Append .onAppear block for appear-context animations
        let onAppearLines = AnimationRenderer.onAppearBlock(from: controller.animations, indent: 2)
        lines.append(contentsOf: onAppearLines)
        lines.append(Strings.indentUnit + Strings.closingBrace)
        lines.append(Strings.closingBrace)
        lines.append(Strings.empty)
        lines.append(Strings.structPrefix + controller.name + Strings.previewSuffix)
        lines.append(Strings.previewStaticLine)
        lines.append(Strings.doubleIndent + controller.name + Strings.viewInit)
        lines.append(Strings.indentUnit + Strings.closingBrace)
        lines.append(Strings.closingBrace)
        return lines.joined(separator: Strings.newline)
    }

    /// Generates `@State private var isXxxVisible: Bool` declarations for each unique
    /// element name that has a visibility mutation.
    static func buildVisibilityStateDeclarations(from rules: [VisibilityRule]) -> [String] {
        var seen: Set<String> = []
        var lines: [String] = []
        for rule in rules {
            let baseName = sanitizedIdentifier(rule.elementName)
            switch rule.kind {
            case .hidden, .visible, .animatedToggle:
                let name = "is\(baseName.prefix(1).uppercased() + baseName.dropFirst())Visible"
                if seen.insert(name).inserted {
                    // Default visible; individual views can start hidden based on initial UIKit state
                    let defaultValue = (rule.kind == .hidden) ? "false" : "true"
                    lines.append("@State private var \(name): Bool = \(defaultValue)")
                }
            case .alphaZero, .alphaOne, .alphaValue:
                let name = baseName + "Opacity"
                if seen.insert(name).inserted {
                    let defaultValue: String
                    switch rule.kind {
                    case .alphaZero: defaultValue = "0.0"
                    case .alphaOne:  defaultValue = "1.0"
                    default:         defaultValue = "1.0"
                    }
                    lines.append("@State private var \(name): Double = \(defaultValue)")
                }
            case .addSubview:
                let name = "isShowing\(baseName.prefix(1).uppercased() + baseName.dropFirst())"
                if seen.insert(name).inserted {
                    lines.append("@State private var \(name): Bool = false")
                }
            case .removeFromSuperview:
                let name = "isShowing\(baseName.prefix(1).uppercased() + baseName.dropFirst())"
                if seen.insert(name).inserted {
                    lines.append("@State private var \(name): Bool = true")
                }
            }
        }
        return lines
    }

    /// Generates `@State private var selectedItem: ItemModel?` declarations for
    /// tableView / collectionView nodes that have didSelect actions.
    static func buildListStateDeclarations(from roots: [UIElementNode], controlActions: [ControlAction]) -> [String] {
        var seen: Set<String> = []
        var lines: [String] = []
        let nodes = collectNodes(from: roots)
        let hasDidSelect = controlActions.contains {
            $0.kind == .tableViewDidSelect || $0.kind == .collectionViewDidSelect
        }
        guard hasDidSelect else { return [] }
        for node in nodes where node.type == .tableView || node.type == .collectionView {
            let cellType = node.cellTypeName ?? "Item"
            let name = "selectedItem"
            if seen.insert(name + cellType).inserted {
                lines.append("@State private var \(name): \(cellType)Model? = nil")
            }
        }
        return lines
    }

    /// Creates @State declarations for controls that require bindings.
    public static func buildStateDeclarations(from roots: [UIElementNode]) -> [String] {
        let nodes = collectNodes(from: roots)
        var lines: [String] = []
        var seen: Set<String> = []

        for node in nodes {
            guard let type = node.type else { continue }
            let baseName = sanitizedIdentifier(node.name)
            switch type {
            case .textField, .textView:
                let name = baseName + Strings.stateSuffixText
                if seen.insert(name).inserted {
                    lines.append(Strings.stateVarPrefix + name + Strings.stateStringInitializer)
                }
            case .toggleSwitch:
                let name = baseName + Strings.stateSuffixIsOn
                if seen.insert(name).inserted {
                    lines.append(Strings.stateVarPrefix + name + Strings.stateBoolInitializer)
                }
            case .slider:
                let name = baseName + Strings.stateSuffixValue
                if seen.insert(name).inserted {
                    lines.append(Strings.stateVarPrefix + name + Strings.stateDoubleInitializer)
                }
            case .segmentedControl:
                let name = baseName + Strings.stateSuffixSelection
                if seen.insert(name).inserted {
                    lines.append(Strings.stateVarPrefix + name + Strings.stateIntInitializer)
                }
            case .progressView:
                let name = baseName + Strings.stateSuffixProgress
                if seen.insert(name).inserted {
                    lines.append(Strings.letPrefix + name + Strings.stateDoubleInitializer)
                }
            default:
                break
            }
        }

        return lines
    }

    /// Renders a collection of nodes into SwiftUI view builder lines.
    static func renderNodes(_ nodes: [UIElementNode], constraints: [LayoutConstraint], patterns: [LayoutPattern], indent: Int) -> [String] {
        guard !nodes.isEmpty else { return [] }
        if nodes.count == 1 {
            return renderNode(nodes[0], constraints: constraints, patterns: patterns, indent: indent)
        }

        var lines: [String] = []
        let indentString = indentString(indent)
        let containerName = containerName(for: nodes, patterns: patterns)
        lines.append(indentString + containerName + Strings.openBrace)
        for node in nodes {
            lines.append(contentsOf: renderNode(node, constraints: constraints, patterns: patterns, indent: indent + 1))
        }
        lines.append(indentString + Strings.closingBrace)
        return lines
    }

    private static let renderers: [UIKitElementType: any SwiftUIRenderStrategy] = [
        .label: LabelRenderer(),
        .button: ButtonRenderer(),
        .imageView: ImageViewRenderer(),
        .image: ImageViewRenderer(),
        .stackView: StackViewRenderer(),
        .view: ViewRenderer(),
        .scrollView: ScrollViewRenderer(),
        .textField: TextFieldRenderer(),
        .textView: TextViewRenderer(),
        .toggleSwitch: ToggleRenderer(),
        .slider: SliderRenderer(),
        .progressView: ProgressViewRenderer(),
        .tableView: ListRenderer(),
        .collectionView: ListRenderer(),
        .activityIndicatorView: ActivityIndicatorRenderer(),
        .segmentedControl: SegmentedControlRenderer(),
        .pageControl: PageControlRenderer(),
        .visualEffectView: VisualEffectRenderer(),
    ]

    /// Renders a single node based on its UIKit type, with custom component support.
    private static func renderNode(_ node: UIElementNode, constraints: [LayoutConstraint], patterns: [LayoutPattern], indent: Int) -> [String] {
        // Prefer custom component rendering when a custom component name is resolved
        if let customName = node.customComponentName,
           let component = activeRegistry?.lookup(customName) {
            let renderer = CustomComponentReferenceRenderer(component: component)
            var lines = renderer.render(node: node, constraints: constraints, patterns: patterns, indent: indent)
            lines.append(contentsOf: AnimationRenderer.modifierLines(for: node.name, animations: activeAnimations, indent: indent))
            return lines
        }

        if let type = node.type, let renderer = renderers[type] {
            var lines = renderer.render(node: node, constraints: constraints, patterns: patterns, indent: indent)
            lines.append(contentsOf: AnimationRenderer.modifierLines(for: node.name, animations: activeAnimations, indent: indent))
            return lines
        }

        var lines = renderFallback(node: node, constraints: constraints, patterns: patterns, indent: indent)
        lines.append(contentsOf: AnimationRenderer.modifierLines(for: node.name, animations: activeAnimations, indent: indent))
        return lines
    }

    private static func renderFallback(
        node: UIElementNode,
        constraints: [LayoutConstraint],
        patterns: [LayoutPattern],
        indent: Int
    ) -> [String] {
        let indentString = indentString(indent)
        let modifiers = modifierLines(for: node.name, constraints: constraints, indent: indent)
        if node.children.isEmpty {
            var lines = [
                indentString + Strings.groupOpen,
                indentString + Strings.indentUnit + Strings.emptyView,
                indentString + Strings.closingBrace,
            ]
                        lines.append(contentsOf: modifiers)
            return lines
        }

        let containerName = containerName(for: node.children, patterns: patterns)
        return renderContainer(name: containerName, node: node, constraints: constraints, patterns: patterns, indent: indent, modifiers: modifiers)
    }

    /// Renders container nodes like Group, ZStack, VStack, HStack, and ScrollView.
    static func renderContainer(name: String, node: UIElementNode, constraints: [LayoutConstraint], patterns: [LayoutPattern], indent: Int, modifiers: [String]) -> [String] {
        let indentString = indentString(indent)
        var lines: [String] = []
        lines.append(indentString + name + Strings.openBrace)
        if node.children.isEmpty {
            lines.append(indentString + Strings.indentUnit + Strings.emptyView)
        } else {
            for child in node.children {
                lines.append(contentsOf: renderNode(child, constraints: constraints, patterns: patterns, indent: indent + 1))
            }
        }
        lines.append(indentString + Strings.closingBrace)
        lines.append(contentsOf: modifiers)
        return lines
    }

    /// Renders list-based UIKit components into SwiftUI List output.
    static func renderList(node: UIElementNode, constraints: [LayoutConstraint], patterns: [LayoutPattern], indent: Int, modifiers: [String]) -> [String] {
        let indentString = indentString(indent)
        var lines: [String] = []
        lines.append(indentString + Strings.listOpen)
        if node.children.isEmpty {
            lines.append(indentString + Strings.indentUnit + Strings.textRow)
        } else {
            for child in node.children {
                lines.append(contentsOf: renderNode(child, constraints: constraints, patterns: patterns, indent: indent + 1))
            }
        }
        lines.append(indentString + Strings.closingBrace)
        lines.append(contentsOf: modifiers)
        return lines
    }

    /// Captures inferred UIStackView configuration for SwiftUI stacks.
    private struct StackConfiguration {
        let axis: StackAxis
        let spacing: Double?
        let alignment: String?

        var name: String {
            axis == .vertical ? Strings.vStack : Strings.hStack
        }
    }

    private enum StackAxis {
        case vertical
        case horizontal
    }

    /// Renders a UIStackView as VStack/HStack with inferred spacing and alignment.
    static func renderStackView(
        node: UIElementNode,
        constraints: [LayoutConstraint],
        patterns: [LayoutPattern],
        indent: Int,
        modifiers: [String]
    ) -> [String] {
        let config = stackConfiguration(for: node, constraints: constraints, patterns: patterns)
        let indentString = indentString(indent)
        var args: [String] = []
        if let alignment = config.alignment {
            args.append(Strings.alignmentPrefix + alignment)
        }
        if let spacing = config.spacing {
            args.append(Strings.spacingPrefix + formatNumber(spacing))
        }
        let headerArguments = args.isEmpty ? Strings.empty : Strings.openParen + args.joined(separator: Strings.commaSpace) + Strings.closeParen
        var lines: [String] = []
        lines.append(indentString + config.name + headerArguments + Strings.openBrace)
        if node.children.isEmpty {
            lines.append(indentString + Strings.indentUnit + Strings.emptyView)
        } else {
            for child in node.children {
                lines.append(contentsOf: renderNode(child, constraints: constraints, patterns: patterns, indent: indent + 1))
            }
        }
        lines.append(indentString + Strings.closingBrace)
        lines.append(contentsOf: modifiers)
        return lines
    }

    /// Determines stack axis, spacing, and alignment from IB properties, patterns, and constraints.
    private static func stackConfiguration(
        for node: UIElementNode,
        constraints: [LayoutConstraint],
        patterns: [LayoutPattern]
    ) -> StackConfiguration {
        let childNames = Set(node.children.map { $0.name })

        // IB explicitly encodes axis — use it directly when available
        let axis: StackAxis
        if let ibAxis = node.properties[Strings.axisKey] {
            axis = ibAxis == Strings.axisVertical ? .vertical : .horizontal
        } else {
            let verticalMatch = bestPatternSize(for: .vStack, in: patterns, childNames: childNames)
            let horizontalMatch = bestPatternSize(for: .hStack, in: patterns, childNames: childNames)
            if verticalMatch > horizontalMatch {
                axis = .vertical
            } else if horizontalMatch > verticalMatch {
                axis = .horizontal
            } else {
                axis = inferAxisFromConstraints(childNames: childNames, constraints: constraints)
            }
        }

        // IB may also specify spacing directly
        let spacing: Double?
        if let ibSpacing = node.properties[Strings.spacingKey].flatMap({ Double($0) }) {
            spacing = ibSpacing
        } else {
            spacing = inferSpacing(childNames: childNames, axis: axis, constraints: constraints)
        }

        let alignment = inferAlignment(childNames: childNames, axis: axis, constraints: constraints)
        return StackConfiguration(axis: axis, spacing: spacing, alignment: alignment)
    }

    private static func bestPatternSize(
        for type: LayoutPatternType,
        in patterns: [LayoutPattern],
        childNames: Set<String>
    ) -> Int {
        var best = 0
        for pattern in patterns where pattern.type == type {
            let elements = Set(pattern.elements)
            if elements.isSubset(of: childNames) {
                best = max(best, pattern.elements.count)
            }
        }
        return best
    }

    private static func inferAxisFromConstraints(
        childNames: Set<String>,
        constraints: [LayoutConstraint]
    ) -> StackAxis {
        var verticalCount = 0
        var horizontalCount = 0
        for constraint in constraints {
            guard let secondItem = constraint.secondItem else { continue }
            guard childNames.contains(constraint.firstItem), childNames.contains(secondItem) else { continue }

            if isVertical(constraint.firstAttribute) || isVertical(constraint.secondAttribute ?? .unknown) {
                verticalCount += 1
            }
            if isHorizontal(constraint.firstAttribute) || isHorizontal(constraint.secondAttribute ?? .unknown) {
                horizontalCount += 1
            }
        }

        if verticalCount == 0 && horizontalCount == 0 {
            return .vertical
        }
        return verticalCount >= horizontalCount ? .vertical : .horizontal
    }

    private static func inferSpacing(
        childNames: Set<String>,
        axis: StackAxis,
        constraints: [LayoutConstraint]
    ) -> Double? {
        var values: [Double] = []
        for constraint in constraints {
            guard let secondItem = constraint.secondItem else { continue }
            guard childNames.contains(constraint.firstItem), childNames.contains(secondItem) else { continue }
            guard isSpacingConstraint(constraint, axis: axis) else { continue }
            if let constant = constraint.constant {
                values.append(abs(constant))
            }
        }
        guard !values.isEmpty else { return nil }
        let total = values.reduce(0, +)
        return total / Double(values.count)
    }

    private static func inferAlignment(
        childNames: Set<String>,
        axis: StackAxis,
        constraints: [LayoutConstraint]
    ) -> String? {
        var counts: [String: Int] = [:]
        for constraint in constraints {
            guard let secondItem = constraint.secondItem else { continue }
            guard childNames.contains(constraint.firstItem), childNames.contains(secondItem) else { continue }

            switch axis {
            case .vertical:
                if constraint.firstAttribute == .leading, constraint.secondAttribute == .leading {
                    counts[Strings.alignmentLeading, default: 0] += 1
                } else if constraint.firstAttribute == .trailing, constraint.secondAttribute == .trailing {
                    counts[Strings.alignmentTrailing, default: 0] += 1
                } else if constraint.firstAttribute == .centerX, constraint.secondAttribute == .centerX {
                    counts[Strings.alignmentCenter, default: 0] += 1
                }
            case .horizontal:
                if constraint.firstAttribute == .top, constraint.secondAttribute == .top {
                    counts[Strings.alignmentTop, default: 0] += 1
                } else if constraint.firstAttribute == .bottom, constraint.secondAttribute == .bottom {
                    counts[Strings.alignmentBottom, default: 0] += 1
                } else if constraint.firstAttribute == .centerY, constraint.secondAttribute == .centerY {
                    counts[Strings.alignmentCenter, default: 0] += 1
                }
            }
        }

        let best = counts.max { $0.value < $1.value }
        return best?.key
    }

    private static func isSpacingConstraint(_ constraint: LayoutConstraint, axis: StackAxis) -> Bool {
        switch axis {
        case .vertical:
            return (constraint.firstAttribute == .top && constraint.secondAttribute == .bottom)
                || (constraint.firstAttribute == .bottom && constraint.secondAttribute == .top)
        case .horizontal:
            return (constraint.firstAttribute == .leading && constraint.secondAttribute == .trailing)
                || (constraint.firstAttribute == .trailing && constraint.secondAttribute == .leading)
                || (constraint.firstAttribute == .left && constraint.secondAttribute == .right)
                || (constraint.firstAttribute == .right && constraint.secondAttribute == .left)
        }
    }

    static func containerName(for nodes: [UIElementNode], patterns: [LayoutPattern]) -> String {
        let childNames = Set(nodes.map { $0.name })
        for pattern in patterns where pattern.type == .zStack {
            let elements = Set(pattern.elements)
            if elements.isSubset(of: childNames), elements.count >= 2 {
                return Strings.zStack
            }
        }
        return Strings.group
    }

    /// Translates basic Auto Layout constraints into SwiftUI modifiers.
    static func modifierLines(for name: String, constraints: [LayoutConstraint], indent: Int) -> [String] {
        let relevant = constraints.filter { $0.firstItem == name && $0.relation == .equal }
        var width: Double?
        var height: Double?
        var paddingTop: Double?
        var paddingBottom: Double?
        var paddingLeading: Double?
        var paddingTrailing: Double?
        let containerNames: Set<String> = [Strings.containerView, Strings.containerContentView, Strings.containerSelfView]
        var centerX = false
        var centerY = false

        for constraint in relevant {
            switch constraint.firstAttribute {
            case .width:
                width = constraint.constant ?? width
            case .height:
                height = constraint.constant ?? height
            case .top:
                paddingTop = constraint.constant ?? paddingTop
            case .bottom:
                paddingBottom = constraint.constant ?? paddingBottom
            case .leading, .left:
                paddingLeading = constraint.constant ?? paddingLeading
            case .trailing, .right:
                paddingTrailing = constraint.constant ?? paddingTrailing
            case .centerX:
                if let secondItem = constraint.secondItem, containerNames.contains(secondItem) {
                    centerX = true
                }
            case .centerY:
                if let secondItem = constraint.secondItem, containerNames.contains(secondItem) {
                    centerY = true
                }
            default:
                break
            }
        }

        let indentString = indentString(indent)
        var lines: [String] = []

        if width != nil || height != nil {
            var args: [String] = []
            if let width {
                args.append(Strings.frameWidthPrefix + formatNumber(width))
            }
            if let height {
                args.append(Strings.frameHeightPrefix + formatNumber(height))
            }
            lines.append(indentString + Strings.framePrefix + args.joined(separator: Strings.commaSpace) + Strings.closeParen)
        }

        if centerX && centerY {
            lines.append(indentString + Strings.frameMaxBothCentered)
        } else if centerX {
            lines.append(indentString + Strings.frameMaxWidthCentered)
        } else if centerY {
            lines.append(indentString + Strings.frameMaxHeightCentered)
        }

        if let paddingTop {
            lines.append(indentString + Strings.paddingTopPrefix + formatNumber(paddingTop) + Strings.closeParen)
        }
        if let paddingBottom {
            lines.append(indentString + Strings.paddingBottomPrefix + formatNumber(paddingBottom) + Strings.closeParen)
        }
        if let paddingLeading {
            lines.append(indentString + Strings.paddingLeadingPrefix + formatNumber(paddingLeading) + Strings.closeParen)
        }
        if let paddingTrailing {
            lines.append(indentString + Strings.paddingTrailingPrefix + formatNumber(paddingTrailing) + Strings.closeParen)
        }

        return lines
    }

    /// Flattens the hierarchy to simplify lookups for state and metadata.
    private static func collectNodes(from roots: [UIElementNode]) -> [UIElementNode] {
        var result: [UIElementNode] = []
        for node in roots {
            result.append(node)
            result.append(contentsOf: collectNodes(from: node.children))
        }
        return result
    }

    /// Sanitizes UIKit variable names into valid Swift identifiers.
    static func sanitizedIdentifier(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let result = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : Strings.underscoreCharacter }
        var string = String(result)
        if string.isEmpty {
            string = Strings.defaultIdentifier
        }
        if let first = string.unicodeScalars.first, CharacterSet.decimalDigits.contains(first) {
            string = Strings.underscorePrefix + string
        }
        return string
    }

    /// Formats numeric values to reduce noise in generated code.
    static func formatNumber(_ value: Double) -> String {
        let rounded = Double(Int(value))
        if abs(rounded - value) < 0.0001 {
            return String(Int(value))
        }
        return String(format: Strings.floatFormat, value)
    }

    /// Evaluates constraint orientation for stack inference.
    private static func isVertical(_ attribute: ConstraintAttribute) -> Bool {
        switch attribute {
        case .top, .bottom, .centerY:
            return true
        default:
            return false
        }
    }

    /// Evaluates constraint orientation for stack inference.
    private static func isHorizontal(_ attribute: ConstraintAttribute) -> Bool {
        switch attribute {
        case .leading, .trailing, .left, .right, .centerX:
            return true
        default:
            return false
        }
    }

    /// Generates indentation for pretty-printed output.
    static func indentString(_ level: Int) -> String {
        String(repeating: Strings.indentUnit, count: level)
    }

    private enum Strings {
        static let empty = ""
        static let newline = "\n"
        static let importSwiftUI = "import SwiftUI"
        static let structPrefix = "struct "
        static let viewTypeSuffix = "View: View {"
        static let previewSuffix = "View_Previews: PreviewProvider {"
        static let previewStaticLine = "    static var previews: some View {"
        static let bodyLine = "    var body: some View {"
        static let viewInit = "View()"
        static let closingBrace = "}"
        static let openBrace = " {"
        static let openParen = "("
        static let closeParen = ")"
        static let commaSpace = ", "
        static let indentUnit = "    "
        static let doubleIndent = "        "
        static let groupOpen = "Group {"
        static let listOpen = "List {"
        static let textRow = "Text(\"Row\")"
        static let emptyView = "EmptyView()"
        static let vStack = "VStack"
        static let hStack = "HStack"
        static let zStack = "ZStack"
        static let group = "Group"

        static let stateVarPrefix = "@State private var "
        static let letPrefix = "let "
        static let stateSuffixText = "Text"
        static let stateSuffixIsOn = "IsOn"
        static let stateSuffixValue = "Value"
        static let stateSuffixSelection = "Selection"
        static let stateSuffixProgress = "Progress"
        static let stateStringInitializer = ": String = \"\""
        static let stateBoolInitializer = ": Bool = false"
        static let stateDoubleInitializer = ": Double = 0"
        static let stateIntInitializer = ": Int = 0"

        static let alignmentPrefix = "alignment: ."
        static let spacingPrefix = "spacing: "

        static let axisKey = "axis"
        static let spacingKey = "spacing"
        static let axisVertical = "vertical"

        static let alignmentLeading = "leading"
        static let alignmentTrailing = "trailing"
        static let alignmentCenter = "center"
        static let alignmentTop = "top"
        static let alignmentBottom = "bottom"

        static let containerView = "view"
        static let containerContentView = "contentView"
        static let containerSelfView = "self.view"

        static let framePrefix = ".frame("
        static let frameWidthPrefix = "width: "
        static let frameHeightPrefix = "height: "
        static let frameMaxBothCentered = ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)"
        static let frameMaxWidthCentered = ".frame(maxWidth: .infinity, alignment: .center)"
        static let frameMaxHeightCentered = ".frame(maxHeight: .infinity, alignment: .center)"

        static let paddingTopPrefix = ".padding(.top, "
        static let paddingBottomPrefix = ".padding(.bottom, "
        static let paddingLeadingPrefix = ".padding(.leading, "
        static let paddingTrailingPrefix = ".padding(.trailing, "

        static let underscorePrefix = "_"
        static let defaultIdentifier = "value"
        static let underscoreCharacter: Character = "_"

        static let floatFormat = "%.2f"
    }
}
