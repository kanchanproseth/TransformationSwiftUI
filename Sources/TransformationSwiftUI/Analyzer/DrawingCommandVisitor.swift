// SPDX-License-Identifier: MIT
//
// DrawingCommandVisitor.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: SwiftSyntax visitor that detects `override func draw(_ rect: CGRect)`
//              in UIView subclasses and extracts CoreGraphics / UIBezierPath drawing
//              commands into a DrawingModel.
//

import Foundation
import SwiftSyntax

/// Visits a class body to extract drawing commands from `draw(_ rect:)` overrides.
public class DrawingCommandVisitor: SyntaxVisitor {

    /// The drawing model built after walking; nil if no draw override was found.
    public private(set) var drawingModel: DrawingModel?

    /// The name of the class being analysed.
    private let className: String

    /// Accumulated raw commands collected while inside the draw method.
    private var rawCommands: [DrawingCommand] = []

    /// True while visiting the body of the draw(_ rect:) override.
    private var isInsideDrawMethod = false

    /// True when any CGContext transform call was detected.
    private var usesContextTransforms = false

    /// Creates a visitor for the named class.
    public init(className: String) {
        self.className = className
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - draw(_ rect:) detection

    override public func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isDrawOverride(node) else { return .visitChildren }
        isInsideDrawMethod = true
        return .visitChildren
    }

    override public func visitPost(_ node: FunctionDeclSyntax) {
        if isDrawOverride(node) {
            isInsideDrawMethod = false
        }
    }

    private func isDrawOverride(_ node: FunctionDeclSyntax) -> Bool {
        guard node.name.text == Strings.draw else { return false }
        let hasOverride = node.modifiers.contains {
            $0.name.text == Strings.override
        }
        guard hasOverride else { return false }
        guard let params = node.signature.parameterClause.parameters.first else { return false }
        let typeText = params.type.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return typeText.contains(Strings.cgRect)
    }

    // MARK: - Drawing call detection

    override public func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard isInsideDrawMethod else { return .visitChildren }

        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            return .visitChildren
        }

        let methodName = memberAccess.declName.baseName.text
        let baseText = memberAccess.base?.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? Strings.empty

        // UIBezierPath instance calls (e.g., `path.move(to:)`)
        if isPathMethod(methodName) {
            parseBezierPathCall(methodName: methodName, node: node)
            return .visitChildren
        }

        // UIColor.xxx.setFill() / .setStroke()
        if methodName == Strings.setFill || methodName == Strings.setStroke {
            parseColorSetCall(base: baseText, methodName: methodName)
            return .visitChildren
        }

        // CGContext calls (guard: base is a local variable, not UIBezierPath static)
        if isCGContextMethod(methodName) {
            parseCGContextCall(methodName: methodName, node: node)
            return .visitChildren
        }

        return .visitChildren
    }

    // MARK: - UIBezierPath parsing

    private func isPathMethod(_ name: String) -> Bool {
        [Strings.move, Strings.addLine, Strings.addCurve, Strings.addQuadCurve,
         Strings.addArc, Strings.close, Strings.fill, Strings.stroke, ].contains(name)
    }

    private func parseBezierPathCall(methodName: String, node: FunctionCallExprSyntax) {
        let args = argumentMap(node)
        switch methodName {
        case Strings.move:
            let pt = args[Strings.to] ?? Strings.zero
            rawCommands.append(.moveTo(x: pointX(pt), y: pointY(pt)))
        case Strings.addLine:
            let pt = args[Strings.to] ?? Strings.zero
            rawCommands.append(.lineTo(x: pointX(pt), y: pointY(pt)))
        case Strings.addCurve:
            let pt = args[Strings.to] ?? Strings.zero
            let cp1 = args[Strings.controlPoint1] ?? Strings.zero
            let cp2 = args[Strings.controlPoint2] ?? Strings.zero
            rawCommands.append(.curveTo(x: pointX(pt), y: pointY(pt),
                                        cp1x: pointX(cp1), cp1y: pointY(cp1),
                                        cp2x: pointX(cp2), cp2y: pointY(cp2)))
        case Strings.addQuadCurve:
            let pt = args[Strings.to] ?? Strings.zero
            let cp = args[Strings.controlPoint] ?? Strings.zero
            rawCommands.append(.quadCurveTo(x: pointX(pt), y: pointY(pt),
                                             cpx: pointX(cp), cpy: pointY(cp)))
        case Strings.addArc:
            rawCommands.append(.arc(
                centerX: pointX(args[Strings.center] ?? Strings.zero),
                centerY: pointY(args[Strings.center] ?? Strings.zero),
                radius: args[Strings.radius] ?? Strings.zero,
                startAngle: args[Strings.startAngle] ?? Strings.zero,
                endAngle: args[Strings.endAngle] ?? Strings.zero,
                clockwise: args[Strings.clockwise] == Strings.trueKeyword
            ))
        case Strings.close:
            rawCommands.append(.closePath)
        case Strings.fill:
            rawCommands.append(.fill)
        case Strings.stroke:
            rawCommands.append(.stroke)
        default:
            break
        }
    }

    // MARK: - CGContext parsing

    private func isCGContextMethod(_ name: String) -> Bool {
        [Strings.beginPath, Strings.fillPath, Strings.strokePath,
         Strings.setFillColor, Strings.setStrokeColor, Strings.setLineWidth,
         Strings.translateBy, Strings.scaleBy, Strings.rotate,
         Strings.addRect, Strings.addEllipse, ].contains(name)
    }

    private func parseCGContextCall(methodName: String, node: FunctionCallExprSyntax) {
        let args = argumentMap(node)
        switch methodName {
        case Strings.fillPath:
            rawCommands.append(.fill)
        case Strings.strokePath:
            rawCommands.append(.stroke)
        case Strings.setFillColor:
            let color = firstArg(node)
            rawCommands.append(.setFillColor(color))
        case Strings.setStrokeColor:
            let color = firstArg(node)
            rawCommands.append(.setStrokeColor(color))
        case Strings.setLineWidth:
            let w = firstArg(node)
            rawCommands.append(.setLineWidth(w))
        case Strings.translateBy:
            rawCommands.append(.translateBy(x: args[Strings.x] ?? Strings.zero,
                                            y: args[Strings.y] ?? Strings.zero))
            usesContextTransforms = true
        case Strings.scaleBy:
            rawCommands.append(.scaleBy(x: args[Strings.x] ?? Strings.zero,
                                        y: args[Strings.y] ?? Strings.zero))
            usesContextTransforms = true
        case Strings.rotate:
            rawCommands.append(.rotateBy(args[Strings.by] ?? Strings.zero))
            usesContextTransforms = true
        case Strings.addRect:
            let r = firstArg(node)
            rawCommands.append(.addRect(x: Strings.zero, y: Strings.zero, width: rectWidth(r), height: rectHeight(r)))
        case Strings.addEllipse:
            let r = args[Strings.in] ?? firstArg(node)
            rawCommands.append(.addEllipse(x: Strings.zero, y: Strings.zero, width: rectWidth(r), height: rectHeight(r)))
        default:
            break
        }
    }

    // MARK: - Color set call parsing

    private func parseColorSetCall(base: String, methodName: String) {
        let colorName = resolveColor(base)
        if methodName == Strings.setFill {
            rawCommands.append(.setFillColor(colorName))
        } else {
            rawCommands.append(.setStrokeColor(colorName))
        }
    }

    // MARK: - Build final model

    /// Call this after walking to assemble the `DrawingModel` from collected raw commands.
    public func buildModel() {
        guard !rawCommands.isEmpty else { return }

        // Split rawCommands into segments at each fill/stroke boundary
        var segments: [DrawingPathSegment] = []
        var currentCommands: [DrawingCommand] = []
        var currentFill: String?
        var currentStroke: String?
        var currentLineWidth: String?

        for cmd in rawCommands {
            switch cmd {
            case .setFillColor(let c):
                currentFill = c
            case .setStrokeColor(let c):
                currentStroke = c
            case .setLineWidth(let w):
                currentLineWidth = w
            case .fill:
                currentCommands.append(cmd)
                segments.append(DrawingPathSegment(
                    commands: currentCommands,
                    fillColor: currentFill,
                    strokeColor: nil,
                    lineWidth: currentLineWidth
                ))
                currentCommands = []
            case .stroke:
                currentCommands.append(cmd)
                segments.append(DrawingPathSegment(
                    commands: currentCommands,
                    fillColor: nil,
                    strokeColor: currentStroke,
                    lineWidth: currentLineWidth
                ))
                currentCommands = []
            default:
                currentCommands.append(cmd)
            }
        }
        // Flush any remaining commands as a final segment
        if !currentCommands.isEmpty {
            segments.append(DrawingPathSegment(
                commands: currentCommands,
                fillColor: currentFill,
                strokeColor: currentStroke,
                lineWidth: currentLineWidth
            ))
        }

        let isSimple = segments.count == 1 && !usesContextTransforms
        drawingModel = DrawingModel(
            className: className,
            segments: segments,
            isSimpleShape: isSimple,
            usesContextTransforms: usesContextTransforms
        )
    }

    // MARK: - Argument extraction helpers

    private func argumentMap(_ node: FunctionCallExprSyntax) -> [String: String] {
        var map: [String: String] = [:]
        for arg in node.arguments {
            let key = arg.label?.text ?? Strings.empty
            let val = arg.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
            map[key] = val
        }
        return map
    }

    private func firstArg(_ node: FunctionCallExprSyntax) -> String {
        node.arguments.first?.expression.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? Strings.zero
    }

    /// Extracts the x component from a CGPoint expression string.
    private func pointX(_ expr: String) -> String {
        if let range = expr.range(of: "x:") {
            let after = String(expr[range.upperBound...])
            let val = after.components(separatedBy: CharacterSet(charactersIn: ",)")).first ?? Strings.zero
            return val.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return expr
    }

    /// Extracts the y component from a CGPoint expression string.
    private func pointY(_ expr: String) -> String {
        if let range = expr.range(of: "y:") {
            let after = String(expr[range.upperBound...])
            let val = after.components(separatedBy: CharacterSet(charactersIn: ",)")).first ?? Strings.zero
            return val.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return expr
    }

    private func rectWidth(_ expr: String) -> String {
        if let range = expr.range(of: "width:") {
            let after = String(expr[range.upperBound...])
            return after.components(separatedBy: CharacterSet(charactersIn: ",)")).first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? Strings.zero
        }
        return Strings.zero
    }

    private func rectHeight(_ expr: String) -> String {
        if let range = expr.range(of: "height:") {
            let after = String(expr[range.upperBound...])
            return after.components(separatedBy: CharacterSet(charactersIn: ",)")).first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? Strings.zero
        }
        return Strings.zero
    }

    private func resolveColor(_ base: String) -> String {
        // e.g., "UIColor.red" -> "Color.red"
        let stripped = base.replacingOccurrences(of: Strings.uiColor + Strings.dot, with: Strings.colorPrefix)
        return stripped
    }

    // MARK: - String constants

    private enum Strings {
        static let empty = ""
        static let zero = "0"
        static let dot = "."
        static let draw = "draw"
        static let override = "override"
        static let cgRect = "CGRect"
        static let uiColor = "UIColor"
        static let colorPrefix = "Color."
        static let move = "move"
        static let addLine = "addLine"
        static let addCurve = "addCurve"
        static let addQuadCurve = "addQuadCurve"
        static let addArc = "addArc"
        static let close = "close"
        static let fill = "fill"
        static let stroke = "stroke"
        static let setFill = "setFill"
        static let setStroke = "setStroke"
        static let beginPath = "beginPath"
        static let fillPath = "fillPath"
        static let strokePath = "strokePath"
        static let setFillColor = "setFillColor"
        static let setStrokeColor = "setStrokeColor"
        static let setLineWidth = "setLineWidth"
        static let translateBy = "translateBy"
        static let scaleBy = "scaleBy"
        static let rotate = "rotate"
        static let addRect = "addRect"
        static let addEllipse = "addEllipse"
        static let to = "to"
        static let controlPoint = "controlPoint"
        static let controlPoint1 = "controlPoint1"
        static let controlPoint2 = "controlPoint2"
        static let center = "center"
        static let radius = "radius"
        static let startAngle = "startAngle"
        static let endAngle = "endAngle"
        static let clockwise = "clockwise"
        static let trueKeyword = "true"
        static let x = "x"
        static let y = "y"
        static let by = "by"
        static let `in` = "in"
    }
}
