// SPDX-License-Identifier: MIT
//
// DrawingRenderer.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Generates SwiftUI Shape conformances or Canvas views from DrawingModel
//              instances extracted from UIView draw(_ rect:) overrides.
//

import Foundation

/// Generates SwiftUI drawing code from a `DrawingModel`.
public struct DrawingRenderer {

    // MARK: - Entry point

    /// Generates a complete Swift file containing either a `Shape` conformance (simple drawings)
    /// or a `Canvas`-backed `View` (complex drawings with multiple segments or transforms).
    ///
    /// - Parameter model: The drawing model from `DrawingCommandVisitor`.
    /// - Returns: The complete Swift file content as a string.
    public static func generate(for model: DrawingModel) -> String {
        var lines: [String] = []
        lines.append(Strings.importSwiftUI)
        lines.append(Strings.empty)

        if model.isSimpleShape {
            lines.append(contentsOf: generateShape(for: model))
        } else {
            lines.append(contentsOf: generateCanvasView(for: model))
        }

        lines.append(Strings.empty)
        lines.append(contentsOf: generatePreview(for: model))
        return lines.joined(separator: Strings.newline)
    }

    // MARK: - Simple Shape generation

    private static func generateShape(for model: DrawingModel) -> [String] {
        let segment = model.segments.first
        let fillColor: String? = segment?.fillColor
        let strokeColor = segment?.strokeColor
        let lineWidth = segment?.lineWidth

        var lines: [String] = []
        lines.append("struct \(model.className): Shape {")
        lines.append("    func path(in rect: CGRect) -> Path {")
        lines.append("        var path = Path()")

        let pathCommands = (segment?.commands ?? []).filter { cmd in
            // Exclude fill/stroke/color setters from path — those become modifiers
            if case .fill = cmd { return false }
            if case .stroke = cmd { return false }
            if case .setFillColor = cmd { return false }
            if case .setStrokeColor = cmd { return false }
            if case .setLineWidth = cmd { return false }
            return true
        }

        for cmd in pathCommands {
            if let codeLine = pathCode(for: cmd, indent: 2) {
                lines.append(codeLine)
            }
        }

        lines.append("        return path")
        lines.append("    }")
        lines.append("}")

        // Emit usage hint as a comment
        lines.append(Strings.empty)
        lines.append("// Usage:")
        var usageModifiers: [String] = []
        if let fill = fillColor {
            usageModifiers.append(".fill(\(fill))")
        }
        if let stroke = strokeColor {
            let w = lineWidth ?? "1"
            usageModifiers.append(".stroke(\(stroke), lineWidth: \(w))")
        }
        let mods = usageModifiers.isEmpty ? "" : usageModifiers.joined(separator: "\n//         ")
        lines.append("// \(model.className)()\(mods.isEmpty ? "" : "\n//         \(mods)")")

        return lines
    }

    // MARK: - Canvas view generation

    private static func generateCanvasView(for model: DrawingModel) -> [String] {
        var lines: [String] = []
        lines.append("struct \(model.className)View: View {")
        lines.append("    var body: some View {")
        lines.append("        Canvas { context, size in")

        for (idx, segment) in model.segments.enumerated() {
            if idx > 0 { lines.append(Strings.empty) }

            // Filter path commands only
            let pathCmds = segment.commands.filter { cmd in
                if case .fill = cmd { return false }
                if case .stroke = cmd { return false }
                if case .setFillColor = cmd { return false }
                if case .setStrokeColor = cmd { return false }
                if case .setLineWidth = cmd { return false }
                if case .translateBy = cmd { return false }
                if case .scaleBy = cmd { return false }
                if case .rotateBy = cmd { return false }
                return true
            }

            if !pathCmds.isEmpty {
                lines.append("            var path\(idx == 0 ? "" : String(idx)) = Path()")
                for cmd in pathCmds {
                    if let code = canvasPathCode(for: cmd, pathVar: idx == 0 ? "path" : "path\(idx)", indent: 3) {
                        lines.append(code)
                    }
                }
            }

            // Transform commands
            let transforms = segment.commands.filter { cmd in
                if case .translateBy = cmd { return true }
                if case .scaleBy = cmd { return true }
                if case .rotateBy = cmd { return true }
                return false
            }
            for t in transforms {
                if let code = canvasTransformCode(for: t, indent: 3) {
                    lines.append(code)
                }
            }

            let pathVar = idx == 0 ? "path" : "path\(idx)"
            if let fill = segment.fillColor {
                lines.append("            context.fill(\(pathVar), with: .color(\(fill)))")
            } else if let stroke = segment.strokeColor {
                let lw = segment.lineWidth.map { ", lineWidth: \($0)" } ?? ""
                lines.append("            context.stroke(\(pathVar), with: .color(\(stroke))\(lw))")
            } else {
                lines.append("            context.fill(\(pathVar), with: .color(.primary))")
            }
        }

        lines.append("        }")
        lines.append("    }")
        lines.append("}")
        return lines
    }

    // MARK: - Path code helpers

    private static func pathCode(for command: DrawingCommand, indent: Int) -> String? {
        let prefix = String(repeating: "    ", count: indent)
        switch command {
        case .moveTo(let x, let y):
            return "\(prefix)path.move(to: CGPoint(x: \(x), y: \(y)))"
        case .lineTo(let x, let y):
            return "\(prefix)path.addLine(to: CGPoint(x: \(x), y: \(y)))"
        case .curveTo(let x, let y, let cp1x, let cp1y, let cp2x, let cp2y):
            return "\(prefix)path.addCurve(to: CGPoint(x: \(x), y: \(y)), " +
                   "control1: CGPoint(x: \(cp1x), y: \(cp1y)), " +
                   "control2: CGPoint(x: \(cp2x), y: \(cp2y)))"
        case .quadCurveTo(let x, let y, let cpx, let cpy):
            return "\(prefix)path.addQuadCurve(to: CGPoint(x: \(x), y: \(y)), " +
                   "control: CGPoint(x: \(cpx), y: \(cpy)))"
        case .arc(let cx, let cy, let r, let start, let end, let cw):
            return "\(prefix)path.addArc(center: CGPoint(x: \(cx), y: \(cy)), " +
                   "radius: \(r), startAngle: .radians(\(start)), " +
                   "endAngle: .radians(\(end)), clockwise: \(cw))"
        case .addRect(let x, let y, let w, let h):
            return "\(prefix)path.addRect(CGRect(x: \(x), y: \(y), width: \(w), height: \(h)))"
        case .addEllipse(let x, let y, let w, let h):
            return "\(prefix)path.addEllipse(in: CGRect(x: \(x), y: \(y), width: \(w), height: \(h)))"
        case .closePath:
            return "\(prefix)path.closeSubpath()"
        default:
            return nil
        }
    }

    private static func canvasPathCode(for command: DrawingCommand, pathVar: String, indent: Int) -> String? {
        let prefix = String(repeating: "    ", count: indent)
        switch command {
        case .moveTo(let x, let y):
            return "\(prefix)\(pathVar).move(to: CGPoint(x: \(x), y: \(y)))"
        case .lineTo(let x, let y):
            return "\(prefix)\(pathVar).addLine(to: CGPoint(x: \(x), y: \(y)))"
        case .curveTo(let x, let y, let cp1x, let cp1y, let cp2x, let cp2y):
            return "\(prefix)\(pathVar).addCurve(to: CGPoint(x: \(x), y: \(y)), " +
                   "control1: CGPoint(x: \(cp1x), y: \(cp1y)), " +
                   "control2: CGPoint(x: \(cp2x), y: \(cp2y)))"
        case .quadCurveTo(let x, let y, let cpx, let cpy):
            return "\(prefix)\(pathVar).addQuadCurve(to: CGPoint(x: \(x), y: \(y)), " +
                   "control: CGPoint(x: \(cpx), y: \(cpy)))"
        case .arc(let cx, let cy, let r, let start, let end, let cw):
            return "\(prefix)\(pathVar).addArc(center: CGPoint(x: \(cx), y: \(cy)), " +
                   "radius: \(r), startAngle: .radians(\(start)), " +
                   "endAngle: .radians(\(end)), clockwise: \(cw))"
        case .addRect(let x, let y, let w, let h):
            return "\(prefix)\(pathVar).addRect(CGRect(x: \(x), y: \(y), width: \(w), height: \(h)))"
        case .addEllipse(let x, let y, let w, let h):
            return "\(prefix)\(pathVar).addEllipse(in: CGRect(x: \(x), y: \(y), width: \(w), height: \(h)))"
        case .closePath:
            return "\(prefix)\(pathVar).closeSubpath()"
        default:
            return nil
        }
    }

    private static func canvasTransformCode(for command: DrawingCommand, indent: Int) -> String? {
        let prefix = String(repeating: "    ", count: indent)
        switch command {
        case .translateBy(let x, let y):
            return "\(prefix)context.translateBy(x: \(x), y: \(y))"
        case .scaleBy(let x, let y):
            return "\(prefix)// context.scaleBy — use context.concatenate(CGAffineTransform(scaleX: \(x), y: \(y)))"
        case .rotateBy(let angle):
            return "\(prefix)// context.rotate(by: \(angle)) — use context.concatenate(CGAffineTransform(rotationAngle: \(angle)))"
        default:
            return nil
        }
    }

    // MARK: - Preview generation

    private static func generatePreview(for model: DrawingModel) -> [String] {
        let previewContent = model.isSimpleShape
            ? "\(model.className)().fill(Color.primary).frame(width: 100, height: 100)"
            : "\(model.className)View()"

        return [
            "#Preview {",
            "    \(previewContent)",
            "}",
        ]
    }

    // MARK: - Color mapping

    /// Maps common UIKit color expressions to SwiftUI Color expressions.
    public static func mapColor(_ uiColorExpression: String) -> String {
        let expr = uiColorExpression
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "UIColor.", with: "Color.")
        // Common system color mappings
        let mappings: [String: String] = [
            "Color.systemRed": "Color.red",
            "Color.systemBlue": "Color.blue",
            "Color.systemGreen": "Color.green",
            "Color.systemOrange": "Color.orange",
            "Color.systemYellow": "Color.yellow",
            "Color.systemPurple": "Color.purple",
            "Color.systemGray": "Color.gray",
            "Color.darkGray": "Color.gray",
            "Color.lightGray": "Color(white: 0.8)",
            "Color.black": "Color.black",
            "Color.white": "Color.white",
            "Color.clear": "Color.clear",
        ]
                return mappings[expr] ?? expr
    }

    // MARK: - String constants

    private enum Strings {
        static let empty = ""
        static let newline = "\n"
        static let importSwiftUI = "import SwiftUI"
        static let primaryColor = "Color.primary"
    }
}
