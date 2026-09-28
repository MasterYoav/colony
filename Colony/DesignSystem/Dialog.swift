//
//  Dialog.swift
//  Colony
//
//  One dialog system for every pop-up in the app, modelled on shadcn/ui's Dialog and
//  macOS alert conventions:
//
//  ┌───────────────────────────────────────────┐
//  │ [◼] Title                              ✕  │  header: icon tile, title, one-line description
//  │     Short description                     │
//  ├───────────────────────────────────────────┤
//  │ Label                                     │  body: labelled fields, 16pt rhythm
//  │ [ field                             ]     │
//  ├───────────────────────────────────────────┤
//  │ hint                      Cancel  [Create]│  footer: right-aligned actions, ⎋ / ⏎
//  └───────────────────────────────────────────┘
//
//  Dialogs are drawn in-window (not as system sheets) so they are centred, sized to
//  their content, dim the app behind them and look the same on Mac, iPad and Vision Pro.
//  iPhone keeps the native sheet with the same content.
//

import SwiftUI

// MARK: - Tokens

enum DialogMetrics {
    static let cornerRadius: CGFloat = 16
    static let padding: CGFloat = 20
    static let fieldHeight: CGFloat = 34
    static let fieldRadius: CGFloat = 8
    static let spacing: CGFloat = 16
}

// MARK: - Presentation

extension View {
    /// Centred, in-window modal with a dimmed scrim. Escape and a scrim click dismiss it.
    func dialogOverlay<Item: Identifiable, Content: View>(item: Binding<Item?>, width: @escaping (Item) -> CGFloat, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        modifier(DialogOverlay(item: item, width: width, dialog: content))
    }
}

private struct DialogOverlay<Item: Identifiable, Dialog: View>: ViewModifier {
    @Binding var item: Item?
    let width: (Item) -> CGFloat
    @ViewBuilder let dialog: (Item) -> Dialog
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    if item != nil {
                        Color.black.opacity(0.45)
                            .ignoresSafeArea()
                            .contentShape(.rect)
                            .onTapGesture { item = nil }
                            .transition(.opacity)
                            .accessibilityHidden(true)
                    }
                    if let current = item {
                        dialog(current)
                            .environment(\.dialogDismiss, DialogDismissAction { item = nil })
                            .frame(width: width(current))
                            .frame(maxHeight: 640)
                            .fixedSize(horizontal: false, vertical: true)
                            .background(Theme.raised, in: .rect(cornerRadius: DialogMetrics.cornerRadius, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: DialogMetrics.cornerRadius, style: .continuous)
                                    .strokeBorder(Theme.strongStroke)
                            }
                            .clipShape(.rect(cornerRadius: DialogMetrics.cornerRadius, style: .continuous))
                            .shadow(color: .black.opacity(0.35), radius: 40, y: 20)
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                            .padding(24)
                            .id(current.id)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
                            .onKeyPress(.escape) { item = nil; return .handled }
                            .accessibilityAddTraits(.isModal)
                    }
                }
                .animation(.snappy(duration: 0.22), value: item?.id)
            }
    }
}

/// Dismisses whichever dialog is showing, whether it was presented in-window or as a native sheet.
struct DialogDismissAction {
    var action: (() -> Void)?
    func callAsFunction() { action?() }
}

private struct DialogDismissKey: EnvironmentKey {
    static let defaultValue = DialogDismissAction(action: nil)
}

extension EnvironmentValues {
    var dialogDismiss: DialogDismissAction {
        get { self[DialogDismissKey.self] }
        set { self[DialogDismissKey.self] = newValue }
    }
}

// MARK: - Frame

/// Header, scrolling body and footer. Every dialog in the app is built from this.
struct DialogFrame<Content: View, Footer: View>: View {
    var symbol: String? = nil
    var tint: Color = Theme.text
    let title: String
    var description: String? = nil
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer
    @Environment(\.dialogDismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: DialogMetrics.spacing, content: content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DialogMetrics.padding)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.automatic)

            HStack(spacing: 8, content: footer)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, DialogMetrics.padding)
                .padding(.vertical, 14)
                .background(Theme.surface.opacity(0.5))
                .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .appFont(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12), in: .rect(cornerRadius: 8, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tint.opacity(0.18)) }
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appFont(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                if let description {
                    Text(description)
                        .appFont(.system(size: 12.5))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, symbol == nil ? 0 : 1)
            Spacer(minLength: 8)
            DialogCloseButton { dismiss() }
        }
        .padding(.horizontal, DialogMetrics.padding)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }
}

extension DialogFrame where Footer == EmptyView {
    init(symbol: String? = nil, tint: Color = Theme.text, title: String, description: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(symbol: symbol, tint: tint, title: title, description: description, content: content, footer: { EmptyView() })
    }
}

struct DialogCloseButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .appFont(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovering ? Theme.text : Theme.secondaryText)
                .frame(width: 26, height: 26)
                .background(isHovering ? Theme.hover : .clear, in: .rect(cornerRadius: 6, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .keyboardShortcut(.cancelAction)
        .help("Close (Esc)")
        .accessibilityLabel("Close")
    }
}

// MARK: - Buttons

/// shadcn-style buttons: primary (solid), secondary (outline), ghost and destructive.
struct DialogButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, destructive }
    var kind: Kind = .secondary
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(.system(size: 13, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(background(pressed: configuration.isPressed), in: .rect(cornerRadius: 8, style: .continuous))
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.strongStroke)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
            .contentShape(.rect)
            .onHover { isHovering = $0 }
    }

    private var foreground: Color {
        switch kind {
        case .primary: Theme.canvas
        case .destructive: .white
        case .secondary, .ghost: Theme.text
        }
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primary: Theme.text.opacity(pressed ? 0.8 : (isHovering ? 0.9 : 1))
        case .destructive: Color.red.opacity(pressed ? 0.75 : (isHovering ? 0.88 : 1))
        case .secondary: pressed ? Theme.selection : (isHovering ? Theme.hover : Theme.surface)
        case .ghost: pressed ? Theme.selection : (isHovering ? Theme.hover : .clear)
        }
    }
}

extension ButtonStyle where Self == DialogButtonStyle {
    static var dialogPrimary: DialogButtonStyle { DialogButtonStyle(kind: .primary) }
    static var dialogSecondary: DialogButtonStyle { DialogButtonStyle(kind: .secondary) }
    static var dialogGhost: DialogButtonStyle { DialogButtonStyle(kind: .ghost) }
    static var dialogDestructive: DialogButtonStyle { DialogButtonStyle(kind: .destructive) }
}

/// Keyboard hint shown on the leading side of a footer ("⏎ to create").
struct KeyHint: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .appFont(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Theme.surface, in: .rect(cornerRadius: 4, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.stroke) }
            }
            Text(label)
                .appFont(.system(size: 11.5))
                .foregroundStyle(Theme.tertiaryText)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Fields

/// Label above a control, with optional trailing accessory (counter, hint).
struct DialogField<Control: View, Accessory: View>: View {
    let label: String
    var hint: String? = nil
    @ViewBuilder var control: () -> Control
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .appFont(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                accessory()
            }
            control()
            if let hint {
                Text(hint)
                    .appFont(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension DialogField where Accessory == EmptyView {
    init(label: String, hint: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.init(label: label, hint: hint, control: control, accessory: { EmptyView() })
    }
}

/// Bordered input chrome with a focus ring, shared by text fields, editors and pickers.
struct DialogInputChrome: ViewModifier {
    var isFocused: Bool
    var isInvalid: Bool = false
    var minHeight: CGFloat = DialogMetrics.fieldHeight

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .frame(minHeight: minHeight)
            .background(Theme.field, in: .rect(cornerRadius: DialogMetrics.fieldRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DialogMetrics.fieldRadius, style: .continuous)
                    .strokeBorder(isInvalid ? Color.red.opacity(0.7) : (isFocused ? Theme.secondaryText : Theme.strongStroke), lineWidth: 1)
            }
            .background {
                // Soft outer ring like shadcn's focus-visible state.
                RoundedRectangle(cornerRadius: DialogMetrics.fieldRadius + 3, style: .continuous)
                    .stroke(isInvalid ? Color.red.opacity(0.25) : Theme.secondaryText.opacity(0.22), lineWidth: 3)
                    .padding(-1.5)
                    .opacity(isFocused || isInvalid ? 1 : 0)
            }
            .animation(.smooth(duration: 0.15), value: isFocused)
    }
}

extension View {
    func dialogInput(isFocused: Bool, isInvalid: Bool = false, minHeight: CGFloat = DialogMetrics.fieldHeight) -> some View {
        modifier(DialogInputChrome(isFocused: isFocused, isInvalid: isInvalid, minHeight: minHeight))
    }
}

/// Single-line text input with leading icon, placeholder and focus ring.
struct DialogTextField: View {
    let placeholder: String
    @Binding var text: String
    var symbol: String? = nil
    var limit: Int? = nil
    var isInvalid: Bool = false
    var autofocus: Bool = false
    var onSubmit: (() -> Void)? = nil
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .appFont(.system(size: 12.5))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: 16)
                    .accessibilityHidden(true)
            }
            TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(Theme.tertiaryText))
                .textFieldStyle(.plain)
                .appFont(.system(size: 13.5), role: .data) // what the user types is content
                .foregroundStyle(Theme.text)
                .focused($focused)
                .onSubmit { onSubmit?() }
                .onChange(of: text) { _, new in
                    if let limit, new.count > limit { text = String(new.prefix(limit)) }
                }
        }
        .dialogInput(isFocused: focused, isInvalid: isInvalid)
        .contentShape(.rect)
        .onTapGesture { focused = true }
        .task {
            guard autofocus else { return }
            await Self.claimFocus { focused = true } isFocused: { focused }
        }
    }
}

extension DialogTextField {
    /// macOS only accepts first-responder changes once the view is in the window and the
    /// presentation transition has started, which varies with what was focused before.
    /// Retry briefly until the field reports focus.
    @MainActor
    static func claimFocus(_ focus: () -> Void, isFocused: () -> Bool) async {
        for delay in [40, 120, 250, 450] {
            try? await Task.sleep(for: .milliseconds(delay))
            if Task.isCancelled || isFocused() { return }
            focus()
        }
    }
}

/// Multi-line text input.
struct DialogTextEditor: View {
    let placeholder: String
    @Binding var text: String
    var lines: ClosedRange<Int> = 3...6
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(Theme.tertiaryText), axis: .vertical)
            .textFieldStyle(.plain)
            .appFont(.system(size: 13.5), role: .data)
            .foregroundStyle(Theme.text)
            .lineLimit(lines)
            .focused($focused)
            .padding(.vertical, 8)
            .dialogInput(isFocused: focused)
            .contentShape(.rect)
            .onTapGesture { focused = true }
    }
}

/// Menu-backed select that looks like the text fields.
struct DialogSelect<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String, symbol: String?)]

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.title, systemImage: "checkmark")
                    } else if let symbol = option.symbol {
                        Label(option.title, systemImage: symbol)
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let symbol = current?.symbol {
                    Image(systemName: symbol).appFont(.system(size: 12.5)).foregroundStyle(Theme.icon)
                }
                Text(current?.title ?? "Select")
                    .appFont(.system(size: 13.5))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down")
                    .appFont(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .dialogInput(isFocused: false)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private var current: (value: Value, title: String, symbol: String?)? {
        options.first { $0.value == selection }
    }
}

/// Toggle row: title + description on the left, switch on the right.
struct DialogToggleRow: View {
    let title: String
    var description: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).appFont(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                if let description {
                    Text(description).appFont(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn.animation(.snappy(duration: 0.2)))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(12)
        .background(Theme.surface, in: .rect(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke) }
    }
}

/// Editable tag list ("Sprint 1", "March"): chips with remove buttons plus an inline input.
struct ChipInput: View {
    @Binding var items: [String]
    var placeholder: String = "Add…"
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 4) {
                    Text(item)
                        .appFont(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Button {
                        withAnimation(.snappy(duration: 0.18)) { items.removeAll { $0 == item } }
                    } label: {
                        Image(systemName: "xmark")
                            .appFont(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 14, height: 14)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item)")
                }
                .padding(.leading, 8)
                .padding(.trailing, 4)
                .frame(height: 24)
                .background(Theme.selection, in: .rect(cornerRadius: 6, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.strongStroke) }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            TextField(placeholder, text: $draft, prompt: Text(items.isEmpty ? placeholder : "Add…").foregroundStyle(Theme.tertiaryText))
                .textFieldStyle(.plain)
                .appFont(.system(size: 13.5))
                .foregroundStyle(Theme.text)
                .focused($focused)
                .frame(minWidth: 90)
                .frame(height: 24)
                .onSubmit(commit)
                .onKeyPress(.delete) {
                    guard draft.isEmpty, !items.isEmpty else { return .ignored }
                    withAnimation(.snappy(duration: 0.18)) { _ = items.removeLast() }
                    return .handled
                }
        }
        .padding(.vertical, 5)
        .dialogInput(isFocused: focused)
        .contentShape(.rect)
        .onTapGesture { focused = true }
    }

    private func commit() {
        let value = ColonyText.trimmed(draft)
        guard !value.isEmpty, !items.contains(value) else { draft = ""; return }
        withAnimation(.snappy(duration: 0.18)) { items.append(value) }
        draft = ""
        focused = true
    }
}

/// Wrapping row layout for chips and swatches.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let isLast = index == row.indices.last
                // The last item in a row (the inline input) stretches to fill the remaining width.
                let width = isLast && index == subviews.count - 1 ? max(size.width, bounds.maxX - x) : size.width
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y + (row.height - size.height) / 2), anchor: .topLeading, proposal: ProposedViewSize(width: width, height: size.height))
                x += width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                let y = row.y + row.height + spacing
                rows.append(Row(indices: [index], y: y, width: size.width, height: size.height))
                continue
            }
            row.indices.append(index)
            row.width = needed
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

// MARK: - Confirmation

/// Destructive/confirm dialog (shadcn AlertDialog): icon, title, message, Cancel + action.
struct ConfirmDialog: View {
    let symbol: String
    let title: String
    let message: String
    let confirmTitle: String
    var isDestructive: Bool = true
    let confirm: () -> Void
    @Environment(\.dialogDismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .appFont(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isDestructive ? Color.red : Theme.text)
                    .frame(width: 36, height: 36)
                    .background((isDestructive ? Color.red : Theme.text).opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .appFont(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(message)
                        .appFont(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(DialogMetrics.padding)

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.dialogSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle) {
                    confirm()
                    dismiss()
                }
                .buttonStyle(isDestructive ? .dialogDestructive : .dialogPrimary)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, DialogMetrics.padding)
            .padding(.bottom, DialogMetrics.padding)
        }
    }
}
