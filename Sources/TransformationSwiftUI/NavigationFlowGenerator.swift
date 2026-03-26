// SPDX-License-Identifier: MIT
//
// NavigationFlowGenerator.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Generates AppFlowView.swift wiring all converted screens together.
//

import Foundation

/// Generates the top-level SwiftUI navigation flow file (`AppFlowView.swift`) from a
/// `NavigationGraph`, replicating the UIKit app structure in SwiftUI idioms:
///
/// - `UINavigationController`  →  `NavigationStack { RootView() }`
/// - `UITabBarController`       →  `TabView { … .tabItem { Label(…) } }`
/// - show/push segues           →  `NavigationLink` in each source view
/// - modal/presentation segues  →  `.sheet` / `.fullScreenCover` in each source view
public struct NavigationFlowGenerator {

    // MARK: - AppFlowView.swift

    /// Generates the full content of `AppFlowView.swift`.
    ///
    /// - Parameters:
    ///   - graph: The navigation graph extracted from storyboards.
    ///   - allVCNames: The complete set of view controller names that were converted,
    ///     used to skip references to VCs that don't have generated files.
    /// - Returns: Swift source code string for `AppFlowView.swift`.
    public static func generateAppFlowView(
        graph: NavigationGraph,
        allVCNames: Set<String>
    ) -> String {
        var lines: [String] = []
        lines.append("import SwiftUI")
        lines.append("")
        lines.append("/// Auto-generated navigation flow.")
        lines.append("/// Mirrors the UIKit storyboard navigation structure.")
        lines.append("struct AppFlowView: View {")
        lines.append("    var body: some View {")

        let bodyLines = generateRootBody(graph: graph, allVCNames: allVCNames, indent: 2)
        lines.append(contentsOf: bodyLines)

        lines.append("    }")
        lines.append("}")
        lines.append("")
        lines.append("#Preview {")
        lines.append("    AppFlowView()")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    // MARK: - Per-View Navigation Injection

    /// Generates the navigation-aware additions for a single view controller's SwiftUI file.
    ///
    /// Returns additional `@State` declarations and view modifiers to append to the
    /// generated view body. Call this after generating the base view content.
    ///
    /// - Parameters:
    ///   - vcName: The view controller's resolved name.
    ///   - graph: The full navigation graph.
    ///   - allVCNames: Only inject links for VCs that were actually converted.
    /// - Returns: Tuple of (stateDeclarations, viewModifiers) to inject into the view.
    public static func navigationInjection(
        for vcName: String,
        graph: NavigationGraph,
        allVCNames: Set<String>
    ) -> (stateLines: [String], modifierLines: [String], linkLines: [String]) {
        let outgoing = graph.outgoingEdges(from: vcName)
            .filter { allVCNames.contains($0.destinationVC) }

        var stateLines: [String] = []
        var modifierLines: [String] = []
        var linkLines: [String] = []

        for edge in outgoing {
            let destView = edge.destinationVC + "View"
            let bindingName = "isShowing\(edge.destinationVC)"

            switch edge.kind {
            case .push, .programmaticPush:
                // NavigationLink rendered inline in the body
                let label = edge.identifier ?? "Go to \(edge.destinationVC)"
                linkLines.append("NavigationLink(\"\(label)\") {")
                linkLines.append("    \(destView)()")
                linkLines.append("}")

            case .sheet, .programmaticPresent:
                stateLines.append("@State private var \(bindingName) = false")
                modifierLines.append(".sheet(isPresented: $\(bindingName)) {")
                modifierLines.append("    \(destView)()")
                modifierLines.append("}")

            case .fullScreenCover:
                stateLines.append("@State private var \(bindingName) = false")
                modifierLines.append(".fullScreenCover(isPresented: $\(bindingName)) {")
                modifierLines.append("    \(destView)()")
                modifierLines.append("}")

            case .embed:
                linkLines.append("\(destView)()")

            case .programmaticDismiss:
                // dismiss is handled via @Environment(\.dismiss)
                stateLines.append("@Environment(\\.dismiss) private var dismiss")

            case .tableViewDidSelect:
                // Row tap navigates: NavigationLink driven by item selection
                let label = edge.identifier ?? "Go to \(edge.destinationVC)"
                linkLines.append("// tableView didSelect → NavigationLink")
                linkLines.append("NavigationLink(\"\(label)\") {")
                linkLines.append("    \(destView)()")
                linkLines.append("}")

            case .collectionViewDidSelect:
                // Item tap navigates via sheet or NavigationLink
                stateLines.append("@State private var \(bindingName) = false")
                modifierLines.append("// collectionView didSelect → sheet")
                modifierLines.append(".sheet(isPresented: $\(bindingName)) {")
                modifierLines.append("    \(destView)()")
                modifierLines.append("}")

            default:
                break
            }
        }

        return (stateLines, modifierLines, linkLines)
    }

    // MARK: - Private Generation Helpers

    private static func generateRootBody(
        graph: NavigationGraph,
        allVCNames: Set<String>,
        indent: Int
    ) -> [String] {
        let pad = String(repeating: "    ", count: indent)

        // Case 1: Tab bar is the root
        if let initialName = graph.initialViewControllerName {
            for container in graph.containers {
                if case .tabBar(let tabs) = container {
                    // Check if the initial VC is the tab bar itself or points to it
                    let tabDestinations = tabs.map { $0.destinationVC }
                    let isRootTabBar = tabDestinations.contains(initialName) ||
                        tabs.first.map { _ in true } == true

                    // Find if initial VC is a nav controller wrapping one of the tabs
                    let tabBarIsInitial = graph.containers.contains {
                        if case .tabBar(let t) = $0 {
                            return t.contains { $0.destinationVC == initialName ||
                                graph.isNavigationRoot($0.destinationVC) }
                        }
                        return false
                    }

                    if isRootTabBar || tabBarIsInitial {
                        return generateTabView(tabs: tabs, graph: graph, allVCNames: allVCNames, indent: indent)
                    }
                }
            }
        }

        // Case 2: Navigation stack is the root
        if let initialName = graph.initialViewControllerName {
            // Initial VC is itself a nav root
            if graph.isNavigationRoot(initialName) {
                return generateNavigationStack(rootVC: initialName, allVCNames: allVCNames, indent: indent)
            }
            // Initial VC is the root of a nav container
            for container in graph.containers {
                if case .navigationStack(let root) = container, allVCNames.contains(root) {
                    return generateNavigationStack(rootVC: root, allVCNames: allVCNames, indent: indent)
                }
            }
            // Initial VC is a plain view controller
            if allVCNames.contains(initialName) {
                return ["\(pad)\(initialName)View()"]
            }
        }

        // Case 3: No initial VC — use the first nav stack or first VC we know about
        for container in graph.containers {
            if case .navigationStack(let root) = container, allVCNames.contains(root) {
                return generateNavigationStack(rootVC: root, allVCNames: allVCNames, indent: indent)
            }
        }
        for container in graph.containers {
            if case .tabBar(let tabs) = container, !tabs.isEmpty {
                return generateTabView(tabs: tabs, graph: graph, allVCNames: allVCNames, indent: indent)
            }
        }

        return ["\(pad)EmptyView() // No entry point detected"]
    }

    private static func generateNavigationStack(
        rootVC: String,
        allVCNames: Set<String>,
        indent: Int
    ) -> [String] {
        let pad = String(repeating: "    ", count: indent)
        guard allVCNames.contains(rootVC) else {
            return ["\(pad)EmptyView() // \(rootVC) was not converted"]
        }
        return [
            "\(pad)NavigationStack {",
            "\(pad)    \(rootVC)View()",
            "\(pad)}",
        ]
    }

    private static func generateTabView(
        tabs: [SegueEdge],
        graph: NavigationGraph,
        allVCNames: Set<String>,
        indent: Int
    ) -> [String] {
        let pad = String(repeating: "    ", count: indent)
        var lines: [String] = []
        lines.append("\(pad)TabView {")

        for tab in tabs.sorted(by: { ($0.tabIndex ?? 0) < ($1.tabIndex ?? 0) }) {
            let destVC = tab.destinationVC
            guard allVCNames.contains(destVC) else { continue }

            let title = tab.tabTitle ?? destVC
            let image = tab.tabImage ?? "circle"

            // Check if this tab's destination is itself a nav controller root
            let isNavRoot = graph.isNavigationRoot(destVC)
            if isNavRoot {
                lines.append("\(pad)    NavigationStack {")
                lines.append("\(pad)        \(destVC)View()")
                lines.append("\(pad)    }")
            } else {
                lines.append("\(pad)    \(destVC)View()")
            }
            lines.append("\(pad)    .tabItem {")
            lines.append("\(pad)        Label(\"\(title)\", systemImage: \"\(image)\")")
            lines.append("\(pad)    }")
        }

        lines.append("\(pad)}")
        return lines
    }
}
