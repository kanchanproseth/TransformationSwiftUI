// SPDX-License-Identifier: MIT
//
// StoryboardParser.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Parses storyboard and XIB files into ViewControllerModel instances.
//

import Foundation

/// Parses `.storyboard` and `.xib` files (XML-based) into `ViewControllerModel` instances,
/// producing the same model used by the Swift source parsing pipeline.
public struct StoryboardParser {

    // MARK: - Public Entry Point

    /// Parses a single storyboard or XIB file and returns one model per view controller (or root view).
    ///
    /// - Parameters:
    ///   - url: The `.storyboard` or `.xib` file URL.
    ///   - componentRegistry: Optional registry for resolving custom UIView subclasses.
    /// - Returns: Array of `ViewControllerModel` instances extracted from the file.
    public static func parseFile(
        _ url: URL,
        componentRegistry: CustomComponentRegistry? = nil
    ) -> [ViewControllerModel] {
        guard let document = try? XMLDocument(contentsOf: url, options: []) else {
            return []
        }

        guard let root = document.rootElement() else { return [] }

        // Determine file type
        let isStoryboard = !root.elements(forName: Strings.xmlScenes).isEmpty
        let isXIB = !root.elements(forName: Strings.xmlObjects).isEmpty

        // Pre-pass: build outlet map (element ID → Swift property name)
        let outletMap = buildOutletMap(root: root)

        // Pre-pass: build id → element map for constraint resolution
        var idToElement: [String: XMLElement] = [:]
        collectAllElements(root: root, into: &idToElement)

        // Build human-readable name map for all IB element IDs
        let idToName = buildNameMap(from: idToElement, outletMap: outletMap)

        if isStoryboard {
            return parseStoryboard(root: root, idToName: idToName, outletMap: outletMap, componentRegistry: componentRegistry)
        } else if isXIB {
            return parseXIB(root: root, idToName: idToName, outletMap: outletMap, componentRegistry: componentRegistry)
        }

        return []
    }

    // MARK: - Storyboard Parsing

    private static func parseStoryboard(
        root: XMLElement,
        idToName: [String: String],
        outletMap: [String: String],
        componentRegistry: CustomComponentRegistry?
    ) -> [ViewControllerModel] {
        var models: [ViewControllerModel] = []

        for scenes in root.elements(forName: Strings.xmlScenes) {
            for scene in scenes.elements(forName: Strings.xmlScene) {
                for objects in scene.elements(forName: Strings.xmlObjects) {
                    // Parse view controllers and standalone views
                    for child in objects.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                        if let model = parseViewController(
                            element: child,
                            idToName: idToName,
                            outletMap: outletMap,
                            componentRegistry: componentRegistry
                        ) {
                            models.append(model)
                        }
                    }
                }
            }
        }

        return models
    }

    private static func parseViewController(
        element: XMLElement,
        idToName: [String: String],
        outletMap: [String: String],
        componentRegistry: CustomComponentRegistry?
    ) -> ViewControllerModel? {
        let xmlName = element.name ?? Strings.empty

        // Accept any view controller variant plus tableViewController, collectionViewController etc.
        let isVC = xmlName.contains(Strings.viewControllerSuffix) || xmlName == Strings.viewController
        guard isVC else { return nil }

        // Resolve view controller name
        let vcName = resolveViewControllerName(element: element, idToName: idToName)

        // Find the root <view> element
        guard let viewElement = firstView(in: element) else {
            return ViewControllerModel(name: vcName, rootElements: [], constraints: [])
        }

        // Parse root view's subviews
        var rootElements: [UIElementNode] = []
        var allConstraints: [LayoutConstraint] = []

        let viewName = idToName[element.attribute(forName: Strings.attrId)?.stringValue ?? Strings.empty]
            ?? vcName.lowercased() + Strings.viewSuffix
        parseSubviews(
            of: viewElement,
            parentName: viewName,
            idToName: idToName,
            outletMap: outletMap,
            componentRegistry: componentRegistry,
            elements: &rootElements,
            constraints: &allConstraints
        )

        // Also parse constraints on the root view itself
        let rootConstraints = parseConstraints(in: viewElement, idToName: idToName, owningViewName: viewName)
        allConstraints.append(contentsOf: rootConstraints)

        return ViewControllerModel(name: vcName, rootElements: rootElements, constraints: allConstraints)
    }

    // MARK: - XIB Parsing

    private static func parseXIB(
        root: XMLElement,
        idToName: [String: String],
        outletMap: [String: String],
        componentRegistry: CustomComponentRegistry?
    ) -> [ViewControllerModel] {
        var models: [ViewControllerModel] = []

        for objects in root.elements(forName: Strings.xmlObjects) {
            for child in objects.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                let xmlName = child.name ?? Strings.empty

                // Root-level view in a XIB
                if xmlName == Strings.xmlView || IBElementMapper.elementType(forXMLName: xmlName) != nil {
                    let elementID = child.attribute(forName: Strings.attrId)?.stringValue ?? Strings.empty
                    let name = idToName[elementID] ?? IBElementMapper.resolveName(for: child, xmlName: xmlName, outletMap: outletMap)

                    var elements: [UIElementNode] = []
                    var constraints: [LayoutConstraint] = []

                    parseSubviews(
                        of: child,
                        parentName: name,
                        idToName: idToName,
                        outletMap: outletMap,
                        componentRegistry: componentRegistry,
                        elements: &elements,
                        constraints: &constraints
                    )

                    let rootConstraints = parseConstraints(in: child, idToName: idToName, owningViewName: name)
                    constraints.append(contentsOf: rootConstraints)

                    let model = ViewControllerModel(name: name, rootElements: elements, constraints: constraints)
                    models.append(model)
                }
            }
        }

        return models
    }

    // MARK: - Subview Recursion

    /// Recursively parses `<subviews>` blocks and their children into `UIElementNode` trees.
    private static func parseSubviews(
        of element: XMLElement,
        parentName: String,
        idToName: [String: String],
        outletMap: [String: String],
        componentRegistry: CustomComponentRegistry?,
        elements: inout [UIElementNode],
        constraints: inout [LayoutConstraint]
    ) {
        for subviewsEl in element.elements(forName: Strings.xmlSubviews) {
            for child in subviewsEl.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                let xmlName = child.name ?? Strings.empty
                let elementID = child.attribute(forName: Strings.attrId)?.stringValue ?? Strings.empty
                let resolvedName = idToName[elementID] ?? IBElementMapper.resolveName(for: child, xmlName: xmlName, outletMap: outletMap)

                var node = buildNode(
                    for: child,
                    xmlName: xmlName,
                    resolvedName: resolvedName,
                    componentRegistry: componentRegistry
                )

                // Recurse into nested subviews
                parseSubviews(
                    of: child,
                    parentName: resolvedName,
                    idToName: idToName,
                    outletMap: outletMap,
                    componentRegistry: componentRegistry,
                    elements: &node.children,
                    constraints: &constraints
                )

                elements.append(node)

                // Track constraints for this view
                let childConstraints = parseConstraints(in: child, idToName: idToName, owningViewName: resolvedName)
                constraints.append(contentsOf: childConstraints)
            }
        }
    }

    private static func buildNode(
        for element: XMLElement,
        xmlName: String,
        resolvedName: String,
        componentRegistry: CustomComponentRegistry?
    ) -> UIElementNode {
        let elementType = IBElementMapper.elementType(forXMLName: xmlName)
        var node = UIElementNode(name: resolvedName, type: elementType)

        // Attach properties inferred from XML attributes
        let properties = IBElementMapper.extractProperties(from: element)
        node.properties = properties

        // Resolve custom component type if present
        if let registry = componentRegistry,
           let customClass = element.attribute(forName: Strings.attrCustomClass)?.stringValue,
           !customClass.isEmpty {
            let resolved = registry.resolveType(customClass)
            if case .custom(let component) = resolved {
                node.customComponentName = component.name
                node.type = component.resolvedBaseType
            }
        }

        return node
    }

    // MARK: - Constraint Parsing

    private static func parseConstraints(
        in element: XMLElement,
        idToName: [String: String],
        owningViewName: String?
    ) -> [LayoutConstraint] {
        var constraints: [LayoutConstraint] = []
        for constraintsElement in element.elements(forName: Strings.xmlConstraints) {
            let constraintElements = constraintsElement.elements(forName: Strings.xmlConstraint)
            let mapped = IBConstraintMapper.mapConstraints(from: constraintElements, idToName: idToName, owningViewName: owningViewName)
            constraints.append(contentsOf: mapped)
        }
        return constraints
    }

    // MARK: - Helpers

    private static func buildOutletMap(root: XMLElement) -> [String: String] {
        var outletMap: [String: String] = [:]
        for connections in root.elements(forName: Strings.xmlConnections) {
            for outlet in connections.elements(forName: Strings.xmlOutlet) {
                let property = outlet.attribute(forName: Strings.attrProperty)?.stringValue
                let destination = outlet.attribute(forName: Strings.attrDestination)?.stringValue
                if let property, let destination, !property.isEmpty {
                    outletMap[destination] = property
                }
            }
        }
        return outletMap
    }

    private static func buildNameMap(
        from idToElement: [String: XMLElement],
        outletMap: [String: String]
    ) -> [String: String] {
        var idToName: [String: String] = [:]
        for (id, element) in idToElement {
            let xmlName = element.name ?? Strings.empty
            let resolved = IBElementMapper.resolveName(for: element, xmlName: xmlName, outletMap: outletMap)
            idToName[id] = resolved
        }
        return idToName
    }

    private static func collectAllElements(root: XMLElement, into map: inout [String: XMLElement]) {
        if let id = root.attribute(forName: Strings.attrId)?.stringValue {
            map[id] = root
        }
        for child in root.children?.compactMap({ $0 as? XMLElement }) ?? [] {
            collectAllElements(root: child, into: &map)
        }
    }

    private static func resolveViewControllerName(element: XMLElement, idToName: [String: String]) -> String {
        if let customClass = element.attribute(forName: Strings.attrCustomClass)?.stringValue, !customClass.isEmpty {
            return customClass
        }
        if let storyboardIdentifier = element.attribute(forName: Strings.attrStoryboardIdentifier)?.stringValue, !storyboardIdentifier.isEmpty {
            return storyboardIdentifier
        }
        if let id = element.attribute(forName: Strings.attrId)?.stringValue, let name = idToName[id] {
            return name
        }
        return Strings.defaultViewControllerName
    }

    private static func firstView(in element: XMLElement) -> XMLElement? {
        for child in element.children?.compactMap({ $0 as? XMLElement }) ?? [] {
            if child.name == Strings.xmlView {
                return child
            }
        }
        return nil
    }

    // MARK: - Navigation Graph Extraction

    /// Parses all navigation connections from a storyboard file into a `NavigationGraph`.
    ///
    /// This is a separate pass from `parseFile` — call both when you need both view
    /// content and navigation flow from the same storyboard.
    public static func parseNavigationGraph(_ url: URL) -> NavigationGraph? {
        guard let document = try? XMLDocument(contentsOf: url, options: []),
              let root = document.rootElement() else { return nil }

        // Only storyboards carry navigation — XIBs have no segues
        guard !root.elements(forName: Strings.xmlScenes).isEmpty else { return nil }

        // Pre-pass: build outlet map and id→element map (same as parseFile)
        let outletMap = buildOutletMap(root: root)
        var idToElement: [String: XMLElement] = [:]
        collectAllElements(root: root, into: &idToElement)
        let idToName = buildNameMap(from: idToElement, outletMap: outletMap)

        // Resolve the initial view controller name
        let initialID = root.attribute(forName: Strings.attrInitialViewController)?.stringValue
        let initialName = initialID.flatMap { idToName[$0] }

        var edges: [SegueEdge] = []
        var containers: [ContainerController] = []

        for scenes in root.elements(forName: Strings.xmlScenes) {
            for scene in scenes.elements(forName: Strings.xmlScene) {
                for objects in scene.elements(forName: Strings.xmlObjects) {
                    for child in objects.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                        let xmlName = child.name ?? Strings.empty
                        let childID = child.attribute(forName: Strings.attrId)?.stringValue ?? Strings.empty
                        let childName = idToName[childID] ?? resolveViewControllerName(element: child, idToName: idToName)

                        if xmlName == Strings.xmlNavigationController {
                            // Extract rootViewController relationship
                            let rootVC = navigationControllerRoot(element: child, idToName: idToName)
                            if let rootVC {
                                containers.append(.navigationStack(rootVC: rootVC))
                            }

                        } else if xmlName == Strings.xmlTabBarController {
                            // Extract all tab viewControllers in order
                            let tabs = tabBarTabs(element: child, idToName: idToName, idToElement: idToElement)
                            if !tabs.isEmpty {
                                containers.append(.tabBar(tabs: tabs))
                            }

                        } else if xmlName.contains(Strings.viewControllerSuffix) || xmlName == Strings.viewController {
                            // Collect action segues from this VC (including inside subviews)
                            let vcEdges = collectSegueEdges(from: child, sourceVC: childName, idToName: idToName)
                            edges.append(contentsOf: vcEdges)
                        }
                    }
                }
            }
        }

        return NavigationGraph(
            initialViewControllerName: initialName,
            edges: edges,
            containers: containers
        )
    }

    /// Enriches a `[ViewControllerModel]` array with navigation metadata from the graph.
    ///
    /// Call this after both `parseFile` and `parseNavigationGraph` to attach segues,
    /// `isNavigationRoot`, `navigationTitle`, and `tabBarItem` to each model.
    public static func enrichModels(
        _ models: inout [ViewControllerModel],
        with graph: NavigationGraph,
        url: URL
    ) {
        guard let document = try? XMLDocument(contentsOf: url, options: []),
              let root = document.rootElement() else { return }

        let outletMap = buildOutletMap(root: root)
        var idToElement: [String: XMLElement] = [:]
        collectAllElements(root: root, into: &idToElement)
        let idToName = buildNameMap(from: idToElement, outletMap: outletMap)

        // Build a name → element lookup for enrichment
        var nameToElement: [String: XMLElement] = [:]
        for scenes in root.elements(forName: Strings.xmlScenes) {
            for scene in scenes.elements(forName: Strings.xmlScene) {
                for objects in scene.elements(forName: Strings.xmlObjects) {
                    for child in objects.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                        let xmlName = child.name ?? Strings.empty
                        guard xmlName.contains(Strings.viewControllerSuffix) || xmlName == Strings.viewController else { continue }
                        let id = child.attribute(forName: Strings.attrId)?.stringValue ?? Strings.empty
                        let name = idToName[id] ?? resolveViewControllerName(element: child, idToName: idToName)
                        nameToElement[name] = child
                    }
                }
            }
        }

        for i in models.indices {
            let vcName = models[i].name
            // Attach outgoing segues
            models[i].segues = graph.outgoingEdges(from: vcName)
            // Mark navigation roots
            models[i].isNavigationRoot = graph.isNavigationRoot(vcName)

            if let element = nameToElement[vcName] {
                // Navigation title from <navigationItem>
                models[i].navigationTitle = navigationTitle(from: element)
                // Tab bar item info
                models[i].tabBarItem = tabBarItemInfo(from: element)
            }
        }
    }

    // MARK: - Navigation Parsing Helpers

    /// Extracts the rootViewController name from a `<navigationController>` element.
    private static func navigationControllerRoot(element: XMLElement, idToName: [String: String]) -> String? {
        for connections in element.elements(forName: Strings.xmlConnections) {
            for segue in connections.elements(forName: Strings.xmlSegue) {
                guard segue.attribute(forName: Strings.attrKind)?.stringValue == Strings.segueRelationship,
                      segue.attribute(forName: Strings.attrRelationship)?.stringValue == Strings.relationshipRootVC
                else { continue }
                if let dest = segue.attribute(forName: Strings.attrDestination)?.stringValue {
                    return idToName[dest]
                }
            }
        }
        return nil
    }

    /// Extracts ordered tab entries from a `<tabBarController>` element.
    private static func tabBarTabs(
        element: XMLElement,
        idToName: [String: String],
        idToElement: [String: XMLElement]
    ) -> [SegueEdge] {
        var tabs: [SegueEdge] = []
        var tabIndex = 0
        for connections in element.elements(forName: Strings.xmlConnections) {
            for segue in connections.elements(forName: Strings.xmlSegue) {
                guard segue.attribute(forName: Strings.attrKind)?.stringValue == Strings.segueRelationship,
                      segue.attribute(forName: Strings.attrRelationship)?.stringValue == Strings.relationshipViewControllers
                else { continue }
                guard let destID = segue.attribute(forName: Strings.attrDestination)?.stringValue,
                      let destName = idToName[destID]
                else { continue }

                // Read tab bar item from destination element
                let destElement = idToElement[destID]
                let title = destElement.flatMap { tabBarItemInfo(from: $0)?.title } ?? destName
                let image = destElement.flatMap { tabBarItemInfo(from: $0)?.image }

                // Resolve the source name (the tab bar controller's name)
                let sourceID = element.attribute(forName: Strings.attrId)?.stringValue ?? Strings.empty
                let sourceName = idToName[sourceID] ?? Strings.tabBarController

                tabs.append(SegueEdge(
                    identifier: nil,
                    sourceVC: sourceName,
                    destinationVC: destName,
                    kind: .tab,
                    tabTitle: title,
                    tabImage: image,
                    tabIndex: tabIndex
                ))
                tabIndex += 1
            }
        }
        return tabs
    }

    /// Recursively collects all action `<segue>` elements from a view controller element
    /// (including segues nested inside buttons, cells, gesture recognizers, etc.).
    private static func collectSegueEdges(
        from element: XMLElement,
        sourceVC: String,
        idToName: [String: String]
    ) -> [SegueEdge] {
        var edges: [SegueEdge] = []
        for connections in element.elements(forName: Strings.xmlConnections) {
            for segue in connections.elements(forName: Strings.xmlSegue) {
                if let edge = segueEdge(from: segue, sourceVC: sourceVC, idToName: idToName) {
                    edges.append(edge)
                }
            }
        }
        // Recurse into child elements (buttons, cells, gesture recognizers carry segues too)
        for child in element.children?.compactMap({ $0 as? XMLElement }) ?? [] {
            // Don't recurse into sub-scenes (avoid crossing scene boundaries)
            guard child.name != Strings.xmlScene else { continue }
            edges.append(contentsOf: collectSegueEdges(from: child, sourceVC: sourceVC, idToName: idToName))
        }
        return edges
    }

    /// Maps a single `<segue>` XML element to a `SegueEdge`, skipping relationship segues.
    private static func segueEdge(
        from segue: XMLElement,
        sourceVC: String,
        idToName: [String: String]
    ) -> SegueEdge? {
        guard let kindString = segue.attribute(forName: Strings.attrKind)?.stringValue,
              kindString != Strings.segueRelationship,   // handled separately as containers
              kindString != Strings.segueUnwind          // unwind has no useful destination for generation
        else { return nil }

        guard let destID = segue.attribute(forName: Strings.attrDestination)?.stringValue,
              let destName = idToName[destID]
        else { return nil }

        let identifier = segue.attribute(forName: Strings.attrIdentifier)?.stringValue
        let kind = IBSegueMapper.segueKind(forKindString: kindString, segueElement: segue)

        return SegueEdge(
            identifier: identifier,
            sourceVC: sourceVC,
            destinationVC: destName,
            kind: kind
        )
    }

    /// Reads the navigation bar title from a `<navigationItem key="navigationItem">` child.
    private static func navigationTitle(from element: XMLElement) -> String? {
        for child in element.children?.compactMap({ $0 as? XMLElement }) ?? [] {
            if child.name == Strings.xmlNavigationItem,
               child.attribute(forName: Strings.attrKey)?.stringValue == Strings.keyNavigationItem {
                return child.attribute(forName: Strings.attrTitle)?.stringValue
            }
        }
        return nil
    }

    /// Reads tab bar item info from a `<tabBarItem key="tabBarItem">` child.
    private static func tabBarItemInfo(from element: XMLElement) -> TabBarItemInfo? {
        for child in element.children?.compactMap({ $0 as? XMLElement }) ?? [] {
            if child.name == Strings.xmlTabBarItem,
               child.attribute(forName: Strings.attrKey)?.stringValue == Strings.keyTabBarItem {
                let title = child.attribute(forName: Strings.attrTitle)?.stringValue ?? Strings.empty
                let image = child.attribute(forName: Strings.attrImage)?.stringValue
                return TabBarItemInfo(title: title, image: image)
            }
        }
        return nil
    }

    private enum Strings {
        static let empty = ""
        static let viewSuffix = "View"
        static let viewController = "viewController"
        static let viewControllerSuffix = "ViewController"
        static let defaultViewControllerName = "ViewController"
        static let tabBarController = "TabBarController"

        static let xmlScenes = "scenes"
        static let xmlScene = "scene"
        static let xmlObjects = "objects"
        static let xmlSubviews = "subviews"
        static let xmlConnections = "connections"
        static let xmlOutlet = "outlet"
        static let xmlConstraints = "constraints"
        static let xmlConstraint = "constraint"
        static let xmlView = "view"
        static let xmlSegue = "segue"
        static let xmlNavigationController = "navigationController"
        static let xmlTabBarController = "tabBarController"
        static let xmlNavigationItem = "navigationItem"
        static let xmlTabBarItem = "tabBarItem"

        static let attrId = "id"
        static let attrCustomClass = "customClass"
        static let attrStoryboardIdentifier = "storyboardIdentifier"
        static let attrProperty = "property"
        static let attrDestination = "destination"
        static let attrKind = "kind"
        static let attrRelationship = "relationship"
        static let attrIdentifier = "identifier"
        static let attrInitialViewController = "initialViewController"
        static let attrKey = "key"
        static let attrTitle = "title"
        static let attrImage = "image"

        static let segueRelationship = "relationship"
        static let segueUnwind = "unwind"
        static let relationshipRootVC = "rootViewController"
        static let relationshipViewControllers = "viewControllers"

        static let keyNavigationItem = "navigationItem"
        static let keyTabBarItem = "tabBarItem"
    }
}
