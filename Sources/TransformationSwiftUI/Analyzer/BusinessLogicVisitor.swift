// SPDX-License-Identifier: MIT
//
// BusinessLogicVisitor.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: SwiftSyntax visitor that extracts business logic patterns per UI control —
//              IBActions, target-action pairs, delegate callbacks, tableView/collectionView
//              didSelectRowAt / didSelectItemAt, and programmatic navigation calls.
//

import SwiftSyntax

// MARK: - ControlAction

/// Represents a single business-logic action tied to a UI control.
public struct ControlAction {
    /// The control variable name this action is associated with.
    public let controlName: String
    /// The kind of action detected.
    public let kind: ControlActionKind
    /// The name of the handler function.
    public let handlerName: String
    /// A brief description of what the action does (inferred from function body analysis).
    public let behaviorSummary: String

    public init(controlName: String, kind: ControlActionKind, handlerName: String, behaviorSummary: String) {
        self.controlName = controlName
        self.kind = kind
        self.handlerName = handlerName
        self.behaviorSummary = behaviorSummary
    }
}

// MARK: - ControlActionKind

/// Categories of UIKit action patterns.
public enum ControlActionKind: String {
    /// `@IBAction func foo(_:)` wired in IB.
    case ibAction
    /// `button.addTarget(self, action: #selector(foo), for: .touchUpInside)`.
    case targetAction
    /// `tableView(_:didSelectRowAt:)` delegate callback.
    case tableViewDidSelect
    /// `collectionView(_:didSelectItemAt:)` delegate callback.
    case collectionViewDidSelect
    /// `prepare(for segue:)` — programmatic navigation prep.
    case prepareForSegue
    /// `performSegue(withIdentifier:sender:)` call.
    case performSegue
    /// `present(_:animated:)` call.
    case presentViewController
    /// `navigationController?.pushViewController` call.
    case pushViewController
    /// `dismiss(animated:)` call.
    case dismissViewController
    /// Any other recognisable delegate callback pattern.
    case delegateCallback
}

// MARK: - NavigationCall

/// A programmatic navigation call found in source — push, present, dismiss, etc.
public struct NavigationCall {
    /// The source function containing this call.
    public let sourceFunction: String
    /// The destination VC class name, when resolvable (e.g. `MyDetailViewController`).
    public let destinationVC: String?
    /// The kind of navigation performed.
    public let kind: ControlActionKind
    /// The segue identifier for performSegue calls.
    public let segueIdentifier: String?

    public init(sourceFunction: String, destinationVC: String?, kind: ControlActionKind, segueIdentifier: String?) {
        self.sourceFunction = sourceFunction
        self.destinationVC = destinationVC
        self.kind = kind
        self.segueIdentifier = segueIdentifier
    }
}

// MARK: - BusinessLogicVisitor

/// Walks a UIViewController class declaration and extracts:
///  - `@IBAction` functions and the likely control they serve
///  - `addTarget` target-action wiring per control variable
///  - `tableView(_:didSelectRowAt:)` and `collectionView(_:didSelectItemAt:)` delegate methods
///  - `prepare(for segue:)`, `performSegue`, `present`, `pushViewController`, `dismiss` calls
public class BusinessLogicVisitor: SyntaxVisitor {

    /// Detected control action bindings.
    public private(set) var controlActions: [ControlAction] = []
    /// Detected programmatic navigation calls.
    public private(set) var navigationCalls: [NavigationCall] = []

    private var currentFunction: String = "unknown"
    private var currentFunctionBody: String = ""

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Function tracking

    override public func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        currentFunction = node.name.text
        currentFunctionBody = node.body?.description ?? ""

        // Detect @IBAction
        let hasIBAction = node.attributes.contains { attr in
            attr.description.contains("IBAction")
        }
        if hasIBAction {
            let summary = inferBehaviorSummary(from: currentFunctionBody)
            controlActions.append(ControlAction(
                controlName: inferControlName(from: node),
                kind: .ibAction,
                handlerName: currentFunction,
                behaviorSummary: summary
            ))
        }

        // Detect UITableViewDelegate methods
        let funcName = node.name.text
        if funcName == "tableView" {
            let params = node.signature.parameterClause.parameters.map { $0.firstName.text }
            if params.contains("didSelectRowAt") {
                let summary = inferBehaviorSummary(from: currentFunctionBody)
                controlActions.append(ControlAction(
                    controlName: "tableView",
                    kind: .tableViewDidSelect,
                    handlerName: funcName,
                    behaviorSummary: summary
                ))
            }
        }

        // Detect UICollectionViewDelegate methods
        if funcName == "collectionView" {
            let params = node.signature.parameterClause.parameters.map { $0.firstName.text }
            if params.contains("didSelectItemAt") {
                let summary = inferBehaviorSummary(from: currentFunctionBody)
                controlActions.append(ControlAction(
                    controlName: "collectionView",
                    kind: .collectionViewDidSelect,
                    handlerName: funcName,
                    behaviorSummary: summary
                ))
            }
        }

        // Detect prepare(for segue:)
        if funcName == "prepare" {
            let params = node.signature.parameterClause.parameters.map { $0.firstName.text }
            if params.contains("for") {
                let summary = inferBehaviorSummary(from: currentFunctionBody)
                controlActions.append(ControlAction(
                    controlName: "segue",
                    kind: .prepareForSegue,
                    handlerName: funcName,
                    behaviorSummary: summary
                ))
            }
        }

        return .visitChildren
    }

    override public func visitPost(_ node: FunctionDeclSyntax) {
        currentFunction = "unknown"
        currentFunctionBody = ""
    }

    // MARK: - Call expression detection

    override public func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            return .visitChildren
        }
        let methodName = member.declName.baseName.text
        let base = member.base?.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch methodName {

        case "addTarget":
            // button.addTarget(self, action: #selector(foo), for: .touchUpInside)
            let handlerName = extractSelectorName(from: node) ?? "unknown"
            controlActions.append(ControlAction(
                controlName: base,
                kind: .targetAction,
                handlerName: handlerName,
                behaviorSummary: "Target-action on \(base)"
            ))

        case "performSegue":
            let identifier = extractStringArgument(from: node, label: "withIdentifier")
            navigationCalls.append(NavigationCall(
                sourceFunction: currentFunction,
                destinationVC: nil,
                kind: .performSegue,
                segueIdentifier: identifier
            ))

        case "present":
            // self.present(destVC, animated: true)
            let destVCName = extractFirstArgumentName(from: node)
            navigationCalls.append(NavigationCall(
                sourceFunction: currentFunction,
                destinationVC: destVCName,
                kind: .presentViewController,
                segueIdentifier: nil
            ))

        case "pushViewController":
            // navigationController?.pushViewController(destVC, animated: true)
            let destVCName = extractFirstArgumentName(from: node)
            navigationCalls.append(NavigationCall(
                sourceFunction: currentFunction,
                destinationVC: destVCName,
                kind: .pushViewController,
                segueIdentifier: nil
            ))

        case "dismiss":
            navigationCalls.append(NavigationCall(
                sourceFunction: currentFunction,
                destinationVC: nil,
                kind: .dismissViewController,
                segueIdentifier: nil
            ))

        default:
            break
        }

        return .visitChildren
    }

    // MARK: - Helpers

    /// Infers the control variable name from an IBAction function signature.
    /// e.g. `@IBAction func loginButtonTapped(_ sender: UIButton)` → "loginButton"
    private func inferControlName(from node: FunctionDeclSyntax) -> String {
        let funcName = node.name.text
        let suffixes = ["Tapped", "Pressed", "Changed", "Selected", "TouchUpInside", "Action", "Clicked"]
        for suffix in suffixes {
            if funcName.hasSuffix(suffix) {
                let base = String(funcName.dropLast(suffix.count))
                return base.isEmpty ? funcName : base
            }
        }
        return funcName
    }

    /// Extracts the selector name from `#selector(foo)` in an addTarget call.
    private func extractSelectorName(from call: FunctionCallExprSyntax) -> String? {
        for arg in call.arguments {
            let expr = arg.expression.description
            if expr.contains("#selector(") {
                let inner = expr.replacingOccurrences(of: "#selector(", with: "")
                    .replacingOccurrences(of: ")", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return inner
            }
        }
        return nil
    }

    /// Extracts a string literal argument by label from a function call.
    private func extractStringArgument(from call: FunctionCallExprSyntax, label: String) -> String? {
        for arg in call.arguments {
            guard arg.label?.text == label else { continue }
            let expr = arg.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
            // Strip surrounding quotes if present
            if expr.hasPrefix("\"") && expr.hasSuffix("\"") {
                return String(expr.dropFirst().dropLast())
            }
            return expr
        }
        return nil
    }

    /// Extracts the first positional argument as a variable/type name.
    private func extractFirstArgumentName(from call: FunctionCallExprSyntax) -> String? {
        call.arguments.first?.expression.description
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Produces a one-line natural-language summary of a function body.
    private func inferBehaviorSummary(from body: String) -> String {
        var parts: [String] = []
        if body.contains("performSegue") { parts.append("navigates via segue") }
        if body.contains("present(") { parts.append("presents view controller") }
        if body.contains("pushViewController") { parts.append("pushes view controller") }
        if body.contains("dismiss(") { parts.append("dismisses") }
        if body.contains("isHidden") { parts.append("toggles visibility") }
        if body.contains("alpha") { parts.append("adjusts alpha") }
        if body.contains("reload") { parts.append("reloads data") }
        if body.contains("fetch") || body.contains("load") { parts.append("loads data") }
        if body.contains("save") || body.contains("persist") { parts.append("saves data") }
        if body.contains("delete") || body.contains("remove") { parts.append("removes item") }
        if parts.isEmpty { return "handles user interaction" }
        return parts.joined(separator: ", ")
    }
}
