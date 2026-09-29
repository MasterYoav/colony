//
//  PlatformCompat.swift
//  Colony
//
//  Swift Pieces are authored for iOS. Colony also ships on macOS, so this file
//  maps the handful of UIKit spellings the pieces use onto AppKit. On iOS and
//  visionOS it compiles to nothing.
//

import SwiftUI

#if os(macOS)
import AppKit

public typealias UIColor = NSColor
public typealias UITextContentType = NSTextContentType

public nonisolated struct PieceTraits: Sendable {
    public enum Style: Sendable { case light, dark, unspecified }
    public enum Contrast: Sendable { case normal, high, unspecified }
    public let userInterfaceStyle: Style
    public var accessibilityContrast: Contrast = .normal
}

extension NSColor {
    /// Mirrors `UIColor { traits in ... }` using an appearance-aware dynamic NSColor.
    /// "Increase contrast" arrives as the high-contrast Aqua appearances.
    nonisolated convenience init(_ provider: @escaping @Sendable (PieceTraits) -> NSColor) {
        self.init(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua])
            let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            let isHigh = match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
            return provider(PieceTraits(userInterfaceStyle: isDark ? .dark : .light, accessibilityContrast: isHigh ? .high : .normal))
        }
    }
}

extension Color {
    nonisolated init(uiColor: NSColor) {
        self.init(nsColor: uiColor)
    }
}

public enum UIKeyboardType: Sendable {
    case `default`, asciiCapable, numbersAndPunctuation, URL, numberPad, phonePad, namePhonePad, emailAddress, decimalPad, twitter, webSearch
}

public enum PieceAutocapitalization: Sendable {
    case never, words, sentences, characters
}

enum UIApplication {
    static let openSettingsURLString = "x-apple.systempreferences:"
}

extension View {
    func keyboardType(_ type: UIKeyboardType) -> some View { self }
    func textInputAutocapitalization(_ style: PieceAutocapitalization?) -> some View { self }
}
#endif

#if os(macOS)
extension NSColor {
    static var secondarySystemBackground: NSColor { .controlBackgroundColor }
    static var systemBackground: NSColor { .windowBackgroundColor }
}
#endif
