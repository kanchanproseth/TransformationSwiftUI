// SPDX-License-Identifier: MIT
//
// IBSegueMapper.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Maps Interface Builder segue kind strings to SegueKind enum values.
//

import Foundation

/// Maps Interface Builder segue `kind` attribute strings to `SegueKind` values.
///
/// Follows the same stateless mapper pattern as `IBElementMapper` and `IBConstraintMapper`.
struct IBSegueMapper {

    // MARK: - Kind String → SegueKind

    /// Maps IB `kind` attribute strings to base `SegueKind` values.
    ///
    /// Note: `"presentation"` and `"modal"` may be further refined to `.fullScreenCover`
    /// based on the `modalPresentationStyle` attribute — use `segueKind(forKindString:segueElement:)`
    /// to apply that refinement automatically.
    private static let kindMap: [String: SegueKind] = [
        "show": .push,
        "push": .push,          // legacy pre-iOS 8
        "showDetail": .sheet,
        "presentation": .sheet,
        "modal": .sheet,         // legacy pre-iOS 8
        "popoverPresentation": .sheet,
        "embed": .embed,
        "unwind": .unwind,
        "custom": .custom,
    ]

    /// Resolves the `SegueKind` for a `<segue>` XML element, applying modal style refinement.
    ///
    /// - Parameters:
    ///   - kindString: The value of the `kind` attribute.
    ///   - segueElement: The full `<segue>` XMLElement (used to check `modalPresentationStyle`).
    /// - Returns: The corresponding `SegueKind`, defaulting to `.custom` for unknown kinds.
    static func segueKind(forKindString kindString: String, segueElement: XMLElement) -> SegueKind {
        let base = kindMap[kindString] ?? .custom

        // Presentation segues with fullScreen style map to .fullScreenCover
        if base == .sheet {
            let style = segueElement.attribute(forName: "modalPresentationStyle")?.stringValue
            if style == "fullScreen" || style == "overFullScreen" {
                return .fullScreenCover
            }
        }

        return base
    }

    /// Resolves a `SegueKind` from a kind string without a segue element (no style refinement).
    static func segueKind(forKindString kindString: String) -> SegueKind {
        kindMap[kindString] ?? .custom
    }
}
