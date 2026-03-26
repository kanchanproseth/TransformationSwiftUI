// SPDX-License-Identifier: MIT
//
// UIKitElementType.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Known UIKit element types used by the analyzer and generator.
//

import Foundation

/// Known UIKit element types used by the analyzer and generator.
public enum UIKitElementType: CaseIterable {
    case label
    case button
    case imageView
    case image
    case stackView
    case view
    case scrollView
    case textField
    case textView
    case toggleSwitch
    case slider
    case progressView
    case tableView
    case collectionView
    case activityIndicatorView
    case segmentedControl
    case pageControl
    case visualEffectView
    case viewController

    /// The UIKit type name used in source and XML matching.
    public var typeName: String {
        switch self {
        case .label:
            return Strings.uiLabel
        case .button:
            return Strings.uiButton
        case .imageView:
            return Strings.uiImageView
        case .image:
            return Strings.uiImage
        case .stackView:
            return Strings.uiStackView
        case .view:
            return Strings.uiView
        case .scrollView:
            return Strings.uiScrollView
        case .textField:
            return Strings.uiTextField
        case .textView:
            return Strings.uiTextView
        case .toggleSwitch:
            return Strings.uiSwitch
        case .slider:
            return Strings.uiSlider
        case .progressView:
            return Strings.uiProgressView
        case .tableView:
            return Strings.uiTableView
        case .collectionView:
            return Strings.uiCollectionView
        case .activityIndicatorView:
            return Strings.uiActivityIndicatorView
        case .segmentedControl:
            return Strings.uiSegmentedControl
        case .pageControl:
            return Strings.uiPageControl
        case .visualEffectView:
            return Strings.uiVisualEffectView
        case .viewController:
            return Strings.uiViewController
        }
    }

    /// Components supported by the analyzer for basic discovery.
    public static let supportedComponents: Set<UIKitElementType> = [
        .label,
        .button,
        .imageView,
        .textField,
        .stackView,
    ]

    /// Parses a type annotation into a UIKitElementType if known.
    public static func from(typeName: String?) -> UIKitElementType? {
        guard let normalized = normalizedTypeName(typeName) else { return nil }
        return allCases.first { $0.typeName == normalized }
    }

    /// Returns true when a type annotation represents a UIViewController subclass.
    public static func isViewController(typeName: String) -> Bool {
        guard let normalized = normalizedTypeName(typeName) else { return false }
        return normalized == UIKitElementType.viewController.typeName
    }

    private static func normalizedTypeName(_ raw: String?) -> String? {
        guard var raw else { return nil }
        raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }
        if raw.hasSuffix(Strings.optionalSuffixQuestion) || raw.hasSuffix(Strings.optionalSuffixExclamation) {
            raw = String(raw.dropLast())
        }
        if let genericIndex = raw.firstIndex(of: Strings.genericStartCharacter) {
            raw = String(raw[..<genericIndex])
        }
        return raw
    }

    private enum Strings {
        static let uiLabel = "UILabel"
        static let uiButton = "UIButton"
        static let uiImageView = "UIImageView"
        static let uiImage = "UIImage"
        static let uiStackView = "UIStackView"
        static let uiView = "UIView"
        static let uiScrollView = "UIScrollView"
        static let uiTextField = "UITextField"
        static let uiTextView = "UITextView"
        static let uiSwitch = "UISwitch"
        static let uiSlider = "UISlider"
        static let uiProgressView = "UIProgressView"
        static let uiTableView = "UITableView"
        static let uiCollectionView = "UICollectionView"
        static let uiActivityIndicatorView = "UIActivityIndicatorView"
        static let uiSegmentedControl = "UISegmentedControl"
        static let uiPageControl = "UIPageControl"
        static let uiVisualEffectView = "UIVisualEffectView"
        static let uiViewController = "UIViewController"

        static let optionalSuffixQuestion = "?"
        static let optionalSuffixExclamation = "!"
        static let genericStartCharacter: Character = "<"
    }
}
