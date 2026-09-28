//
//  CommandPalette.swift
//  Colony
//
//  ⌘K command center (shadcn Command / Raycast style): a floating panel near the top
//  of the window with a search field, grouped results, a keyboard-driven highlight
//  (↑ ↓ ⏎, Esc) and a hint footer. Drawn in-window so it opens instantly and never
//  fights with sheet presentation.
//

import SwiftData
import SwiftUI

struct CommandPalette: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Project.sortIndex) private var projects: [Project]
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @Query private var channels: [Channel]
    @Query private var contacts: [Contact]
    @State private var query = ""
    @State private var highlighted: String?
    @State private var lastPointer: CGPoint?
    @FocusState private var focused: Bool

    struct Item: Identifiable {
        enum Group: String, CaseIterable {
            case actions = "Actions", navigation = "Go to", projects = "Projects", tasks = "Tasks", channels = "Channels", people = "People"
        }

        let id: String
        let group: Group
        let symbol: String
        var tint: Color? = nil
        let title: String
        var subtitle: String? = nil
        var shortcut: String? = nil
        let run: () -> Void
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Rectangle().fill(Theme.stroke).frame(height: 1)
            resultsList
            Rectangle().fill(Theme.stroke).frame(height: 1)
            footer
        }
        .frame(width: 600)
        .background(Theme.raised, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.strongStroke) }
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 50, y: 24)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        .onAppear { highlighted = results.first?.id }
        .task {
            await DialogTextField.claimFocus { focused = true } isFocused: { focused }
        }
        .onChange(of: query) { _, _ in highlighted = results.first?.id }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        .accessibilityAddTraits(.isModal)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .appFont(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            TextField("Search", text: $query, prompt: Text("Type a command or search…").foregroundStyle(Theme.tertiaryText))
                .textFieldStyle(.plain)
                .appFont(.system(size: 15))
                .foregroundStyle(Theme.text)
                .focused($focused)
                .onSubmit(runHighlighted)
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
            Text("esc")
                .appFont(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(Theme.surface, in: .rect(cornerRadius: 5, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.stroke) }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if results.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "magnifyingglass").appFont(.system(size: 20)).foregroundStyle(Theme.tertiaryText)
                            Text("No results for \u{201C}\(query)\u{201D}").appFont(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                    ForEach(grouped, id: \.group) { section in
                        Text(section.group.rawValue)
                            .appFont(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.tertiaryText)
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                        ForEach(section.items) { item in
                            row(item).id(item.id)
                        }
                    }
                }
                .padding(6)
            }
            .frame(height: 340)
            .onChange(of: highlighted) { _, id in
                guard let id else { return }
                withAnimation(.snappy(duration: 0.12)) { proxy.scrollTo(id, anchor: nil) }
            }
        }
    }

    private func row(_ item: Item) -> some View {
        let isOn = item.id == highlighted
        return Button {
            item.run()
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let tint = item.tint {
                        ProjectGlyph(symbol: item.symbol, color: tint, size: 18)
                    } else {
                        Image(systemName: item.symbol)
                            .appFont(.system(size: 13))
                            .foregroundStyle(isOn ? Theme.text : Theme.icon)
                    }
                }
                .frame(width: 20)
                Text(item.title)
                    .appFont(.system(size: 13.5))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .appFont(.system(size: 12))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .appFont(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.tertiaryText)
                } else if isOn {
                    Image(systemName: "return")
                        .appFont(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(isOn ? Theme.selection : .clear, in: .rect(cornerRadius: 8, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onContinuousHover(coordinateSpace: .global) { phase in
            // Only a real pointer move changes the highlight. Rows that slide under a
            // resting pointer while typing must not steal it from the keyboard.
            guard case .active(let location) = phase, location != lastPointer else { return }
            let moved = lastPointer != nil
            lastPointer = location
            if moved { highlighted = item.id }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var footer: some View {
        HStack(spacing: 14) {
            KeyHint(keys: ["↑", "↓"], label: "navigate")
            KeyHint(keys: ["⏎"], label: "open")
            KeyHint(keys: ["esc"], label: "close")
            Spacer()
            Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                .appFont(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Theme.surface.opacity(0.5))
    }

    // MARK: Behaviour

    private func move(_ delta: Int) {
        let ids = results.map(\.id)
        guard !ids.isEmpty else { return }
        let current = highlighted.flatMap(ids.firstIndex) ?? -1
        highlighted = ids[(current + delta + ids.count) % ids.count]
    }

    private func runHighlighted() {
        (results.first { $0.id == highlighted } ?? results.first)?.run()
    }

    private func close() {
        withAnimation(.snappy(duration: 0.15)) { app.isCommandPalettePresented = false }
    }

    private func go(_ destination: Destination) -> () -> Void {
        { close(); app.go(destination) }
    }

    private func open(_ dialog: ActiveSheet) -> () -> Void {
        { withAnimation(.snappy(duration: 0.18)) { app.present(dialog) } }
    }

    // MARK: Data

    private var allItems: [Item] {
        var items: [Item] = [
            Item(id: "a-task", group: .actions, symbol: "plus", title: "New task", shortcut: "⌘N", run: open(.newTask(project: nil, list: nil))),
            Item(id: "a-project", group: .actions, symbol: "folder.badge.plus", title: "New project", shortcut: "⇧⌘N", run: open(.newProject)),
            Item(id: "a-channel", group: .actions, symbol: "number", title: "New channel", run: open(.newChannel)),
            Item(id: "a-contact", group: .actions, symbol: "person.crop.circle.badge.plus", title: "New contact", run: open(.newContact)),
            Item(id: "a-import", group: .actions, symbol: "person.crop.rectangle.stack", title: "Import from Apple Contacts", run: open(app.contacts.canRead ? .importContacts : .connectContacts)),
            Item(id: "a-appearance", group: .actions, symbol: app.preferences.appearance == .light ? "moon" : "sun.max", title: app.preferences.appearance == .light ? "Switch to dark appearance" : "Switch to light appearance", run: {
                app.preferences.appearance = app.preferences.appearance == .light ? .dark : .light
                close()
            }),
            Item(id: "a-sidebar", group: .actions, symbol: "sidebar.left", title: app.preferences.isSidebarCollapsed ? "Expand sidebar" : "Collapse sidebar", shortcut: "⌃⌘S", run: {
                app.preferences.isSidebarCollapsed.toggle()
                close()
            }),
            Item(id: "n-home", group: .navigation, symbol: "house", title: "Home", run: go(.home)),
            Item(id: "n-updates", group: .navigation, symbol: "bell", title: "Updates", run: go(.updates)),
            Item(id: "n-inbox", group: .navigation, symbol: "tray", title: "Inbox", run: go(.messages(channel: nil))),
            Item(id: "n-mine", group: .navigation, symbol: "list.clipboard", title: "My tasks", run: go(.myTasks)),
            Item(id: "n-all", group: .navigation, symbol: "checklist", title: "All tasks", run: go(.allTasks)),
            Item(id: "n-projects", group: .navigation, symbol: "square.stack.3d.up", title: "Projects", run: go(.projects)),
            Item(id: "n-pipeline", group: .navigation, symbol: "square.grid.2x2", title: "Pipeline", run: go(.pipeline)),
            Item(id: "n-contacts", group: .navigation, symbol: "person.2", title: "Contacts", run: go(.contacts)),
            Item(id: "n-reports", group: .navigation, symbol: "chart.pie", title: "Reports", run: go(.reports)),
            Item(id: "n-apple", group: .navigation, symbol: "puzzlepiece.extension", title: "Apple services", run: go(.appleServices)),
            Item(id: "n-settings", group: .navigation, symbol: "slider.horizontal.3", title: "Settings", run: go(.settings))
        ]
        items += projects.map { p in
            Item(id: "p-\(p.uuid)", group: .projects, symbol: p.symbol, tint: p.color.color, title: p.name, subtitle: p.openTaskCount > 0 ? "\(p.openTaskCount) open" : nil, run: go(.project(p.uuid)))
        }
        items += tasks.map { t in
            Item(id: "t-\(t.uuid)", group: .tasks, symbol: t.isDone ? "checkmark.circle.fill" : "circle", title: t.title, subtitle: t.project?.name, run: open(.task(t.uuid)))
        }
        items += channels.map { c in
            Item(id: "c-\(c.uuid)", group: .channels, symbol: "number", title: c.name, subtitle: c.topic.isEmpty ? nil : c.topic, run: go(.messages(channel: c.uuid)))
        }
        items += contacts.map { c in
            Item(id: "k-\(c.uuid)", group: .people, symbol: "person.crop.circle", title: c.name, subtitle: c.company.isEmpty ? nil : c.company, run: go(.contacts))
        }
        return items
    }

    private var results: [Item] {
        let q = ColonyText.trimmed(query)
        guard !q.isEmpty else {
            // Empty query: actions, navigation and projects; tasks/people appear once you type.
            return allItems.filter { [.actions, .navigation, .projects].contains($0.group) }
        }
        return allItems
            .compactMap { item -> (Item, Int)? in
                let score = Self.score(item.title, q) ?? item.subtitle.flatMap { Self.score($0, q) }.map { $0 + 50 }
                return score.map { (item, $0) }
            }
            .sorted { $0.1 == $1.1 ? Item.Group.allCases.firstIndex(of: $0.0.group)! < Item.Group.allCases.firstIndex(of: $1.0.group)! : $0.1 < $1.1 }
            .prefix(60)
            .map(\.0)
    }

    /// Lower is better: prefix match, then word prefix, then substring, then initials
    /// ("nt" → "New task"). No loose subsequence matching, so results stay predictable.
    static func score(_ text: String, _ query: String) -> Int? {
        let text = text.lowercased(), query = query.lowercased()
        if text.hasPrefix(query) { return 0 }
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.contains(where: { $0.hasPrefix(query) }) { return 10 }
        if text.contains(query) { return 20 }
        let initials = String(words.compactMap(\.first))
        if query.count >= 2, initials.hasPrefix(query) { return 30 }
        return nil
    }

    /// Results grouped for display, preserving the ranked order inside each group.
    private var grouped: [(group: Item.Group, items: [Item])] {
        let items = results
        var order: [Item.Group] = []
        var buckets: [Item.Group: [Item]] = [:]
        for item in items {
            if buckets[item.group] == nil { order.append(item.group) }
            buckets[item.group, default: []].append(item)
        }
        return order.map { ($0, buckets[$0]!) }
    }
}

/// Presents the palette in-window, anchored near the top like Spotlight.
struct CommandPaletteHost: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            ZStack(alignment: .top) {
                if app.isCommandPalettePresented {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .contentShape(.rect)
                        .onTapGesture { withAnimation(.snappy(duration: 0.15)) { app.isCommandPalettePresented = false } }
                        .transition(.opacity)
                        .accessibilityHidden(true)
                    CommandPalette()
                        .padding(.top, 90)
                        .padding(.horizontal, 24)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.97, anchor: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.18), value: app.isCommandPalettePresented)
        }
    }
}
