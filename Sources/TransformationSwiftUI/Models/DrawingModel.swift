// SPDX-License-Identifier: MIT
//
// DrawingModel.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Model types for CoreGraphics and UIBezierPath drawing commands
//              extracted from draw(_ rect:) overrides in UIView subclasses.
//

import Foundation

// MARK: - DrawingCommand

/// A single drawing operation extracted from a `draw(_ rect:)` override.
public enum DrawingCommand {
    /// `path.move(to:)` or `ctx.move(to:)`
    case moveTo(x: String, y: String)
    /// `path.addLine(to:)` or `ctx.addLine(to:)`
    case lineTo(x: String, y: String)
    /// `path.addCurve(to:controlPoint1:controlPoint2:)` or CGContext equivalent
    case curveTo(x: String, y: String, cp1x: String, cp1y: String, cp2x: String, cp2y: String)
    /// `path.addQuadCurve(to:controlPoint:)`
    case quadCurveTo(x: String, y: String, cpx: String, cpy: String)
    /// `path.addArc(center:radius:startAngle:endAngle:clockwise:)`
    case arc(centerX: String, centerY: String, radius: String, startAngle: String, endAngle: String, clockwise: Bool)
    /// `CGContext.addRect(_:)` or `UIBezierPath(rect:)`
    case addRect(x: String, y: String, width: String, height: String)
    /// `CGContext.addEllipse(in:)` or `UIBezierPath(ovalIn:)`
    case addEllipse(x: String, y: String, width: String, height: String)
    /// `path.close()` or `ctx.closePath()`
    case closePath
    /// `UIColor.xxx.setFill()` or `ctx.setFillColor(...)`
    case setFillColor(String)
    /// `UIColor.xxx.setStroke()` or `ctx.setStrokeColor(...)`
    case setStrokeColor(String)
    /// `ctx.setLineWidth(_:)`
    case setLineWidth(String)
    /// `path.fill()` or `ctx.fillPath()`
    case fill
    /// `path.stroke()` or `ctx.strokePath()`
    case stroke
    /// `ctx.translateBy(x:y:)`
    case translateBy(x: String, y: String)
    /// `ctx.scaleBy(x:y:)`
    case scaleBy(x: String, y: String)
    /// `ctx.rotate(by:)`
    case rotateBy(String)
}

// MARK: - DrawingPathSegment

/// A logical path segment — a group of path-building commands followed by a fill or stroke operation.
public struct DrawingPathSegment {
    /// The ordered drawing commands in this segment.
    public let commands: [DrawingCommand]

    /// The resolved SwiftUI fill color expression, if any.
    public let fillColor: String?

    /// The resolved SwiftUI stroke color expression, if any.
    public let strokeColor: String?

    /// The line width expression, if any.
    public let lineWidth: String?

    public init(
        commands: [DrawingCommand],
        fillColor: String?,
        strokeColor: String?,
        lineWidth: String?
    ) {
        self.commands = commands
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
    }
}

// MARK: - DrawingModel

/// The complete drawing model for a custom UIView subclass that overrides `draw(_ rect:)`.
public struct DrawingModel {
    /// The name of the UIView subclass this drawing model belongs to.
    public let className: String

    /// The ordered path segments extracted from the draw method.
    public let segments: [DrawingPathSegment]

    /// True when the drawing can be expressed as a SwiftUI `Shape` conformance:
    /// single segment, single path, no context transforms.
    /// False when a `Canvas` view is more appropriate (multiple segments or transforms).
    public let isSimpleShape: Bool

    /// True when CGContext transform calls (`translateBy`, `scaleBy`, `rotate`) were used.
    public let usesContextTransforms: Bool

    public init(
        className: String,
        segments: [DrawingPathSegment],
        isSimpleShape: Bool,
        usesContextTransforms: Bool
    ) {
        self.className = className
        self.segments = segments
        self.isSimpleShape = isSimpleShape
        self.usesContextTransforms = usesContextTransforms
    }
}
