//
//  SidebarGlass.swift
//  Colony
//
//  The sidebar's frosted glass. On the Mac it's the real window-backdrop material
//  (the desktop and windows behind blur through, like Finder and Notes). On iPad and
//  iPhone, where nothing sits behind the app, a soft wash of colour is frosted under
//  a thin material so the panel still reads as glass. Vision Pro windows are glass
//  already. Reduce Transparency swaps all of it for the opaque sidebar colour.
//

import SwiftUI

extension Theme {
    /// Row selection on glass: a translucent tint so the blur shows through.
    static let glassSelection = Color.primary.opacity(0.085)
    static let glassHover = Color.primary.opacity(0.045)
    /// Hairlines on glass.
    static let glassStroke = Color.primary.opacity(0.08)
}

struct SidebarGlassBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Theme.sidebar
        } else {
            #if os(macOS)
            WindowBackdropMaterial()
            #elseif os(visionOS)
            Color.clear
            #else
            ZStack {
                Theme.sidebar
                FrostWash()
                Rectangle().fill(.ultraThinMaterial)
            }
            #endif
        }
    }
}

/// Soft colour fields under the material, so frosted glass has something to frost.
private struct FrostWash: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Circle().fill(ColonyColor.teal.color.opacity(0.35)).frame(width: w * 1.3).offset(x: -w * 0.35, y: -h * 0.32)
                Circle().fill(ColonyColor.blue.color.opacity(0.25)).frame(width: w * 1.1).offset(x: w * 0.4, y: h * 0.05)
                Circle().fill(ColonyColor.purple.color.opacity(0.2)).frame(width: w * 1.2).offset(x: -w * 0.2, y: h * 0.38)
            }
            .frame(width: w, height: h)
            .blur(radius: 60)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if os(macOS)
import AppKit

/// `NSVisualEffectView` blending with whatever is behind the window.
private struct WindowBackdropMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
#endif
