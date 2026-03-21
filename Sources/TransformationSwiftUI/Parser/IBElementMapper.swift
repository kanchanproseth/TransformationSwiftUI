// SPDX-License-Identifier: MIT
//
// IBElementMapper.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Maps Interface Builder XML elements and attributes to internal model types.
//

import Foundation

/// Maps Interface Builder XML element names and attributes to the internal model types.
public struct IBElementMapper {

    // MARK: - XML Name → UIKitElementType

    private static let xmlNameMap: [String: UIKitElementType] = [
        Strings.xmlLabel: .label,
        Strings.xmlButton: .button,
        Strings.xmlImageView: .imageView,
        Strings.xmlTextField: .textField,
        Strings.xmlTextView: .textView,
        Strings.xmlSwitch: .toggleSwitch,
        Strings.xmlSlider: .slider,
        Strings.xmlProgressView: .progressView,
        Strings.xmlStackView: .stackView,
        Strings.xmlScrollView: .scrollView,
        Strings.xmlView: .view,
        Strings.xmlTableView: .tableView,
        Strings.xmlCollectionView: .collectionView,
        Strings.xmlActivityIndicatorView: .activityIndicatorView,
        Strings.xmlSegmentedControl: .segmentedControl,
        Strings.xmlPageControl: .pageControl,
        Strings.xmlVisualEffectView: .visualEffectView,
    ]

    /// Returns the UIKitElementType for a given XML element tag name (e.g., "label" → .label).
    public static func elementType(forXMLName xmlName: String) -> UIKitElementType? {
        xmlNameMap[xmlName]
    }

    // MARK: - Property Extraction

    /// Extracts display-relevant properties from an XML element into a string dictionary.
    public static func extractProperties(from element: XMLElement) -> [String: String] {
        var props: [String: String] = [:]
        let xmlName = element.name ?? Strings.empty

        switch xmlName {
        case Strings.xmlLabel:
            if let text = element.attribute(forName: Strings.attrText)?.stringValue, !text.isEmpty {
                props[Strings.propText] = text
            }

        case Strings.xmlButton:
            // Button titles live in <state key="normal" title="...">
            for child in element.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                if child.name == Strings.xmlState,
                   child.attribute(forName: Strings.attrKey)?.stringValue == Strings.stateNormal {
                    if let title = child.attribute(forName: Strings.attrTitle)?.stringValue {
                        props[Strings.propTitle] = title
                    }
                    if let image = child.attribute(forName: Strings.attrImage)?.stringValue {
                        props[Strings.propImageName] = image
                    }
                }
            }

        case Strings.xmlImageView:
            if let imageName = element.attribute(forName: Strings.attrImage)?.stringValue, !imageName.isEmpty {
                props[Strings.propImageName] = imageName
            }

        case Strings.xmlTextField:
            if let placeholder = element.attribute(forName: Strings.attrPlaceholder)?.stringValue {
                props[Strings.propPlaceholder] = placeholder
            }
            if let text = element.attribute(forName: Strings.attrText)?.stringValue {
                props[Strings.propText] = text
            }

        case Strings.xmlTextView:
            if let text = element.attribute(forName: Strings.attrText)?.stringValue {
                props[Strings.propText] = text
            }

        case Strings.xmlStackView:
            if let axis = element.attribute(forName: Strings.attrAxis)?.stringValue {
                props[Strings.propAxis] = axis  // "vertical" or "horizontal"
            }
            if let spacing = element.attribute(forName: Strings.attrSpacing)?.stringValue {
                props[Strings.propSpacing] = spacing
            }
            if let alignment = element.attribute(forName: Strings.attrAlignment)?.stringValue {
                props[Strings.propAlignment] = alignment
            }

        case Strings.xmlSwitch:
            if let on = element.attribute(forName: Strings.attrOn)?.stringValue {
                props[Strings.propOn] = on  // "YES" or "NO"
            }

        case Strings.xmlSlider:
            if let value = element.attribute(forName: Strings.attrValue)?.stringValue {
                props[Strings.propValue] = value
            }
            if let minValue = element.attribute(forName: Strings.attrMinValue)?.stringValue {
                props[Strings.propMinValue] = minValue
            }
            if let maxValue = element.attribute(forName: Strings.attrMaxValue)?.stringValue {
                props[Strings.propMaxValue] = maxValue
            }

        case Strings.xmlProgressView:
            if let progress = element.attribute(forName: Strings.attrProgress)?.stringValue {
                props[Strings.propProgress] = progress
            }

        case Strings.xmlSegmentedControl:
            // Segment titles live in <segments><segment title="...">
            var titles: [String] = []
            for segments in element.elements(forName: Strings.xmlSegments) {
                for segment in segments.elements(forName: Strings.xmlSegment) {
                    if let title = segment.attribute(forName: Strings.attrTitle)?.stringValue {
                        titles.append(title)
                    }
                }
            }
            if !titles.isEmpty {
                props[Strings.propSegmentTitles] = titles.joined(separator: Strings.comma)
            }

        default:
            break
        }

        return props
    }

    // MARK: - Name Resolution

    /// Resolves a human-readable name for an IB element.
    ///
    /// Priority:
    /// 1. Outlet property name (caller provides via outletMap)
    /// 2. customClass attribute → camelCased
    /// 3. userLabel attribute → camelCased
    /// 4. Content-derived name (label text, button title, placeholder)
    /// 5. Fallback: "{xmlName}_{shortId}"
    static func resolveName(
        for element: XMLElement,
        xmlName: String,
        outletMap: [String: String] = [:]
    ) -> String {
        let elementID = element.attribute(forName: Strings.attrId)?.stringValue ?? Strings.empty

        // 1. Outlet property name
        if let outletName = outletMap[elementID], !outletName.isEmpty {
            return outletName
        }

        // 2. customClass attribute
        if let customClass = element.attribute(forName: Strings.attrCustomClass)?.stringValue,
           !customClass.isEmpty {
            return camelCased(customClass)
        }

        // 3. userLabel attribute
        if let userLabel = element.attribute(forName: Strings.attrUserLabel)?.stringValue,
           !userLabel.isEmpty {
            return camelCased(userLabel)
        }

        // 4. Content-derived name
        let contentName = contentDerivedName(for: element, xmlName: xmlName)
        if let name = contentName {
            return name
        }

        // 5. Fallback: xmlName + short ID suffix
        let shortID = elementID.components(separatedBy: Strings.idSeparator).last ?? elementID
        return shortID.isEmpty ? xmlName : xmlName + Strings.nameSeparator + shortID
    }

    // MARK: - Private Helpers

    private static func contentDerivedName(for element: XMLElement, xmlName: String) -> String? {
        switch xmlName {
        case Strings.xmlLabel:
            guard let text = element.attribute(forName: Strings.attrText)?.stringValue, !text.isEmpty else {
                return nil
            }
            return camelCased(text) + Strings.suffixLabel

        case Strings.xmlButton:
            for child in element.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                if child.name == Strings.xmlState,
                   child.attribute(forName: Strings.attrKey)?.stringValue == Strings.stateNormal,
                   let title = child.attribute(forName: Strings.attrTitle)?.stringValue,
                   !title.isEmpty {
                    return camelCased(title) + Strings.suffixButton
                }
            }
            return nil

        case Strings.xmlTextField:
            guard let placeholder = element.attribute(forName: Strings.attrPlaceholder)?.stringValue,
                  !placeholder.isEmpty else { return nil }
            return camelCased(placeholder) + Strings.suffixTextField

        case Strings.xmlImageView:
            guard let image = element.attribute(forName: Strings.attrImage)?.stringValue,
                  !image.isEmpty else { return nil }
            return camelCased(image) + Strings.suffixImageView

        default:
            return nil
        }
    }

    /// Converts a string to camelCase (lowercases first character, removes spaces/special chars).
    static func camelCased(_ input: String) -> String {
        let words = input.components(separatedBy: .init(charactersIn: Strings.camelSeparators))
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return input }
        let first = words[0].prefix(1).lowercased() + words[0].dropFirst()
        let rest = words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }
        let combined = ([first] + rest).joined()
        // Remove non-alphanumeric characters
        let allowed = CharacterSet.alphanumerics
        return String(combined.unicodeScalars.filter { allowed.contains($0) })
    }

    private enum Strings {
        static let empty = ""
        static let comma = ","
        static let idSeparator = "-"
        static let nameSeparator = "_"

        static let xmlLabel = "label"
        static let xmlButton = "button"
        static let xmlImageView = "imageView"
        static let xmlTextField = "textField"
        static let xmlTextView = "textView"
        static let xmlSwitch = "switch"
        static let xmlSlider = "slider"
        static let xmlProgressView = "progressView"
        static let xmlStackView = "stackView"
        static let xmlScrollView = "scrollView"
        static let xmlView = "view"
        static let xmlTableView = "tableView"
        static let xmlCollectionView = "collectionView"
        static let xmlActivityIndicatorView = "activityIndicatorView"
        static let xmlSegmentedControl = "segmentedControl"
        static let xmlPageControl = "pageControl"
        static let xmlVisualEffectView = "visualEffectView"
        static let xmlState = "state"
        static let xmlSegments = "segments"
        static let xmlSegment = "segment"

        static let attrText = "text"
        static let attrTitle = "title"
        static let attrImage = "image"
        static let attrPlaceholder = "placeholder"
        static let attrAxis = "axis"
        static let attrSpacing = "spacing"
        static let attrAlignment = "alignment"
        static let attrOn = "on"
        static let attrValue = "value"
        static let attrMinValue = "minValue"
        static let attrMaxValue = "maxValue"
        static let attrProgress = "progress"
        static let attrKey = "key"
        static let attrId = "id"
        static let attrCustomClass = "customClass"
        static let attrUserLabel = "userLabel"

        static let propText = "text"
        static let propTitle = "title"
        static let propImageName = "imageName"
        static let propPlaceholder = "placeholder"
        static let propAxis = "axis"
        static let propSpacing = "spacing"
        static let propAlignment = "alignment"
        static let propOn = "on"
        static let propValue = "value"
        static let propMinValue = "minValue"
        static let propMaxValue = "maxValue"
        static let propProgress = "progress"
        static let propSegmentTitles = "segmentTitles"

        static let stateNormal = "normal"

        static let suffixLabel = "Label"
        static let suffixButton = "Button"
        static let suffixTextField = "TextField"
        static let suffixImageView = "ImageView"

        static let camelSeparators = " _-"
    }
}
