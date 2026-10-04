//
//  SettingsViews.swift
//  Colony
//
//  Settings, laid out like System Settings: a searchable list of sections on the
//  left (profile first), and one page per section on the right under a frosted
//  navigation bar with back/forward. Pages are built from grouped, inset rows.
//  On iPhone the same pages are pushed from a plain list.
//
//  Everything here is a preference in iCloud key-value storage (CloudPreferences)
//  or a live status from an Apple service; nothing is stored anywhere else.
//

import EventKit
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case profile, general, sidebar, appearance, ai, iCloud, notifications, calendar, reminders, contacts, privacy, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: "Profile"
        case .general: "General"
        case .sidebar: "Sidebar"
        case .appearance: "Appearance"
        case .ai: "AI"
        case .iCloud: "iCloud"
        case .notifications: "Notifications"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .contacts: "Contacts"
        case .privacy: "Privacy"
        case .about: "About Colony"
        }
    }

    var symbol: String {
        switch self {
        case .profile: "person.crop.circle.fill"
        case .general: "gearshape.fill"
        case .sidebar: "sidebar.left"
        case .appearance: "circle.lefthalf.filled"
        case .ai: "sparkles"
        case .iCloud: "icloud.fill"
        case .notifications: "bell.badge.fill"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .contacts: "person.crop.circle"
        case .privacy: "hand.raised.fill"
        case .about: "info.circle.fill"
        }
    }

    /// Tile colour, as in System Settings: grey for system-ish, colour for services.
    var tint: Color {
        switch self {
        case .profile: ColonyColor.purple.color
        case .general: Color(white: 0.55)
        case .sidebar: Color(red: 0.36, green: 0.42, blue: 0.95)
        case .appearance: Color(white: 0.16)
        case .ai: Color(red: 0.55, green: 0.36, blue: 0.96)
        case .iCloud: Color(red: 0.20, green: 0.55, blue: 0.98)
        case .notifications: Color(red: 0.96, green: 0.26, blue: 0.27)
        case .calendar: Color(red: 0.93, green: 0.33, blue: 0.33)
        case .reminders: Color(red: 0.98, green: 0.58, blue: 0.10)
        case .contacts: Color(red: 0.55, green: 0.55, blue: 0.58)
        case .privacy: Color(red: 0.20, green: 0.48, blue: 0.96)
        case .about: Color(white: 0.55)
        }
    }

    /// Extra words the search field matches.
    var keywords: String {
        switch self {
        case .profile: "name photo picture avatar account"
        case .general: "workspace name keyboard shortcuts"
        case .sidebar: "hide show items reorder customize crm reports inbox agents automations music workspace"
        case .appearance: "theme dark light mode font typeface"
        case .ai: "agents model apple intelligence openai chatgpt gpt anthropic claude google gemini openrouter ollama api key jev typesafe"
        case .iCloud: "sync cloudkit storage"
        case .notifications: "alerts due dates background remind tasks sound"
        case .calendar: "apple calendar events schedule automations dated tasks"
        case .reminders: "apple reminders mirror due dates"
        case .contacts: "apple contacts import address book customers"
        case .privacy: "data policy tracking"
        case .about: "version support accessibility"
        }
    }

    /// Sidebar groups, separated by space like System Settings.
    static let groups: [[SettingsSection]] = [[.general, .sidebar, .appearance], [.ai], [.notifications, .calendar], [.iCloud, .reminders, .contacts], [.privacy, .about]]
}

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .compact {
            CompactSettings()
        } else {
            HStack(spacing: 0) {
                SettingsSidebar()
                    .frame(width: 250)
                    .background(Theme.sidebar)
                Rectangle().fill(Theme.stroke).frame(width: 1)
                SettingsDetail(section: app.settingsSection)
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Section list

private struct SettingsSidebar: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            SettingsSearchField(text: $query)
                .padding(.leading, max(10, SidebarMetrics.titleBarLeading(collapsed: app.preferences.isSidebarCollapsed)))
                .padding(.trailing, 10)
                #if os(macOS)
                .frame(height: 32) // on the traffic-light line
                #else
                .padding(.top, 14)
                #endif
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if matches(.profile) {
                        profileRow
                            .padding(.bottom, 10)
                    }
                    ForEach(Array(SettingsSection.groups.enumerated()), id: \.offset) { _, group in
                        let visible = group.filter(matches)
                        if !visible.isEmpty {
                            ForEach(visible) { section in
                                SettingsListRow(section: section, isSelected: app.settingsSection == section) {
                                    app.openSettings(section)
                                }
                            }
                            Color.clear.frame(height: 12)
                        }
                    }
                    if SettingsSection.allCases.allSatisfy({ !matches($0) }) {
                        Text("No results for “\(query)”")
                            .appFont(.system(size: 12.5))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(10)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
        }
    }

    private var profileRow: some View {
        let isSelected = app.settingsSection == .profile
        return Button { app.openSettings(.profile) } label: {
            HStack(spacing: 10) {
                ProfileAvatar(size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.preferences.displayName)
                        .appFont(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                    Text("Colony profile")
                        .appFont(.system(size: 11.5))
                        .opacity(0.75)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.white : Theme.text)
            .padding(.horizontal, 7)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor : .clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile: \(app.preferences.displayName)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func matches(_ section: SettingsSection) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return section.title.localizedCaseInsensitiveContains(q) || section.keywords.localizedCaseInsensitiveContains(q)
    }
}

private struct SettingsSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .appFont(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .appFont(.system(size: 13))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Theme.selection, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct SettingsListRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                SettingsIcon(section: section, size: 22)
                Text(section.title)
                    .appFont(.system(size: 13.5))
                    .foregroundStyle(isSelected ? Color.white : Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(minHeight: 30)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor : .clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The rounded colour tile with a white glyph.
struct SettingsIcon: View {
    let section: SettingsSection
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(section.tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: section.symbol)
                    .appFont(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Detail with frosted navigation bar

private struct SettingsDetail: View {
    @Environment(AppModel.self) private var app
    let section: SettingsSection
    @State private var isScrolled = false

    var body: some View {
        ScrollView {
            SettingsPage(section: section)
                .frame(maxWidth: 640)
                .padding(.horizontal, 28)
                .padding(.top, 14)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
        }
        .id(section)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 1 } action: { _, scrolled in
            isScrolled = scrolled
        }
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .background(Theme.canvas)
    }

    /// Back/forward pill and the page title on frosted glass; content blurs under it.
    private var navigationBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                navButton("chevron.left", label: "Back", enabled: app.canGoBackInSettings) { app.settingsBack() }
                Rectangle().fill(Theme.stroke).frame(width: 1, height: 14)
                navButton("chevron.right", label: "Forward", enabled: app.canGoForwardInSettings) { app.settingsForward() }
            }
            .glassSurface(.capsule)
            Text(section.title)
                .appFont(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .padding(.horizontal, 14)
        #if os(macOS)
        .frame(height: 32) // same line as the traffic lights
        .padding(.top, 2)
        .padding(.bottom, 8)
        #else
        .padding(.vertical, 10)
        #endif
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(isScrolled ? 1 : 0)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.stroke).frame(height: 1).opacity(isScrolled ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.15), value: isScrolled)
    }

    private func navButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .appFont(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? Theme.text : Theme.tertiaryText)
                .frame(width: 34, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - iPhone

private struct CompactSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            Section {
                NavigationLink(value: SettingsSection.profile) {
                    HStack(spacing: 12) {
                        ProfileAvatar(size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.preferences.displayName).appFont(.headline)
                            Text("Colony profile").appFont(.caption).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }
            ForEach(Array(SettingsSection.groups.enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group) { section in
                        NavigationLink(value: section) {
                            Label { Text(section.title) } icon: { SettingsIcon(section: section, size: 26) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .navigationDestination(for: SettingsSection.self) { section in
            ScrollView {
                SettingsPage(section: section).padding(20)
            }
            .background(Theme.canvas)
            .navigationTitle(section.title)
        }
    }
}

// MARK: - Pages

private struct SettingsPage: View {
    let section: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            switch section {
            case .profile: ProfilePage()
            case .general: GeneralPage()
            case .sidebar: SidebarSettingsPage()
            case .appearance: AppearancePage()
            case .ai: AISettingsPage()
            case .iCloud: ICloudPage()
            case .notifications: NotificationsPage()
            case .calendar: CalendarPage()
            case .reminders: RemindersPage()
            case .contacts: ContactsPage()
            case .privacy: PrivacyPage()
            case .about: AboutPage()
            }
        }
    }
}

/// Big icon, title and one line of explanation at the top of a service page.
struct PageHeader: View {
    let section: SettingsSection
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            SettingsIcon(section: section, size: 52)
            Text(section.title)
                .appFont(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(text)
                .appFont(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

// MARK: Profile

private struct ProfilePage: View {
    @Environment(AppModel.self) private var app
    @State private var photoItem: PhotosPickerItem?
    @State private var isImporting = false
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var prefs = app.preferences

        VStack(spacing: 10) {
            ProfileAvatar(size: 96)
                .overlay {
                    if isDropTargeted {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 3)
                    }
                }
                .overlay(alignment: .bottomTrailing) { photoMenu }
                .dropDestination(for: Data.self) { items, _ in
                    guard let data = items.first else { return false }
                    return setPhoto(data)
                } isTargeted: { isDropTargeted = $0 }
            Text(prefs.displayName)
                .appFont(.system(size: 20, weight: .semibold), role: .data)
                .foregroundStyle(Theme.text)
            Text("Shown in the sidebar and on your messages")
                .appFont(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .photosPicker(isPresented: $isPickingPhoto, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { _ = setPhoto(data) }
                photoItem = nil
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { _ = setPhoto(data) }
        }

        SettingsGroup {
            SettingsRow("Name") {
                TextField("Name", text: $prefs.displayName)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .appFont(.system(size: 13.5), role: .data)
                    .frame(maxWidth: 260)
                    .onChange(of: prefs.displayName) { _, new in if new.count > 40 { prefs.displayName = String(new.prefix(40)) } }
            }
        }

        SettingsGroup(header: "Photo", footer: "Drop an image on the picture above, or choose one. It's resized to a small square and synced to your other devices through iCloud.") {
            SettingsRow("Choose from Photos…", action: { isPickingPhoto = true })
            SettingsRow("Choose a file…", action: { isImporting = true })
            if prefs.avatarImageData != nil {
                SettingsRow("Remove photo", role: .destructive, action: { prefs.avatarImageData = nil })
            }
        }

        if prefs.avatarImageData == nil {
            SettingsGroup(header: "Monogram") {
                SettingsRow("Colour") {
                    HStack(spacing: 7) {
                        ForEach(ColonyColor.allCases) { color in
                            Button { prefs.avatarColor = color } label: {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 18, height: 18)
                                    .overlay {
                                        if prefs.avatarColor == color {
                                            Circle().strokeBorder(Theme.canvas, lineWidth: 2).padding(2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(color.title)
                            .accessibilityAddTraits(prefs.avatarColor == color ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }
            }
        }
    }

    @State private var isPickingPhoto = false

    private var photoMenu: some View {
        Menu {
            Button("Choose from Photos…", systemImage: "photo.on.rectangle") { isPickingPhoto = true }
            Button("Choose a File…", systemImage: "folder") { isImporting = true }
            if app.preferences.avatarImageData != nil {
                Divider()
                Button("Remove Photo", systemImage: "trash", role: .destructive) { app.preferences.avatarImageData = nil }
            }
        } label: {
            Image(systemName: "pencil")
                .appFont(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 28, height: 28)
                .background(Theme.raised, in: Circle())
                .overlay { Circle().strokeBorder(Theme.strongStroke, lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Change photo")
    }

    private func setPhoto(_ data: Data) -> Bool {
        guard let prepared = ProfilePhoto.prepare(data) else {
            app.show("That image couldn't be used", detail: "Try a JPEG, PNG or HEIC file.", style: .warning)
            return false
        }
        app.preferences.avatarImageData = prepared
        return true
    }
}

// MARK: General

private struct GeneralPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var prefs = app.preferences

        SettingsGroup(header: "This workspace", footer: "The name and colour at the top of the sidebar. Each workspace has its own projects, tasks, customers, channels, agents and automations.") {
            SettingsRow("Name") {
                TextField("Workspace name", text: $prefs.currentWorkspaceName)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .appFont(.system(size: 13.5))
                    .frame(maxWidth: 240)
                    .onChange(of: prefs.currentWorkspaceName) { _, new in if new.count > 32 { prefs.currentWorkspaceName = String(new.prefix(32)) } }
            }
            SettingsRow("Colour") {
                ColorSwatches(selection: Binding(get: { prefs.currentWorkspace.color }, set: { color in
                    var workspace = prefs.currentWorkspace
                    workspace.color = color
                    prefs.update(workspace)
                }))
                .disabled(prefs.currentWorkspace.isOriginal)
                .opacity(prefs.currentWorkspace.isOriginal ? 0.4 : 1)
                .help(prefs.currentWorkspace.isOriginal ? "Your first workspace keeps the Colony colours." : "")
            }
        }

        SettingsGroup(header: "Workspaces") {
            ForEach(prefs.workspaces) { workspace in
                SettingsRow(workspace.name, detail: workspace.id == prefs.currentWorkspaceID ? "Open now" : nil) {
                    if workspace.id != prefs.currentWorkspaceID {
                        Button("Open") { app.switchWorkspace(to: workspace.id) }
                    }
                    if !workspace.isOriginal {
                        Button("Delete…", role: .destructive) { app.present(.deleteWorkspace(workspace.id)) }
                    }
                }
            }
            SettingsRow("New Workspace…") { app.present(.newWorkspace) }
        }

        SettingsGroup(header: "Sidebar") {
            SettingsRow("Show sidebar") {
                Toggle("Show sidebar", isOn: Binding(get: { !prefs.isSidebarCollapsed }, set: { show in
                    if show == prefs.isSidebarCollapsed { app.toggleSidebar() }
                }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            SettingsRow("Choose what the sidebar shows…") { app.openSettings(.sidebar) }
        }

        SettingsGroup(header: "Keyboard shortcuts") {
            shortcut("Command Center", "⌘K")
            shortcut("New task", "⌘N")
            shortcut("New project", "⇧⌘N")
            shortcut("Show or hide sidebar", "⌃⌘S")
            shortcut("Save in dialogs", "⌘↩")
        }
    }

    private func shortcut(_ title: String, _ keys: String) -> some View {
        SettingsRow(title) {
            Text(keys)
                .appFont(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

// MARK: Sidebar

/// Choose what the sidebar shows, per workspace: a starting point, then each item.
private struct SidebarSettingsPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let layout = SidebarLayout(preferences: app.preferences)
        let workspace = app.preferences.currentWorkspace

        PageHeader(section: .sidebar, text: "Show the tools you use and hide the rest. This is for \(workspace.name); each workspace has its own sidebar. Hidden tools are still in Search (⌘K).")

        SettingsGroup(header: "Start from", footer: "Pick what this workspace is for, then fine-tune below.") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(WorkspacePreset.allCases) { preset in
                    PresetCard(preset: preset, isSelected: app.preferences.sidebarSetup.preset == preset) {
                        layout.apply(preset)
                    }
                }
            }
            .padding(10)
        }

        SettingsGroup(header: "Pages", footer: "Use the arrows to change the order, or drag items in the sidebar. Home is always shown.") {
            ForEach(Array(layout.allItems.enumerated()), id: \.element) { index, item in
                SidebarItemRow(
                    symbol: item.symbol,
                    title: item.title,
                    detail: item.detail,
                    isShown: !layout.isHidden(item),
                    canHide: item != .home,
                    canMoveUp: index > 0,
                    canMoveDown: index < layout.allItems.count - 1,
                    setShown: { layout.setHidden(item, !$0) },
                    move: { layout.move(item, by: $0) }
                )
            }
        }

        SettingsGroup(header: "Sections") {
            ForEach(SidebarSectionItem.allCases) { section in
                SidebarItemRow(
                    symbol: section.symbol,
                    title: section.title,
                    detail: section.detail,
                    isShown: !layout.isHidden(section),
                    setShown: { layout.setHidden(section, !$0) }
                )
            }
        }

        SettingsGroup {
            SettingsRow("Show everything, in the original order") { layout.reset() }
        }
    }
}

/// Icon, title, one line, optional ↑↓, and a switch.
private struct SidebarItemRow: View {
    let symbol: String
    let title: String
    let detail: String
    let isShown: Bool
    var canHide = true
    var canMoveUp: Bool? = nil
    var canMoveDown: Bool? = nil
    let setShown: (Bool) -> Void
    var move: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .appFont(.system(size: 13, weight: .medium))
                .foregroundStyle(isShown ? Theme.text : Theme.tertiaryText)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).appFont(.system(size: 13.5)).foregroundStyle(isShown ? Theme.text : Theme.secondaryText)
                Text(detail).appFont(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 12)
            if let move, let canMoveUp, let canMoveDown {
                HStack(spacing: 0) {
                    arrow("chevron.up", "Move \(title) up", enabled: canMoveUp) { move(-1) }
                    arrow("chevron.down", "Move \(title) down", enabled: canMoveDown) { move(1) }
                }
            }
            Toggle(isOn: Binding(get: { isShown }, set: setShown)) { Text("Show \(title)") }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!canHide)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minHeight: 44)
    }

    private func arrow(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .appFont(.system(size: 10.5, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(QuietButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }
}

// MARK: Appearance

private struct AppearancePage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var prefs = app.preferences

        SettingsGroup {
            SettingsRow("Appearance", alignment: .top) {
                HStack(spacing: 14) {
                    ForEach(AppearancePreference.allCases) { option in
                        AppearanceThumbnail(option: option, isSelected: prefs.appearance == option) {
                            prefs.appearance = option
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }

        SettingsGroup(header: "Fonts", footer: "Fonts come from this device. If a font isn't installed on another device, that device uses the system font.") {
            SettingsRow("Interface", detail: "Sidebar, headers, buttons and labels") {
                FontPopUpButton(title: "Interface font", sample: "Home  Updates  Settings", family: $prefs.uiFontFamily)
            }
            SettingsRow("Content", detail: "Tasks, messages, customers and numbers") {
                FontPopUpButton(title: "Data font", sample: "Ship the onboarding flow · 42", family: $prefs.dataFontFamily)
            }
            if !prefs.uiFontFamily.isEmpty || !prefs.dataFontFamily.isEmpty {
                SettingsRow("Use system fonts", action: {
                    prefs.uiFontFamily = ""
                    prefs.dataFontFamily = ""
                })
            }
        }
    }
}

/// Miniature window in light, dark or split, like the macOS appearance picker.
private struct AppearanceThumbnail: View {
    let option: AppearancePreference
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    switch option {
                    case .light: window(dark: false)
                    case .dark: window(dark: true)
                    case .system:
                        window(dark: false)
                            .overlay { window(dark: true).mask(HStack(spacing: 0) { Color.clear; Color.black }) }
                    }
                }
                .frame(width: 70, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Theme.strongStroke, lineWidth: isSelected ? 2.5 : 0.5)
                        .padding(isSelected ? -3 : 0)
                }
                Text(option == .system ? "Auto" : option.title)
                    .appFont(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.text : Theme.secondaryText)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option == .system ? "Auto" : option.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func window(dark: Bool) -> some View {
        let bg = dark ? Color(white: 0.12) : Color(white: 0.96)
        let side = dark ? Color(white: 0.18) : Color(white: 0.88)
        let line = dark ? Color(white: 0.34) : Color(white: 0.76)
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 4, height: 4) }
                }
                ForEach(0..<3, id: \.self) { _ in Capsule().fill(line).frame(width: 12, height: 2.5) }
                Spacer(minLength: 0)
            }
            .padding(5)
            .frame(width: 24, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(side)
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(Color.accentColor).frame(width: 22, height: 3)
                Capsule().fill(line).frame(width: 30, height: 2.5)
                Capsule().fill(line).frame(width: 18, height: 2.5)
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(bg)
        }
    }
}

// MARK: iCloud

private struct ICloudPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let state = app.iCloud.displayState
        PageHeader(section: .iCloud, text: "Projects, tasks, messages and customers live in your private iCloud database. Only you can read them; Colony has no server.")

        SettingsGroup {
            SettingsRow("Status") {
                HStack(spacing: 6) {
                    Circle().fill(state.isHealthy ? Color.green : Color.orange).frame(width: 8, height: 8)
                    Text(state.title).foregroundStyle(Theme.secondaryText)
                }
                .appFont(.system(size: 13))
            }
            if let last = app.iCloud.lastSyncedAt {
                SettingsRow("Last synced") {
                    Text(last, format: .relative(presentation: .named))
                        .appFont(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            SettingsRow("Check again", action: { Task { await app.iCloud.refresh() } })
        }

        if !state.isHealthy {
            Text(detail(for: state))
                .appFont(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 12)
        }

        SettingsGroup(header: "What syncs") {
            SettingsRow("Projects, lists and tasks") { check }
            SettingsRow("Channels and messages") { check }
            SettingsRow("Customers") { check }
            SettingsRow("Preferences, profile and sidebar order") { check }
        }

        SettingsGroup(footer: "Colony uses this iCloud container. You can see its size in System Settings › Apple Account › iCloud › Manage.") {
            SettingsRow("Container") {
                Text(CloudStore.containerIdentifier)
                    .appFont(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .textSelection(.enabled)
            }
        }
    }

    private var check: some View {
        Image(systemName: "checkmark")
            .appFont(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.secondaryText)
            .accessibilityLabel("Synced")
    }

    private func detail(for state: ICloudStatus.State) -> String {
        switch state {
        case .available: "Changes sync automatically to every device signed in with your Apple Account."
        case .noAccount: "Sign in to iCloud in System Settings to sync. Data is kept on this device until then."
        case .restricted: "iCloud is restricted by Screen Time or device management."
        case .temporarilyUnavailable: "iCloud will resume syncing automatically."
        case .localOnly(let reason): reason
        case .error(let message): message
        case .checking: "Contacting iCloud…"
        }
    }
}

// MARK: Reminders

private struct RemindersPage: View {
    @Environment(AppModel.self) private var app
    @Query private var tasksEverywhere: [TaskItem]
    private var tasks: [TaskItem] { tasksEverywhere.inWorkspace() }

    var body: some View {
        @Bindable var prefs = app.preferences
        PageHeader(section: .reminders, text: "Mirror tasks into Apple Reminders so due dates alert you on iPhone, Apple Watch and Mac.")

        SettingsGroup {
            SettingsRow("Access") {
                Text(app.reminders.statusTitle).appFont(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
            if app.reminders.canWrite {
                SettingsRow("Mirror tasks to Reminders") {
                    Toggle("Mirror tasks to Reminders", isOn: $prefs.mirrorsToReminders)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: prefs.mirrorsToReminders) { _, on in
                            guard on else { return }
                            let open = tasks.filter { !$0.isDone }
                            open.forEach { app.reminders.mirror($0) }
                            app.show("Mirrored \(open.count) tasks to Reminders")
                        }
                }
            } else {
                SettingsRow("Connect Reminders…", action: { app.present(.connectReminders) })
            }
        }

        if let error = app.reminders.lastError {
            Text(error).appFont(.system(size: 12)).foregroundStyle(.red).padding(.horizontal, 12)
        }
    }
}

// MARK: Notifications

private struct NotificationsPage: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Query private var tasksEverywhere: [TaskItem]
    private var tasks: [TaskItem] { tasksEverywhere.inWorkspace() }

    var body: some View {
        @Bindable var prefs = app.preferences
        PageHeader(section: .notifications, text: "Get an alert when a task is due, the way Reminders does: at its time, or at 9:00 for tasks with only a date. Alerts arrive even when Colony isn't open.")

        SettingsGroup(footer: "Each alert has Complete and Remind Me in 1 Hour. The switch syncs through iCloud; each device asks once for permission.") {
            SettingsRow("Notify me when tasks are due") {
                Toggle("Notify me when tasks are due", isOn: Binding(get: { prefs.notifiesTasks }, set: { on in
                    guard on else {
                        prefs.notifiesTasks = false
                        app.scheduler.run(force: true)
                        return
                    }
                    Task {
                        if await app.notifications.requestAccess() {
                            prefs.notifiesTasks = true
                            app.scheduler.run(force: true)
                            let upcoming = tasks.filter { !$0.isDone && ($0.alertDate ?? .distantPast) > .now }.count
                            app.show(upcoming == 0 ? "Notifications on" : "Notifications on for \(upcoming) upcoming task\(upcoming == 1 ? "" : "s")")
                        } else {
                            app.show("Notifications are off for Colony in System Settings")
                        }
                    }
                }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            SettingsRow("Permission") {
                Text(app.notifications.statusTitle).appFont(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
            if app.notifications.authorization == .denied {
                SettingsRow("Open Notification Settings…", action: openSystemSettings)
            }
        }
        #if os(macOS)
        SettingsGroup(footer: "Keeps Colony in the menu bar after you close its window, so snoozes and changes from other devices are applied right away. Alerts are delivered either way.") {
            SettingsRow("Keep running in the menu bar") {
                Toggle("Keep running in the menu bar", isOn: $prefs.runsInMenuBar)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            SettingsRow("Open at login") {
                Toggle("Open at login", isOn: Binding(get: { LoginItem.isEnabled }, set: { LoginItem.set($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        #endif
        EmptyView()
            .task { await app.notifications.refreshAuthorization() }
    }

    private func openSystemSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=yoavperetz.Colony") { openURL(url) }
        #else
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
        #endif
    }
}

// MARK: Calendar

private struct CalendarPage: View {
    @Environment(AppModel.self) private var app
    @Query private var tasksEverywhere: [TaskItem]
    private var tasks: [TaskItem] { tasksEverywhere.inWorkspace() }

    var body: some View {
        @Bindable var prefs = app.preferences
        PageHeader(section: .calendar, text: "Show dated tasks and automation schedules in Apple Calendar, next to the rest of your day. Colony adds its own \"Colony\" calendar and never touches your other events.")

        SettingsGroup(footer: "Tasks with only a date appear as all-day events; timed tasks take half an hour. Completing a task removes its event.") {
            SettingsRow("Access") {
                Text(app.calendar.statusTitle).appFont(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
            SettingsRow("Show tasks in Calendar") {
                Toggle("Show tasks in Calendar", isOn: Binding(get: { prefs.showsTasksInCalendar }, set: { on in
                    guard on else {
                        prefs.showsTasksInCalendar = false
                        if !prefs.showsAutomationsInCalendar { app.calendar.removeCalendar() } else { tasks.forEach { app.calendar.remove(eventID: $0.calendarEventID); $0.calendarEventID = nil } }
                        return
                    }
                    Task {
                        guard await ensureAccess() else { return }
                        prefs.showsTasksInCalendar = true
                        app.scheduler.run(force: true)
                        let dated = tasks.filter { !$0.isDone && $0.dueDate != nil }.count
                        app.show("\(dated) task\(dated == 1 ? "" : "s") added to Calendar")
                    }
                }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            SettingsRow("Show automation schedules") {
                Toggle("Show automation schedules", isOn: Binding(get: { prefs.showsAutomationsInCalendar }, set: { on in
                    guard on else {
                        prefs.showsAutomationsInCalendar = false
                        if prefs.showsTasksInCalendar { app.calendar.syncAutomations([]) } else { app.calendar.removeCalendar() }
                        return
                    }
                    Task {
                        guard await ensureAccess() else { return }
                        prefs.showsAutomationsInCalendar = true
                        app.scheduler.run(force: true)
                        app.show("Automation schedules added to Calendar")
                    }
                }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }

        if let error = app.calendar.lastError {
            Text(error).appFont(.system(size: 12)).foregroundStyle(.red).padding(.horizontal, 12)
        }
    }

    private func ensureAccess() async -> Bool {
        if app.calendar.authorization == .fullAccess { return true }
        let granted = await app.calendar.requestAccess()
        if !granted { app.show("Calendar access is off for Colony in System Settings") }
        return granted
    }
}

// MARK: Contacts

private struct ContactsPage: View {
    @Environment(AppModel.self) private var app
    @Query private var customersEverywhere: [Contact]
    private var customers: [Contact] { customersEverywhere.inWorkspace() }

    var body: some View {
        PageHeader(section: .contacts, text: "Import people from Apple Contacts into the CRM. Colony only reads your address book; it never changes it.")

        SettingsGroup {
            SettingsRow("Access") {
                Text(app.contacts.statusTitle).appFont(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
            SettingsRow("Imported customers") {
                Text("\(customers.filter { $0.appleContactIdentifier != nil }.count)")
                    .appFont(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
            if app.contacts.canRead {
                SettingsRow("Import people…", action: { app.present(.importContacts) })
            } else {
                SettingsRow("Connect Contacts…", action: { app.present(.connectContacts) })
            }
        }
    }
}

// MARK: Privacy

private struct PrivacyPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        PageHeader(section: .privacy, text: "Colony collects no data about you. Nothing leaves your devices except to your own iCloud, and to AI accounts you connect yourself.")

        SettingsGroup(footer: "AI services are optional and use your own accounts. Change them in Settings › AI.") {
            SettingsRow("Tracking") { value("None") }
            SettingsRow("Analytics") { value("None") }
            SettingsRow("Third-party services") { value(connectedServices) }
            SettingsRow("Where your data lives") { value("Your iCloud") }
        }

        SettingsGroup(footer: "Delete a project, task, customer or message and it's removed from iCloud on all your devices.") {
            SettingsLinkRow("Privacy policy", url: ColonyLinks.privacy)
        }
    }

    private func value(_ text: String) -> some View {
        Text(text).appFont(.system(size: 13)).foregroundStyle(Theme.secondaryText)
    }

    /// The AI services the user connected and that agents actually use.
    private var connectedServices: String {
        var names = AIProvider.allCases.filter { $0.isCloud && app.agents.canUse($0) }.map(\.shortTitle)
        if app.preferences.ai.jevEnabled, app.ai.hasJevKey { names.append("Jev") }
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }
}

// MARK: About

private struct AboutPage: View {
    var body: some View {
        VStack(spacing: 8) {
            AppIconImage()
                .frame(width: 84, height: 84)
            Text("Colony")
                .appFont(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("Version \(ColonyLinks.version)")
                .appFont(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryText)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)

        SettingsGroup {
            SettingsLinkRow("Support", url: ColonyLinks.support)
            SettingsLinkRow("Accessibility statement", url: ColonyLinks.accessibility)
            SettingsLinkRow("Privacy policy", url: ColonyLinks.privacy)
            SettingsLinkRow("Website", url: ColonyLinks.site)
        }

        Text("Made by Yoav Peretz")
            .appFont(.system(size: 11.5))
            .foregroundStyle(Theme.tertiaryText)
            .frame(maxWidth: .infinity)
    }
}

/// The app's own icon, from the running bundle.
private struct AppIconImage: View {
    var body: some View {
        #if os(macOS)
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .accessibilityHidden(true)
        #else
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Theme.brandGradient)
            .accessibilityHidden(true)
        #endif
    }
}

// MARK: - Grouped rows

/// An inset group of rows with hairline separators, an optional header above and
/// footnote below: the System Settings form style.
struct SettingsGroup<Content: View>: View {
    var header: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let header {
                Text(header)
                    .appFont(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(rows.indices, id: \.self) { index in
                        rows[index]
                        if index < rows.count - 1 {
                            Rectangle().fill(Theme.stroke).frame(height: 1).padding(.horizontal, 12)
                        }
                    }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke) }
            if let footer {
                Text(footer)
                    .appFont(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Title (and optional detail) on the left, a control on the right. Without a control
/// and with an action it's a whole-row button (blue text, or red when destructive).
struct SettingsRow<Trailing: View>: View {
    let title: String
    var detail: String?
    var alignment: VerticalAlignment = .center
    var role: ButtonRole?
    var action: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, detail: String? = nil, alignment: VerticalAlignment = .center, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.alignment = alignment
        self.trailing = trailing()
    }

    var body: some View {
        if let action {
            Button(role: role, action: action) {
                label
                    .foregroundStyle(role == .destructive ? Color.red : Color.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
        } else {
            HStack(alignment: alignment, spacing: 12) {
                label.foregroundStyle(Theme.text)
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 38)
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).appFont(.system(size: 13.5))
            if let detail {
                Text(detail).appFont(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
        self.trailing = EmptyView()
    }
}

/// A row that opens a web page, with the ↗ affordance.
struct SettingsLinkRow: View {
    let title: String
    let url: URL

    init(_ title: String, url: URL) {
        self.title = title
        self.url = url
    }

    var body: some View {
        Link(destination: url) {
            HStack {
                Text(title).appFont(.system(size: 13.5)).foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .appFont(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Profile avatar

/// The user's photo, or a monogram on their chosen colour. Used in the sidebar,
/// settings and on the user's own messages.
struct ProfileAvatar: View {
    @Environment(AppModel.self) private var app
    var size: CGFloat = 28
    /// Rounded square (sidebar account button) instead of a circle.
    var squircle = false

    var body: some View {
        let prefs = app.preferences
        Group {
            if let data = prefs.avatarImageData, let image = Image(data: data) {
                image.resizable().scaledToFill()
            } else {
                Rectangle()
                    .fill(prefs.avatarColor.color.gradient)
                    .overlay {
                        Text(ColonyText.initials(for: prefs.displayName))
                            .appFont(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(squircle ? AnyShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)) : AnyShape(Circle()))
        .accessibilityHidden(true)
    }
}
