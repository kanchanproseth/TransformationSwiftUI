// SPDX-License-Identifier: MIT
//
// ViewControllerModel.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Model for a parsed view controller and its layout data.
//

import Foundation

/// Parsed data for a single UIViewController or storyboard scene.
public struct ViewControllerModel {
    /// The view controller name or storyboard identifier used for output.
    public let name: String

    /// Root elements extracted from the view hierarchy.
    public var rootElements: [UIElementNode] = []

    /// Collected Auto Layout constraints for this controller.
    public var constraints: [LayoutConstraint] = []

    /// UIKit animations detected in this view controller's Swift source.
    public var animations: [AnimationModel] = []

    // MARK: - Navigation metadata (populated from storyboard parsing)

    /// Outgoing segues from this view controller to other screens.
    public var segues: [SegueEdge] = []

    /// True when this view controller is the root of a navigation controller.
    public var isNavigationRoot: Bool = false

    /// The navigation bar title, when defined in Interface Builder.
    public var navigationTitle: String?

    /// The tab bar item configuration when this controller is used in a tab bar.
    public var tabBarItem: TabBarItemInfo?

    // MARK: - Business logic metadata (populated from Swift source analysis)

    /// Visibility mutations (isHidden, alpha, addSubview, removeFromSuperview) across all methods.
    public var visibilityRules: [VisibilityRule] = []

    /// All control action bindings (IBAction, target-action, didSelectRowAt, etc.).
    public var controlActions: [ControlAction] = []

    /// Programmatic navigation calls (present, push, dismiss, performSegue).
    public var navigationCalls: [NavigationCall] = []

    public init(
        name: String,
        rootElements: [UIElementNode] = [],
        constraints: [LayoutConstraint] = []
    ) {
        self.name = name
        self.rootElements = rootElements
        self.constraints = constraints
    }
}

/// Tab bar item metadata for a view controller that appears as a tab.
public struct TabBarItemInfo {
    /// The tab title shown under the icon.
    public let title: String

    /// The image name from Interface Builder, if provided.
    public let image: String?

    public init(title: String, image: String?) {
        self.title = title
        self.image = image
    }
}
