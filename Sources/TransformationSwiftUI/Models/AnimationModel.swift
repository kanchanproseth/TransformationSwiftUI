// SPDX-License-Identifier: MIT
//
// AnimationModel.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Model types for UIKit animation data detected in Swift source files.
//

import Foundation

// MARK: - AnimationTimingCurve

/// The timing curve detected from a UIKit animation call.
public enum AnimationTimingCurve {
    /// Ease in and out — the default UIKit curve.
    case easeInOut
    /// Ease in only.
    case easeIn
    /// Ease out only.
    case easeOut
    /// Constant velocity.
    case linear
    /// Spring-based animation with damping and response parameters.
    case spring(dampingFraction: Double, response: Double)
    /// A curve that could not be statically resolved (e.g., a variable).
    case custom
}

// MARK: - AnimatedTransform

/// The transform sub-type detected inside an animation block.
public enum AnimatedTransform {
    /// Scale transform (`CGAffineTransform(scaleX:y:)`).
    case scale(x: Double, y: Double)
    /// Rotation transform — angle in radians.
    case rotation(Double)
    /// Translation transform.
    case translation(x: Double, y: Double)
    /// Identity transform (reset).
    case identity
}

// MARK: - AnimatedPropertyChange

/// A property change detected inside a UIKit animation closure.
public enum AnimatedPropertyChange {
    /// `view.alpha = value`
    case alpha(Double)
    /// `view.transform = CGAffineTransform(...)`
    case transform(AnimatedTransform)
    /// `view.backgroundColor = UIColor.xxx`
    case backgroundColor(String)
    /// `view.isHidden = value`
    case isHidden(Bool)
    /// `view.frame = ...` (generic frame change)
    case frame
}

// MARK: - AnimationContext

/// The UIViewController lifecycle method or action context where the animation was found.
public enum AnimationContext {
    /// Found inside `viewDidAppear(_:)`.
    case viewDidAppear
    /// Found inside `viewWillAppear(_:)`.
    case viewWillAppear
    /// Found inside `viewDidLoad()`.
    case viewDidLoad
    /// Found inside a named `@objc` action method.
    case actionMethod(String)
    /// Found inside some other named method.
    case other(String)
}

// MARK: - AnimationKind

/// The UIKit animation API variant that was detected.
public enum AnimationKind {
    /// `UIView.animate(withDuration:animations:)` and its overloads.
    case uiViewAnimate
    /// `UIView.animate(withDuration:delay:usingSpringWithDamping:...)`.
    case uiViewSpringAnimate
    /// `UIView.transition(with:duration:options:animations:completion:)`.
    case uiViewTransition
    /// `UIViewPropertyAnimator(duration:curve:animations:)`.
    case propertyAnimator
    /// `CABasicAnimation(keyPath:)` with the detected key path string.
    case caBasicAnimation(String)
    /// `CAKeyframeAnimation(keyPath:)` with the detected key path string.
    case caKeyframeAnimation(String)
    /// `CASpringAnimation()` for spring-based layer animations.
    case caSpringAnimation(String)
    /// `CAAnimationGroup()` grouping multiple layer animations.
    case caAnimationGroup
}

// MARK: - AnimationModel

/// A single UIKit animation detected in Swift source code.
public struct AnimationModel {
    /// The animation API variant.
    public let kind: AnimationKind

    /// Animation duration in seconds, when statically resolvable.
    public let duration: Double?

    /// Animation delay in seconds, when statically resolvable.
    public let delay: Double?

    /// The timing curve for this animation.
    public let timingCurve: AnimationTimingCurve

    /// The lifecycle/action context where this animation was found.
    public let context: AnimationContext

    /// The name of the view element being animated (variable name with `self.` stripped),
    /// when determinable from the animation closure.
    public let targetElementName: String?

    /// The property changes detected inside the animation closure.
    public let propertyChanges: [AnimatedPropertyChange]

    /// Whether a `completion:` closure was provided.
    public let hasCompletion: Bool

    public init(
        kind: AnimationKind,
        duration: Double?,
        delay: Double?,
        timingCurve: AnimationTimingCurve,
        context: AnimationContext,
        targetElementName: String?,
        propertyChanges: [AnimatedPropertyChange],
        hasCompletion: Bool
    ) {
        self.kind = kind
        self.duration = duration
        self.delay = delay
        self.timingCurve = timingCurve
        self.context = context
        self.targetElementName = targetElementName
        self.propertyChanges = propertyChanges
        self.hasCompletion = hasCompletion
    }
}
