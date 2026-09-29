//
//  AppFont.swift
//  Colony
//
//  Two user-chosen typefaces, picked in Settings › Appearance from the fonts installed
//  on the device:
//
//  • UI:   everything that belongs to the app — sidebar, headers, buttons, labels.
//  • Data: the user's content — task titles and notes, messages, contacts, deals, numbers.
//
//  Views write `.appFont(.system(size: 13, weight: .medium))` or `.appFont(.headline)`
//  exactly like `.font(...)`. The modifier resolves the font from the environment: the
//  role (`.fontRole(.data)` on content regions, UI otherwise) picks the family, and
//  "System" keeps Apple's system font. Monospaced/rounded/serif designs stay system
//  fonts on purpose (key hints, tabular numbers).
//
//  The choice roams through iCloud, but fonts are local: a family that isn't installed
//  on this device falls back to the system font.
//
//  Larger Text: text styles follow Dynamic Type natively, and fixed sizes
//  (`.system(size: 13)`) are scaled here by the same ratio, so every label in the app grows
//  with the user's text size setting. App chrome (the UI role) stops growing at
//  accessibility size 2 so the sidebar and toolbars stay usable; content (the Data role)
//  scales all the way. Where the platform has no Dynamic Type (macOS) nothing changes.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public enum FontRole: String, Sendable {
    case ui, data
}

/// A font description that can be rendered in the system font or in a chosen family.
public struct AppFont: Sendable {
    fileprivate enum Base: Sendable {
        case style(Font.TextStyle)
        case size(CGFloat)
    }

    fileprivate var base: Base
    fileprivate var weight: Font.Weight?
    fileprivate var design: Font.Design?
    fileprivate var monospacedDigits = false

    // MARK: Constructors mirroring `Font`

    public static func system(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> AppFont {
        AppFont(base: .size(size), weight: weight, design: design)
    }

    public static func system(_ style: Font.TextStyle, design: Font.Design? = nil, weight: Font.Weight? = nil) -> AppFont {
        AppFont(base: .style(style), weight: weight, design: design)
    }

    public static let largeTitle = AppFont(base: .style(.largeTitle))
    public static let title = AppFont(base: .style(.title))
    public static let title2 = AppFont(base: .style(.title2))
    public static let title3 = AppFont(base: .style(.title3))
    public static let headline = AppFont(base: .style(.headline))
    public static let subheadline = AppFont(base: .style(.subheadline))
    public static let body = AppFont(base: .style(.body))
    public static let callout = AppFont(base: .style(.callout))
    public static let footnote = AppFont(base: .style(.footnote))
    public static let caption = AppFont(base: .style(.caption))
    public static let caption2 = AppFont(base: .style(.caption2))

    public func weight(_ weight: Font.Weight) -> AppFont {
        var copy = self
        copy.weight = weight
        return copy
    }

    public func monospacedDigit() -> AppFont {
        var copy = self
        copy.monospacedDigits = true
        return copy
    }

    // MARK: Resolution

    /// The SwiftUI font for this description, in `family` when one is given. Fixed sizes
    /// are multiplied by `scale` (the Dynamic Type ratio); text styles scale by themselves.
    public func resolved(family: String?, scale: CGFloat = 1) -> Font {
        let keepsSystem = design != nil && design != .default
        var font: Font
        if let family, !keepsSystem {
            switch base {
            case .style(let style):
                font = .custom(family, size: Self.pointSize(for: style), relativeTo: style)
                if let implied = Self.impliedWeight(for: style), weight == nil { font = font.weight(implied) }
            case .size(let size):
                font = .custom(family, fixedSize: (size * scale).rounded())
            }
            if let weight { font = font.weight(weight) }
        } else {
            switch base {
            case .style(let style):
                font = .system(style, design: design ?? .default)
                if let weight { font = font.weight(weight) }
            case .size(let size):
                font = .system(size: (size * scale).rounded(), weight: weight ?? .regular, design: design ?? .default)
            }
        }
        if monospacedDigits { font = font.monospacedDigit() }
        return font
    }

    /// Point sizes of the text styles at the default Dynamic Type size.
    private static func pointSize(for style: Font.TextStyle) -> CGFloat {
        #if os(macOS)
        switch style {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote, .caption, .caption2: 10
        @unknown default: 13
        }
        #else
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
        #endif
    }

    /// Styles that are bold by definition keep that weight in a custom family.
    private static func impliedWeight(for style: Font.TextStyle) -> Font.Weight? {
        style == .headline ? .semibold : nil
    }
}

// MARK: - Installed families

public enum InstalledFonts {
    /// Every font family installed on this device, sorted for display.
    @MainActor public static let families: [String] = {
        #if canImport(AppKit)
        let names = NSFontManager.shared.availableFontFamilies
        #elseif canImport(UIKit)
        let names = UIFont.familyNames
        #endif
        return names
            .filter { !$0.hasPrefix(".") } // private system families
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }()

    @MainActor private static let lookup = Set(families)

    /// `family` when it's installed here, otherwise nil (the system font).
    @MainActor public static func available(_ family: String) -> String? {
        guard !family.isEmpty, lookup.contains(family) else { return nil }
        return family
    }
}

// MARK: - Environment

/// The families currently in effect; nil means the system font.
public struct AppTypefaces: Equatable, Sendable {
    public var ui: String?
    public var data: String?

    public init(ui: String? = nil, data: String? = nil) {
        self.ui = ui
        self.data = data
    }

    public func family(for role: FontRole) -> String? {
        role == .data ? data : ui
    }
}

public extension EnvironmentValues {
    @Entry var appTypefaces = AppTypefaces()
    @Entry var fontRole: FontRole = .ui
}

public extension View {
    /// Like `.font(_:)`, but in the family the user picked for the current role.
    func appFont(_ font: AppFont) -> some View {
        modifier(AppFontModifier(font: font, role: nil))
    }

    /// Forces a role for this one view, regardless of its surroundings.
    func appFont(_ font: AppFont, role: FontRole) -> some View {
        modifier(AppFontModifier(font: font, role: role))
    }

    /// Marks a region as the user's content (Data font) or app chrome (UI font).
    func fontRole(_ role: FontRole) -> some View {
        environment(\.fontRole, role)
            // Re-resolve the inherited default font for the new role, so plain `Text`
            // without an explicit font follows the region too.
            .modifier(AppFontModifier(font: .body, role: role))
    }
}

private struct AppFontModifier: ViewModifier {
    let font: AppFont
    let role: FontRole?
    @Environment(\.appTypefaces) private var typefaces
    @Environment(\.fontRole) private var inheritedRole
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        let role = role ?? inheritedRole
        let size = role == .ui ? min(typeSize, .accessibility2) : typeSize
        content.font(font.resolved(family: typefaces.family(for: role), scale: TextScale.factor(for: size)))
    }
}

/// Ratio of body text at each Dynamic Type size to body at the default (Large) size,
/// from Apple's type ramp (17pt body on iOS).
public enum TextScale {
    public static func factor(for size: DynamicTypeSize) -> CGFloat {
        #if os(macOS)
        return 1
        #else
        let body: CGFloat = switch size {
        case .xSmall: 14
        case .small: 15
        case .medium: 16
        case .large: 17
        case .xLarge: 19
        case .xxLarge: 21
        case .xxxLarge: 23
        case .accessibility1: 28
        case .accessibility2: 33
        case .accessibility3: 40
        case .accessibility4: 47
        case .accessibility5: 53
        @unknown default: 17
        }
        return body / 17
        #endif
    }
}
