//
//  FontPicker.swift
//  Colony
//
//  Settings › Appearance font pickers. A field shows the current family in its own
//  typeface; clicking opens a searchable list of every family installed on the device,
//  each row rendered in that family. "System" (Apple's system font) is always first.
//

import SwiftUI

struct FontPickerRow: View {
    let title: String
    let detail: String
    let sample: String
    @Binding var family: String
    @State private var isOpen = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).appFont(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                Text(detail).appFont(.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 12)
            Button { isOpen.toggle() } label: {
                HStack(spacing: 8) {
                    Text(displayName)
                        .font(previewFont(family, size: 13))
                        .foregroundStyle(isMissing ? Theme.secondaryText : Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.up.chevron.down")
                        .appFont(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .padding(.horizontal, 10)
                .frame(width: 220, height: 32)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(isOpen ? Theme.secondaryText.opacity(0.6) : Theme.strongStroke) }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title): \(displayName)")
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                FontList(selection: $family, sample: sample) { isOpen = false }
            }
        }
    }

    private var isMissing: Bool {
        !family.isEmpty && InstalledFonts.available(family) == nil
    }

    private var displayName: String {
        if family.isEmpty { return "System" }
        return isMissing ? "\(family) (not installed)" : family
    }
}

/// Searchable list of installed families. Arrow keys move, Return picks, Esc closes.
private struct FontList: View {
    @Binding var selection: String
    let sample: String
    let onPick: () -> Void

    @State private var query = ""
    @State private var highlighted: String?
    @FocusState private var searchFocused: Bool

    private static let systemToken = ""

    private var results: [String] {
        let all = [Self.systemToken] + InstalledFonts.families
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { name in
            (name.isEmpty ? "System" : name).localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .appFont(.system(size: 12))
                    .foregroundStyle(Theme.tertiaryText)
                TextField("Search \(InstalledFonts.families.count) fonts", text: $query)
                    .textFieldStyle(.plain)
                    .appFont(.system(size: 13))
                    .focused($searchFocused)
                    .onSubmit { if let highlighted { pick(highlighted) } }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(results, id: \.self) { name in
                            row(name)
                                .id(name)
                        }
                        if results.isEmpty {
                            Text("No fonts match “\(query)”")
                                .appFont(.caption)
                                .foregroundStyle(Theme.secondaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        }
                    }
                    .padding(6)
                }
                .onAppear {
                    highlighted = selection
                    proxy.scrollTo(selection, anchor: .center)
                }
                .onChange(of: highlighted) { _, new in
                    if let new { withMotion(.snappy(duration: 0.12)) { proxy.scrollTo(new) } }
                }
            }
        }
        .frame(width: 320, height: 380)
        .background(Theme.raised)
        .onChange(of: query) { highlighted = results.first }
        .task { await DialogTextField.claimFocus { searchFocused = true } isFocused: { searchFocused } }
    }

    private func row(_ name: String) -> some View {
        let isSelected = name == selection
        return Button { pick(name) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? "System" : name)
                        .appFont(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                    Text(sample)
                        .font(previewFont(name, size: 15))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark")
                        .appFont(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(highlighted == name ? Theme.selection : .clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { if $0 { highlighted = name } }
        .accessibilityLabel(name.isEmpty ? "System" : name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        let index = highlighted.flatMap { results.firstIndex(of: $0) } ?? -1
        highlighted = results[max(0, min(results.count - 1, index + delta))]
    }

    private func pick(_ name: String) {
        selection = name
        onPick()
    }
}

/// A family rendered at `size`; empty or missing families preview in the system font.
private func previewFont(_ family: String, size: CGFloat) -> Font {
    MainActor.assumeIsolated {
        InstalledFonts.available(family).map { .custom($0, fixedSize: size) } ?? .system(size: size)
    }
}
