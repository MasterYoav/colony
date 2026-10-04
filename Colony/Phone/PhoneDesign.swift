//
//  PhoneDesign.swift
//  Colony
//
//  The iPhone design language, modelled on Apple's own apps (Maps, Health, Fitness)
//  and Incredible: true-black canvas in dark mode, big rounded cards, bold section
//  headers with a chevron, circular colour icons, one hero number with a plain
//  sentence under it, metric tiles with a vertical gauge, and Liquid Glass controls.
//

#if os(iOS)
import SwiftUI

enum Phone {
    /// Grouped background: black in dark mode, light grey in light mode.
    static let canvas = Color(uiColor: .systemGroupedBackground)
    /// Cards: #1C1C1E in dark mode, white in light mode.
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    /// A recessed well inside a card (gauge tracks, chips).
    static let well = Color(uiColor: .tertiarySystemGroupedBackground)
    static let separator = Color(uiColor: .separator)
    static let cardRadius: CGFloat = 26
    static let margin: CGFloat = 16

    /// Rounded heavy title, as in Incredible and Fitness.
    static func display(_ size: CGFloat) -> AppFont { .system(size: size, weight: .heavy, design: .rounded) }
    /// Tabular numbers in tiles.
    static func number(_ size: CGFloat) -> AppFont { .system(size: size, weight: .bold, design: .monospaced) }
}

// MARK: - Scroll edge

extension View {
    /// A firm blur under the floating glass header, so content never shows through it.
    func phoneScrollEdge() -> some View {
        scrollEdgeEffectStyle(.soft, for: .all)
    }
}

// MARK: - Card

struct PhoneCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Phone.card, in: RoundedRectangle(cornerRadius: Phone.cardRadius, style: .continuous))
    }
}

/// A card holding rows separated by inset hairlines (Maps "Recents").
struct PhoneRowsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows.indices, id: \.self) { index in
                    rows[index]
                    if index < rows.count - 1 {
                        Rectangle().fill(Phone.separator).frame(height: 0.5).padding(.leading, 70).padding(.trailing, 18)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Phone.card, in: RoundedRectangle(cornerRadius: Phone.cardRadius, style: .continuous))
    }
}

// MARK: - Section header

/// "Places ›": a big bold title that opens the full list.
struct PhoneSectionHeader: View {
    let title: String
    var subtitle: String?
    var action: (() -> Void)?
    var trailing: AnyView?

    init(_ title: String, subtitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }

    init<T: View>(_ title: String, subtitle: String? = nil, action: (() -> Void)? = nil, @ViewBuilder trailing: () -> T) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if let action {
                    Button(action: action) { titleLabel(chevron: true) }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    titleLabel(chevron: false).accessibilityAddTraits(.isHeader)
                }
                if let subtitle {
                    Text(subtitle)
                        .appFont(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }

    private func titleLabel(chevron: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .appFont(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            if chevron {
                Image(systemName: "chevron.right")
                    .appFont(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Icons

/// A gradient circle with a white glyph (Maps "Places", Reminders lists).
struct CircleIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .appFont(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle().fill(LinearGradient(colors: [color.mix(with: .white, by: 0.18), color], startPoint: .top, endPoint: .bottom))
            )
            .accessibilityHidden(true)
    }
}

/// Maps-style row: circle icon, bold title, grey subtitle, trailing accessory.
struct PhoneRow<Accessory: View>: View {
    let icon: AnyView
    let title: String
    var subtitle: String?
    var subtitleColor: Color = .secondary
    var action: (() -> Void)?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        let row = HStack(spacing: 14) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .appFont(.system(size: 15))
                        .foregroundStyle(subtitleColor)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            accessory
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(.rect)

        if let action {
            Button(action: action) { row }.buttonStyle(PhonePressStyle())
        } else {
            row
        }
    }
}

extension PhoneRow where Accessory == EmptyView {
    init(icon: AnyView, title: String, subtitle: String? = nil, subtitleColor: Color = .secondary, action: (() -> Void)? = nil) {
        self.init(icon: icon, title: title, subtitle: subtitle, subtitleColor: subtitleColor, action: action) { EmptyView() }
    }
}

/// The "•••" button at the end of a Maps row.
struct MoreMenu<Items: View>: View {
    var label = "More"
    @ViewBuilder var items: Items

    var body: some View {
        Menu { items } label: {
            Image(systemName: "ellipsis")
                .appFont(.system(size: 17, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .contentShape(.rect)
        }
        .accessibilityLabel(label)
    }
}

/// Dims slightly while pressed, like Apple's list cards.
struct PhonePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.06 : 0))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Gauges

/// Incredible's hero: an open arc with a glowing dot at the progress point.
struct ArcGauge: View {
    /// 0…1
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 34

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height * 1.25)
            let radius = (size - lineWidth) / 2
            let span = 0.64 // fraction of the circle drawn: ends level with the number
            let start = Angle.degrees(90 + 360 * (1 - span) / 2)
            let clamped = min(max(progress, 0), 1)
            let angle = start.radians + 2 * .pi * span * clamped
            let center = CGPoint(x: proxy.size.width / 2, y: size / 2)
            ZStack {
                Circle()
                    .trim(from: 0, to: span)
                    .stroke(Phone.card, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(start)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)
                Circle()
                    .trim(from: 0, to: span * clamped)
                    .stroke(LinearGradient(colors: [color.opacity(0.45), color], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(start)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: lineWidth * 1.3, height: lineWidth * 1.3)
                    .overlay { Circle().fill(color).frame(width: lineWidth * 0.52, height: lineWidth * 0.52) }
                    .position(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The vertical bar on the right of a metric tile.
struct VerticalGauge: View {
    /// 0…1
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let inner = proxy.size.height - 12
            ZStack(alignment: .bottom) {
                Capsule().fill(Phone.well)
                Capsule()
                    .fill(color.gradient)
                    .frame(width: 14, height: value <= 0 ? 0 : max(inner * 0.18, inner * min(value, 1)))
                    .opacity(value <= 0 ? 0 : 1)
                    .padding(.bottom, 6)
            }
        }
        .frame(width: 26)
        .accessibilityHidden(true)
    }
}

/// Incredible's metric tile: label, icon, big number, chip and a vertical gauge.
struct MetricTile: View {
    let title: String
    let symbol: String
    let value: String
    var unit: String?
    var chip: String?
    var chipSymbol: String?
    let gauge: Double
    let color: Color
    var action: (() -> Void)?

    var body: some View {
        Button { action?() } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .appFont(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                    Image(systemName: symbol)
                        .appFont(.system(size: 22, weight: .semibold))
                        .foregroundStyle(color)
                        .padding(.top, 14)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(value)
                            .appFont(Phone.number(30))
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        if let unit {
                            Text(unit).appFont(.system(size: 14, weight: .bold)).foregroundStyle(.primary)
                        }
                    }
                    .padding(.top, 4)
                    if let chip {
                        HStack(spacing: 4) {
                            if let chipSymbol { Image(systemName: chipSymbol).appFont(.system(size: 11, weight: .heavy)) }
                            Text(chip).appFont(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Phone.well, in: Capsule())
                        .padding(.top, 8)
                    }
                }
                Spacer(minLength: 0)
                VerticalGauge(value: gauge, color: color)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .background(Phone.card, in: RoundedRectangle(cornerRadius: Phone.cardRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Phone.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)\(unit.map { " \($0)" } ?? "")\(chip.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Chips and pickers

/// Incredible's filter chips: the selected one is a solid white capsule.
struct ChipPicker<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(options, id: \.0) { value, title in
                    let selected = value == selection
                    Button {
                        withMotion(.snappy(duration: 0.2)) { selection = value }
                    } label: {
                        Text(title)
                            .appFont(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(selected ? Color(uiColor: .systemBackground) : .primary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(selected ? Color.primary : Phone.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, Phone.margin)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -Phone.margin)
    }
}

/// The compact "W M Y" capsule picker.
struct LetterPicker<Value: Hashable>: View {
    let options: [(Value, String, String)] // value, letter, spoken name
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, letter, spoken in
                let selected = value == selection
                Button { withMotion(.snappy(duration: 0.2)) { selection = value } } label: {
                    Text(letter)
                        .appFont(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(selected ? Color.primary.opacity(0.22) : .clear, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(spoken)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Phone.card, in: Capsule())
    }
}

/// A Reminders-style completion circle.
struct PhoneCheckCircle: View {
    let isOn: Bool
    let color: Color
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle().strokeBorder(isOn ? color : Color.secondary.opacity(0.6), lineWidth: 1.8)
            if isOn {
                Circle().fill(color).padding(4.5)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}
#endif
