//
//  Motion.swift
//  Colony
//
//  Reduce Motion support. Every animation in the app goes through `withMotion` or
//  `.motion(_:value:)`; with the Reduce Motion accessibility setting on, changes
//  happen instantly instead of sliding, springing or resizing.
//
//  (Swift Pieces components read `accessibilityReduceMotion` themselves.)
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum Motion {
    /// The system Reduce Motion setting, readable outside a view (button actions, models).
    @MainActor static var isReduced: Bool {
        #if canImport(AppKit)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #elseif canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #else
        false
        #endif
    }
}

/// `withAnimation`, except with Reduce Motion on the change is applied without animation.
@MainActor
@discardableResult
func withMotion<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(Motion.isReduced ? nil : animation, body)
}

extension View {
    /// `.animation(_:value:)` that turns itself off with Reduce Motion.
    func motion<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    let animation: Animation?
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
