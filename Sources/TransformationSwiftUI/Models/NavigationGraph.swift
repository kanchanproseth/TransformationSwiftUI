// SPDX-License-Identifier: MIT
//
// NavigationGraph.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Models for the navigation flow graph extracted from storyboard files.
//

import Foundation

// MARK: - SegueKind

/// The SwiftUI navigation pattern that maps to a UIKit segue kind.
public enum SegueKind: String {
    /// Push onto a NavigationStack — from `show` or `push` segues.
    case push
    /// Present as a sheet — from `presentation` or `modal` segues.
    case sheet
    /// Present full-screen — from `presentation` segues with `fullScreen` style.
    case fullScreenCover
    /// A tab in a TabView — from `relationship` segues on a UITabBarController.
    case tab
    /// An embedded child view controller — from `embed` segues.
    case embed
    /// An unwind segue (dismissal / pop-back).
    case unwind
    /// A custom UIStoryboardSegue subclass.
    case custom
    /// Programmatic `present(_:animated:)` call detected in Swift source.
    case programmaticPresent
    /// Programmatic `pushViewController(_:animated:)` call detected in Swift source.
    case programmaticPush
    /// Programmatic `dismiss(animated:)` call — generates `.dismiss` environment action.
    case programmaticDismiss
    /// Triggered by `tableView(_:didSelectRowAt:)` — List row tap navigation.
    case tableViewDidSelect
    /// Triggered by `collectionView(_:didSelectItemAt:)` — LazyGrid item tap navigation.
    case collectionViewDidSelect
}

// MARK: - SegueEdge

/// A directed edge in the navigation graph connecting two view controllers.
public struct SegueEdge {
    /// The user-assigned segue identifier (used in `performSegue(withIdentifier:)`), if any.
    public let identifier: String?
    /// The resolved name of the source view controller.
    public let sourceVC: String
    /// The resolved name of the destination view controller.
    public let destinationVC: String
    /// How the transition is performed.
    public let kind: SegueKind
    /// Tab title for `.tab` edges, sourced from `<tabBarItem title="...">`.
    public let tabTitle: String?
    /// Tab SF Symbol image name for `.tab` edges, sourced from `<tabBarItem image="...">`.
    public let tabImage: String?
    /// Zero-based tab index for `.tab` edges (order of relationship segues in the XML).
    public let tabIndex: Int?

    public init(
        identifier: String?,
        sourceVC: String,
        destinationVC: String,
        kind: SegueKind,
        tabTitle: String? = nil,
        tabImage: String? = nil,
        tabIndex: Int? = nil
    ) {
        self.identifier = identifier
        self.sourceVC = sourceVC
        self.destinationVC = destinationVC
        self.kind = kind
        self.tabTitle = tabTitle
        self.tabImage = tabImage
        self.tabIndex = tabIndex
    }
}

// MARK: - ContainerController

/// A UIKit container controller that wraps one or more child view controllers.
public enum ContainerController {
    /// A UINavigationController — wraps a single root VC and enables push navigation.
    case navigationStack(rootVC: String)
    /// A UITabBarController — hosts multiple tabs, each identified by a `.tab` SegueEdge.
    case tabBar(tabs: [SegueEdge])
}

// MARK: - NavigationGraph

/// The complete navigation flow extracted from one or more storyboard files.
public struct NavigationGraph {
    /// The resolved name of the storyboard's initial view controller (the app entry point).
    public let initialViewControllerName: String?
    /// All action segue edges (push, sheet, fullScreenCover, embed, unwind, custom).
    public let edges: [SegueEdge]
    /// All container controllers (navigation stacks and tab bars).
    public let containers: [ContainerController]

    public init(
        initialViewControllerName: String?,
        edges: [SegueEdge],
        containers: [ContainerController]
    ) {
        self.initialViewControllerName = initialViewControllerName
        self.edges = edges
        self.containers = containers
    }

    /// Returns all action edges (non-tab) originating from the given view controller name.
    public func outgoingEdges(from vcName: String) -> [SegueEdge] {
        edges.filter { $0.sourceVC == vcName && $0.kind != .tab }
    }

    /// Returns true if the given VC is the direct root of any NavigationStack container.
    public func isNavigationRoot(_ vcName: String) -> Bool {
        containers.contains {
            if case .navigationStack(let root) = $0 { return root == vcName }
            return false
        }
    }

    /// Returns the tab bar container that contains the given VC (directly or via a nav stack).
    public func tabBar(containing vcName: String) -> ContainerController? {
        containers.first {
            if case .tabBar(let tabs) = $0 {
                return tabs.contains { $0.destinationVC == vcName }
            }
            return false
        }
    }

    /// Merges another graph into this one, deduplicating edges by source+destination+kind.
    public func merging(_ other: NavigationGraph) -> NavigationGraph {
        var seenEdges = Set(edges.map { "\($0.sourceVC)-\($0.destinationVC)-\($0.kind.rawValue)" })
        var mergedEdges = edges
        for edge in other.edges {
            let key = "\(edge.sourceVC)-\(edge.destinationVC)-\(edge.kind.rawValue)"
            if seenEdges.insert(key).inserted {
                mergedEdges.append(edge)
            }
        }
        return NavigationGraph(
            initialViewControllerName: initialViewControllerName ?? other.initialViewControllerName,
            edges: mergedEdges,
            containers: containers + other.containers
        )
    }

    /// Adds programmatic navigation edges inferred from `BusinessLogicVisitor.navigationCalls`.
    /// - Parameters:
    ///   - calls: The navigation calls discovered in Swift source.
    ///   - sourceVC: The view controller that owns those calls.
    /// - Returns: A new graph with the extra edges appended (deduplication applied).
    public func addingProgrammaticEdges(
        from calls: [NavigationCall],
        sourceVC: String
    ) -> NavigationGraph {
        var newEdges: [SegueEdge] = []
        var seen = Set(edges.map { "\($0.sourceVC)-\($0.destinationVC)-\($0.kind.rawValue)" })

        for call in calls {
            let kind: SegueKind
            switch call.kind {
            case .presentViewController:   kind = .programmaticPresent
            case .pushViewController:      kind = .programmaticPush
            case .dismissViewController:   kind = .programmaticDismiss
            case .performSegue:            kind = .push // treated as push unless we know more
            case .tableViewDidSelect:      kind = .tableViewDidSelect
            case .collectionViewDidSelect: kind = .collectionViewDidSelect
            default: continue
            }

            let destVC = call.destinationVC ?? "Unknown"
            let key = "\(sourceVC)-\(destVC)-\(kind.rawValue)"
            if seen.insert(key).inserted {
                newEdges.append(SegueEdge(
                    identifier: call.segueIdentifier,
                    sourceVC: sourceVC,
                    destinationVC: destVC,
                    kind: kind
                ))
            }
        }

        return NavigationGraph(
            initialViewControllerName: initialViewControllerName,
            edges: edges + newEdges,
            containers: containers
        )
    }
}
