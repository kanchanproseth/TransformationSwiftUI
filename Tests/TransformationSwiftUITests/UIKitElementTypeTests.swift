// SPDX-License-Identifier: MIT
//
// UIKitElementTypeTests.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Tests for UIKitElementType parsing and helpers.
//

import Foundation
import Testing
import SwiftParser
@testable import TransformationSwiftUI

struct UIKitElementTypeTests {
    @Test
    func parsesOptionalTypeNames() {
        #expect(UIKitElementType.from(typeName: "UILabel?") == .label)
        #expect(UIKitElementType.from(typeName: "UISwitch!") == .toggleSwitch)
    }

    @Test
    func parsesGenericTypeNames() {
        #expect(UIKitElementType.from(typeName: "UIStackView<UIView>") == .stackView)
    }

    @Test
    func returnsNilForUnknownTypes() {
        #expect(UIKitElementType.from(typeName: "CustomView") == nil)
    }

    @Test
    func identifiesViewControllerInheritance() {
        #expect(UIKitElementType.isViewController(typeName: "UIViewController") == true)
        #expect(UIKitElementType.isViewController(typeName: "UITableViewController") == false)
    }
}

struct SwiftUIRendererTests {
    @Test
    func labelRendererProducesText() {
        let node = UIElementNode(name: "titleLabel", type: .label, children: [])
        let lines = LabelRenderer().render(node: node, constraints: [], patterns: [], indent: 1)
        #expect(lines.first == "    Text(\"titleLabel\")")
    }

    @Test
    func buttonRendererProducesButton() {
        let node = UIElementNode(name: "actionButton", type: .button, children: [])
        let lines = ButtonRenderer().render(node: node, constraints: [], patterns: [], indent: 0)
        #expect(lines.first == "Button(\"actionButton\") { }")
    }

    @Test
    func imageRendererAddsResizable() {
        let node = UIElementNode(name: "heroImage", type: .imageView, children: [])
        let lines = ImageViewRenderer().render(node: node, constraints: [], patterns: [], indent: 1)
        #expect(lines.count == 2)
        #expect(lines[1].contains(".resizable()") == true)
    }

    @Test
    func stackViewRendererDefaultsToVStack() {
        let node = UIElementNode(
            name: "contentStack",
            type: .stackView,
            children: [
                UIElementNode(name: "firstLabel", type: .label, children: []),
                UIElementNode(name: "secondLabel", type: .label, children: [])
            ]
        )
        let lines = StackViewRenderer().render(node: node, constraints: [], patterns: [], indent: 1)
        #expect(lines.first?.contains("VStack") == true)
    }

    @Test
    func viewRendererUsesZStackWhenPatternDetected() {
        let childA = UIElementNode(name: "badge", type: .label, children: [])
        let childB = UIElementNode(name: "icon", type: .imageView, children: [])
        let node = UIElementNode(name: "container", type: .view, children: [childA, childB])
        let patterns = [LayoutPattern(type: .zStack, elements: ["badge", "icon"])]
        let lines = ViewRenderer().render(node: node, constraints: [], patterns: patterns, indent: 0)
        #expect(lines.first == "ZStack {")
    }

    @Test
    func scrollViewRendererWrapsContent() {
        let node = UIElementNode(name: "scroll", type: .scrollView, children: [])
        let lines = ScrollViewRenderer().render(node: node, constraints: [], patterns: [], indent: 0)
        #expect(lines.first == "ScrollView {")
    }

    @Test
    func textFieldRendererBindsState() {
        let node = UIElementNode(name: "usernameField", type: .textField, children: [])
        let lines = TextFieldRenderer().render(node: node, constraints: [], patterns: [], indent: 0)
        #expect(lines.first?.contains("TextField(\"usernameField\"") == true)
        #expect(lines.first?.contains("$usernameFieldText") == true)
    }

    @Test
    func textViewRendererBindsState() {
        let node = UIElementNode(name: "bioTextView", type: .textView, children: [])
        let lines = TextViewRenderer().render(node: node, constraints: [], patterns: [], indent: 0)
        #expect(lines.first == "TextEditor(text: $bioTextViewText)")
    }

    @Test
    func toggleRendererBindsState() {
        let node = UIElementNode(name: "isEnabled", type: .toggleSwitch, children: [])
        let lines = ToggleRenderer().render(node: node, constraints: [], patterns: [], indent: 0)
        #expect(lines.first == "Toggle(\"isEnabled\", isOn: $isEnabledIsOn)")
    }

    @Test
    func sliderRendererBindsState() {
        let node = UIElementNode(name: "volumeSlider", type: .slider, children: [])
        let lines = SliderRenderer().render(node: node, constraints: [], patterns: [], indent: 0)
        #expect(lines.first == "Slider(value: $volumeSliderValue)")
    }

    @Test
    func progressViewRendererUsesValue() {
        let node = UIElementNode(name: "downloadProgress", type: .progressView, children: [])
        let lines = ProgressViewRenderer().render(node: node, constraints: [], patterns: [], indent: 0)
        #expect(lines.first == "ProgressView(value: downloadProgressProgress)")
    }

    @Test
    func listRendererStartsList() {
        let node = UIElementNode(name: "tableView", type: .tableView, children: [])
        let lines = ListRenderer().render(node: node, constraints: [], patterns: [], indent: 0)
        #expect(lines.first == "List {")
    }

    @Test
    func activityIndicatorRendererUsesProgressView() {
        let node = UIElementNode(name: "spinner", type: .activityIndicatorView, children: [])
        let lines = ActivityIndicatorRenderer().render(node: node, constraints: [], patterns: [], indent: 0)
        #expect(lines.first == "ProgressView()")
    }

    @Test
    func segmentedControlRendererUsesPickerStyle() {
        let node = UIElementNode(name: "modeControl", type: .segmentedControl, children: [])
        let lines = SegmentedControlRenderer().render(node: node, constraints: [], patterns: [], indent: 0)
        #expect(lines.contains { $0.contains("pickerStyle(.segmented)") })
    }

    @Test
    func pageControlRendererUsesPageStyle() {
        let node = UIElementNode(name: "pageControl", type: .pageControl, children: [])
        let lines = PageControlRenderer().render(node: node, constraints: [], patterns: [], indent: 0)
        #expect(lines.contains { $0.contains("tabViewStyle(.page)") })
    }

    @Test
    func visualEffectRendererUsesMaterialFill() {
        let node = UIElementNode(name: "blurView", type: .visualEffectView, children: [])
        let lines = VisualEffectRenderer().render(node: node, constraints: [], patterns: [], indent: 0)
        #expect(lines.first == "Rectangle().fill(.ultraThinMaterial)")
    }
}

struct SwiftUICodeGeneratorTests {
    @Test
    func generateIncludesPreviewAndState() {
        let textField = UIElementNode(name: "usernameField", type: .textField, children: [])
        let toggle = UIElementNode(name: "isEnabled", type: .toggleSwitch, children: [])
        let slider = UIElementNode(name: "volume", type: .slider, children: [])
        let segmented = UIElementNode(name: "mode", type: .segmentedControl, children: [])
        let progress = UIElementNode(name: "download", type: .progressView, children: [])
        let root = UIElementNode(name: "rootView", type: .view, children: [textField, toggle, slider, segmented, progress])

        let model = ViewControllerModel(
            name: "Sample",
            rootElements: [root],
            constraints: []
        )

        let output = SwiftUICodeGenerator.generate(for: model)
        #expect(output.contains("struct SampleView: View"))
        #expect(output.contains("@State private var usernameFieldText"))
        #expect(output.contains("@State private var isEnabledIsOn"))
        #expect(output.contains("@State private var volumeValue"))
        #expect(output.contains("@State private var modeSelection"))
        #expect(output.contains("let downloadProgress"))
        #expect(output.contains("struct SampleView_Previews"))
    }

    @Test
    func modifierLinesApplyFrameAndPadding() {
        let constraints = [
            LayoutConstraint(
                firstItem: "avatar",
                firstAttribute: .width,
                relation: .equal,
                secondItem: nil,
                secondAttribute: nil,
                constant: 48
            ),
            LayoutConstraint(
                firstItem: "avatar",
                firstAttribute: .height,
                relation: .equal,
                secondItem: nil,
                secondAttribute: nil,
                constant: 48
            ),
            LayoutConstraint(
                firstItem: "avatar",
                firstAttribute: .top,
                relation: .equal,
                secondItem: "view",
                secondAttribute: .top,
                constant: 12
            )
        ]

        let lines = SwiftUICodeGenerator.modifierLines(for: "avatar", constraints: constraints, indent: 1)
        #expect(lines.contains("    .frame(width: 48, height: 48)"))
        #expect(lines.contains("    .padding(.top, 12)"))
    }

    @Test
    func containerNameUsesZStackPattern() {
        let children = [
            UIElementNode(name: "badge", type: .label, children: []),
            UIElementNode(name: "icon", type: .imageView, children: [])
        ]
        let patterns = [LayoutPattern(type: .zStack, elements: ["badge", "icon"])]
        #expect(SwiftUICodeGenerator.containerName(for: children, patterns: patterns) == "ZStack")
    }
}

struct LayoutPatternEngineTests {
    @Test
    func inferPatternsDetectsStacks() {
        let constraints = [
            LayoutConstraint(
                firstItem: "title",
                firstAttribute: .top,
                relation: .equal,
                secondItem: "subtitle",
                secondAttribute: .bottom,
                constant: 8
            ),
            LayoutConstraint(
                firstItem: "avatar",
                firstAttribute: .leading,
                relation: .equal,
                secondItem: "title",
                secondAttribute: .trailing,
                constant: 12
            )
        ]

        let patterns = LayoutPatternEngine.inferPatterns(from: constraints)
        #expect(patterns.contains { $0.type == .vStack })
        #expect(patterns.contains { $0.type == .hStack })
    }

    @Test
    func inferPatternsDetectsZStack() {
        let constraints = [
            LayoutConstraint(
                firstItem: "badge",
                firstAttribute: .centerX,
                relation: .equal,
                secondItem: "icon",
                secondAttribute: .centerX,
                constant: 0
            ),
            LayoutConstraint(
                firstItem: "badge",
                firstAttribute: .centerY,
                relation: .equal,
                secondItem: "icon",
                secondAttribute: .centerY,
                constant: 0
            )
        ]

        let patterns = LayoutPatternEngine.inferPatterns(from: constraints)
        #expect(patterns.contains { $0.type == .zStack })
    }

    @Test
    func inferHintsProducesFrameAndPadding() {
        let constraints = [
            LayoutConstraint(
                firstItem: "avatar",
                firstAttribute: .width,
                relation: .equal,
                secondItem: nil,
                secondAttribute: nil,
                constant: 44
            ),
            LayoutConstraint(
                firstItem: "avatar",
                firstAttribute: .leading,
                relation: .equal,
                secondItem: "view",
                secondAttribute: .leading,
                constant: 12
            )
        ]

        let hints = LayoutPatternEngine.inferHints(from: constraints)
        #expect(hints.contains("avatar.frame(width: 44)"))
        #expect(hints.contains("avatar.padding(.leading, 12)"))
    }
}
