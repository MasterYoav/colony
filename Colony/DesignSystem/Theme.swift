//
//  Theme.swift
//  Colony
//
//  Design tokens taken from the reference sidebar: near-black surfaces, hairline
//  strokes, soft grey selection pills and quiet secondary text. Every token adapts
//  so the light appearance keeps the same hierarchy.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum Theme {
    // Surfaces
    static let canvas = color(Tones.canvas)
    static let sidebar = color(Tones.sidebar)
    static let rail = adaptive(light: 0xF3F3F5, dark: 0x0F1012)
    static let surface = color(Tones.surface)
    static let raised = color(Tones.raised)
    static let selection = adaptive(light: 0xE9E9EC, dark: 0x1F2024)
    static let hover = adaptive(light: 0xF0F0F2, dark: 0x18191C)
    static let field = adaptive(light: 0xFFFFFF, dark: 0x131417)

    // Lines. With Increase Contrast they become clearly visible edges.
    static let stroke = color(Tones.stroke)
    static let strongStroke = color(Tones.strongStroke)

    // Text. Primary and secondary meet WCAG AA (4.5:1) on every surface. Tertiary is for
    // incidental text (timestamps, shortcut hints, placeholders); with Increase Contrast
    // it's raised to AA as well. ThemeContrastTests checks these ratios.
    static let text = color(Tones.text)
    static let secondaryText = color(Tones.secondaryText)
    static let tertiaryText = color(Tones.tertiaryText)
    static let icon = color(Tones.icon)

    /// Raw hex values, per appearance, for tokens that change under Increase Contrast.
    struct Tone: Sendable {
        let light: UInt32, dark: UInt32, highLight: UInt32, highDark: UInt32
    }

    enum Tones {
        static let canvas = Tone(light: 0xF6F6F7, dark: 0x0B0B0D, highLight: 0xF6F6F7, highDark: 0x0B0B0D)
        static let sidebar = Tone(light: 0xFBFBFC, dark: 0x0F1012, highLight: 0xFBFBFC, highDark: 0x0F1012)
        static let surface = Tone(light: 0xFFFFFF, dark: 0x15161A, highLight: 0xFFFFFF, highDark: 0x15161A)
        static let raised = Tone(light: 0xFFFFFF, dark: 0x1B1C20, highLight: 0xFFFFFF, highDark: 0x1B1C20)

        static let stroke = Tone(light: 0xE4E4E7, dark: 0x222327, highLight: 0x8A8C92, highDark: 0x6A6C72)
        static let strongStroke = Tone(light: 0xD4D4D8, dark: 0x2C2D32, highLight: 0x6B6D74, highDark: 0x8E9096)
        static let text = Tone(light: 0x17181B, dark: 0xECECEE, highLight: 0x000000, highDark: 0xFFFFFF)
        static let secondaryText = Tone(light: 0x6B6D74, dark: 0x8E9096, highLight: 0x3F4146, highDark: 0xC4C5CA)
        static let tertiaryText = Tone(light: 0x9A9CA2, dark: 0x5F6167, highLight: 0x5E6066, highDark: 0x9B9DA3)
        static let icon = Tone(light: 0x4A4C52, dark: 0xB7B8BD, highLight: 0x2A2B2F, highDark: 0xDADBDF)
    }

    static func color(_ tone: Tone) -> Color {
        adaptive(light: tone.light, dark: tone.dark, highLight: tone.highLight, highDark: tone.highDark)
    }

    // Brand
    static let brandGradient = LinearGradient(
        colors: [Color(red: 0.98, green: 0.45, blue: 0.35), Color(red: 0.78, green: 0.36, blue: 0.95), Color(red: 0.36, green: 0.55, blue: 0.98)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let avatarGradient = LinearGradient(
        colors: [Color(red: 0.99, green: 0.33, blue: 0.62), Color(red: 0.49, green: 0.32, blue: 0.98)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Metrics
    static let panelWidth: CGFloat = 232

    /// The expanded sidebar widens with larger text (up to 1.4×) so labels keep fitting.
    static func panelWidth(for size: DynamicTypeSize) -> CGFloat {
        (panelWidth * min(TextScale.factor(for: min(size, .accessibility2)), 1.4)).rounded()
    }
    /// Sidebar open/close: a smooth, non-bouncy width change.
    static let sidebarAnimation: Animation = .smooth(duration: 0.32)
    #if os(macOS)
    /// Traffic lights span x 8…70 (close at 8, zoom 54 + 16), so a 78pt column puts
    /// them exactly in the middle: 8pt on each side.
    static let collapsedPanelWidth: CGFloat = 78
    #else
    static let collapsedPanelWidth: CGFloat = 52
    #endif
    static let rowHeight: CGFloat = 30
    static let rowRadius: CGFloat = 8

    /// macOS: the live window appearance carries Increase Contrast, but reading the setting
    /// directly is what makes it reliable in every drawing context.
    nonisolated static var systemIncreasesContrast: Bool {
        #if os(macOS)
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        #else
        false
        #endif
    }

    static func adaptive(light: UInt32, dark: UInt32, highLight: UInt32? = nil, highDark: UInt32? = nil) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let isHigh = traits.accessibilityContrast == .high || Theme.systemIncreasesContrast
            let hex = isHigh ? (isDark ? highDark ?? dark : highLight ?? light) : (isDark ? dark : light)
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

/// Small rounded tile with a symbol, used for projects in the sidebar and throughout the app.
struct ProjectGlyph: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 18

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .appFont(.system(size: size * 0.52, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
            }
    }
}

struct AvatarView: View {
    let name: String
    let color: Color
    var imageData: Data? = nil
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let imageData, let image = Image(data: imageData) {
                image.resizable().scaledToFill()
            } else {
                Circle()
                    .fill(color.gradient)
                    .overlay {
                        Text(ColonyText.initials(for: name))
                            .appFont(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

extension Image {
    init?(data: Data) {
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        self.init(nsImage: image)
        #else
        guard let image = UIImage(data: data) else { return nil }
        self.init(uiImage: image)
        #endif
    }
}

/// Section title used in detail screens.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .appFont(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle)
                        .appFont(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Bordered card container matching the sidebar's hairline style.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.stroke)
            }
    }
}

/// Quiet bordered button used for secondary actions.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(.subheadline.weight(.medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(configuration.isPressed ? Theme.selection : Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.stroke)
            }
            .contentShape(.rect)
    }
}

/// Empty state used across lists.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .appFont(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.tertiaryText)
            Text(title)
                .appFont(.headline)
                .foregroundStyle(Theme.text)
            Text(message)
                .appFont(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(QuietButtonStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
