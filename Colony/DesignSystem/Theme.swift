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
#endif

enum Theme {
    // Surfaces
    static let canvas = adaptive(light: 0xF6F6F7, dark: 0x0B0B0D)
    static let sidebar = adaptive(light: 0xFBFBFC, dark: 0x0F1012)
    static let rail = adaptive(light: 0xF3F3F5, dark: 0x0F1012)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x15161A)
    static let raised = adaptive(light: 0xFFFFFF, dark: 0x1B1C20)
    static let selection = adaptive(light: 0xE9E9EC, dark: 0x1F2024)
    static let hover = adaptive(light: 0xF0F0F2, dark: 0x18191C)
    static let field = adaptive(light: 0xFFFFFF, dark: 0x131417)

    // Lines
    static let stroke = adaptive(light: 0xE4E4E7, dark: 0x222327)
    static let strongStroke = adaptive(light: 0xD4D4D8, dark: 0x2C2D32)

    // Text
    static let text = adaptive(light: 0x17181B, dark: 0xECECEE)
    static let secondaryText = adaptive(light: 0x6B6D74, dark: 0x8E9096)
    static let tertiaryText = adaptive(light: 0x9A9CA2, dark: 0x5F6167)
    static let icon = adaptive(light: 0x4A4C52, dark: 0xB7B8BD)

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
    static let railWidth: CGFloat = 52
    static let panelWidth: CGFloat = 232
    static let collapsedPanelWidth: CGFloat = 52
    static let rowHeight: CGFloat = 30
    static let rowRadius: CGFloat = 8

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
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
                    .font(.system(size: size * 0.52, weight: .bold))
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
                            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
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
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
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
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .frame(height: 30)
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
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.tertiaryText)
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text(message)
                .font(.subheadline)
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
