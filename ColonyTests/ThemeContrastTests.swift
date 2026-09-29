//
//  ThemeContrastTests.swift
//  ColonyTests
//
//  Locks in the text contrast claims made in the accessibility statement
//  (docs/accessibility.md): WCAG 2.1 AA, 4.5:1 for normal text and 3:1 for component edges.
//

import Foundation
import Testing
@testable import Colony

struct ThemeContrastTests {
    private enum Mode: CaseIterable { case light, dark, highLight, highDark }

    private func hex(_ tone: Theme.Tone, _ mode: Mode) -> UInt32 {
        switch mode {
        case .light: tone.light
        case .dark: tone.dark
        case .highLight: tone.highLight
        case .highDark: tone.highDark
        }
    }

    private func luminance(_ hex: UInt32) -> Double {
        func channel(_ v: UInt32) -> Double {
            let c = Double(v & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(hex >> 16) + 0.7152 * channel(hex >> 8) + 0.0722 * channel(hex)
    }

    private func ratio(_ a: Theme.Tone, on b: Theme.Tone, _ mode: Mode) -> Double {
        let (x, y) = (luminance(hex(a, mode)), luminance(hex(b, mode)))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private let surfaces: [(String, Theme.Tone)] = [
        ("canvas", Theme.Tones.canvas), ("sidebar", Theme.Tones.sidebar),
        ("surface", Theme.Tones.surface), ("raised", Theme.Tones.raised),
    ]

    @Test func primaryAndSecondaryTextMeetAAEverywhere() {
        for mode in Mode.allCases {
            for (name, bg) in surfaces {
                #expect(ratio(Theme.Tones.text, on: bg, mode) >= 4.5, "text on \(name) in \(mode)")
                #expect(ratio(Theme.Tones.secondaryText, on: bg, mode) >= 4.5, "secondaryText on \(name) in \(mode)")
            }
        }
    }

    @Test func increaseContrastRaisesTertiaryTextToAA() {
        for mode in [Mode.highLight, .highDark] {
            for (name, bg) in surfaces {
                #expect(ratio(Theme.Tones.tertiaryText, on: bg, mode) >= 4.5, "tertiaryText on \(name) in \(mode)")
            }
        }
    }

    @Test func increaseContrastMakesEdgesVisible() {
        for mode in [Mode.highLight, .highDark] {
            for (name, bg) in surfaces {
                #expect(ratio(Theme.Tones.strongStroke, on: bg, mode) >= 3, "strongStroke on \(name) in \(mode)")
            }
        }
    }
}
