//
//  CRMViews.swift
//  Colony
//
//  The CRM: one screen with two views of the same customers.
//   • Customers: a table grouped by deal stage (coloured stage pills, counts,
//     collapsible groups, "Add customer" at the end of each group).
//   • Pipeline: the same people as a board; drag cards between stages.
//  Selecting someone opens the detail panel on the right. People can be imported
//  from Apple Contacts; mail, calls and FaceTime hand off to the system apps.
//

import SwiftData
import SwiftUI

enum CRMTab: String, CaseIterable, Identifiable {
    case customers, pipeline

    var id: String { rawValue }
    var title: String { self == .customers ? "Customers" : "Pipeline" }
    var symbol: String { self == .customers ? "person.2.fill" : "square.grid.2x2.fill" }
    var tint: ColonyColor { self == .customers ? .blue : .purple }
}

struct CRMView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Contact.name) private var contacts: [Contact]
    @State private var search = ""

    var body: some View {
        @Bindable var app = app
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 28)
                    .padding(.top, 22)

                UnderlineTabs(selection: $app.crmTab, tabs: CRMTab.allCases) { tab in
                    TabGlyph(symbol: tab.symbol, color: tab.tint.color)
                    Text(tab.title)
                }
                .padding(.horizontal, 28)
                .padding(.top, 14)

                Rectangle().fill(Theme.stroke).frame(height: 1)

                if contacts.isEmpty {
                    importBanner
                        .padding(.horizontal, 28)
                        .padding(.top, 16)
                }
                switch app.crmTab {
                case .customers: CustomersTable(contacts: filtered, selection: $app.crmSelection)
                case .pipeline: PipelineBoard(contacts: filtered, selection: $app.crmSelection)
                }
            }
            .frame(maxWidth: .infinity)

            if let contact = contacts.first(where: { $0.uuid == app.crmSelection }) {
                Rectangle().fill(Theme.stroke).frame(width: 1)
                ContactInspector(contact: contact) { app.crmSelection = nil }
                    .frame(width: 320)
                    .background(Theme.sidebar)
                    .transition(.move(edge: .trailing))
            }
        }
        .motion(.snappy, value: app.crmSelection)
        .navigationTitle("CRM")
    }

    private var header: some View {
        HStack(spacing: 12) {
            ProjectGlyph(symbol: "person.2.fill", color: ColonyColor.indigo.color, size: 26)
            Text("CRM")
                .appFont(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(summary)
                .appFont(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 12)
            SearchPill(text: $search, prompt: "Search customers")
                .frame(maxWidth: 240)
            Menu {
                Button("New customer", systemImage: "person.crop.circle.badge.plus") { app.present(.newContact) }
                Button("Import from Contacts", systemImage: "person.crop.rectangle.stack") {
                    app.present(app.contacts.canRead ? .importContacts : .connectContacts)
                }
            } label: {
                Label("Add", systemImage: "plus")
            } primaryAction: {
                app.present(.newContact)
            }
            .menuStyle(.button)
            .buttonStyle(QuietButtonStyle())
            .fixedSize()
        }
    }

    /// First run: point at Apple Contacts; "Add customer" in any group works too.
    private var importBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.rectangle.stack")
                .appFont(.system(size: 18))
                .foregroundStyle(ColonyColor.indigo.color)
            VStack(alignment: .leading, spacing: 2) {
                Text("No customers yet").appFont(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text("Import people from Apple Contacts, or use Add customer in any stage below.")
                    .appFont(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 12)
            Button("Import from Contacts") {
                app.present(app.contacts.canRead ? .importContacts : .connectContacts)
            }
            .buttonStyle(QuietButtonStyle())
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke) }
    }

    /// "12 customers · $48,000 open"
    private var summary: String {
        let open = contacts.filter(\.stage.isOpen).reduce(0) { $0 + $1.dealValue }
        let people = "\(contacts.count) \(contacts.count == 1 ? "customer" : "customers")"
        return open > 0 ? "\(people) · \(CRMFormat.money(open)) open" : people
    }

    private var filtered: [Contact] {
        let q = ColonyText.trimmed(search)
        guard !q.isEmpty else { return contacts }
        return contacts.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.company.localizedCaseInsensitiveContains(q) || $0.email.localizedCaseInsensitiveContains(q)
        }
    }
}

enum CRMFormat {
    static var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }

    static func money(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode).precision(.fractionLength(0)))
    }
}

// MARK: - Customers table

struct CustomersTable: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let contacts: [Contact]
    @Binding var selection: UUID?
    @State private var collapsed: Set<DealStage> = []
    @State private var width: CGFloat = 900

    /// Columns drop out as the table narrows, least important first.
    private var showsEmail: Bool { width > 860 }
    private var showsCompany: Bool { width > 600 }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                columnHeader
                ForEach(DealStage.allCases) { stage in
                    let people = contacts.filter { $0.stage == stage }
                    StageGroupHeader(stage: stage, count: people.count, total: people.reduce(0) { $0 + $1.dealValue }, isCollapsed: collapsed.contains(stage)) {
                        withMotion(.snappy(duration: 0.2)) {
                            if collapsed.contains(stage) { collapsed.remove(stage) } else { collapsed.insert(stage) }
                        }
                    }
                    .dropDestination(for: String.self) { ids, _ in move(ids, to: stage) }
                    if !collapsed.contains(stage) {
                        ForEach(people) { contact in
                            CustomerRow(contact: contact, isSelected: selection == contact.uuid, showsCompany: showsCompany, showsEmail: showsEmail) {
                                selection = selection == contact.uuid ? nil : contact.uuid
                            }
                            .draggable(contact.uuid.uuidString)
                        }
                        AddCustomerRow(stage: stage) { contact in selection = contact.uuid }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 34)
            if showsCompany { Text("Company").frame(width: 170, alignment: .leading) }
            if showsEmail { Text("Email").frame(width: 210, alignment: .leading) }
            Text("Value").frame(width: 96, alignment: .trailing)
            Color.clear.frame(width: 24)
        }
        .appFont(.system(size: 12.5, weight: .medium))
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 8)
        .frame(minHeight: 40)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
        .accessibilityHidden(true)
    }

    private func move(_ ids: [String], to stage: DealStage) -> Bool {
        let uuids = Set(ids.compactMap(UUID.init(uuidString:)))
        for contact in contacts where uuids.contains(contact.uuid) {
            withMotion(.snappy) { WorkspaceActions(context: context).setStage(stage, for: contact) }
        }
        return !uuids.isEmpty
    }
}

/// Disclosure triangle + coloured stage pill + count, like a grouped task list.
struct StageGroupHeader: View {
    let stage: DealStage
    let count: Int
    let total: Double
    let isCollapsed: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: "triangle.fill")
                    .appFont(.system(size: 8))
                    .rotationEffect(.degrees(isCollapsed ? 90 : 180))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 14)
                StagePill(stage: stage)
                Text("\(count)")
                    .appFont(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                if total > 0 {
                    Text(CRMFormat.money(total))
                        .appFont(.system(size: 12.5, weight: .medium), role: .data)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.trailing, 44)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stage.title), \(count) \(count == 1 ? "customer" : "customers")")
        .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
        .accessibilityHint("Toggles the group")
    }
}

/// Solid stage badge: white icon and uppercase title on the stage colour.
struct StagePill: View {
    let stage: DealStage
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: stage.symbol)
                .appFont(.system(size: compact ? 10 : 11.5, weight: .bold))
            Text(stage.title.uppercased())
                .appFont(.system(size: compact ? 10.5 : 12, weight: .semibold))
                .tracking(0.3)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 7 : 9)
        .frame(minHeight: compact ? 20 : 26)
        .background(stage.pillColor, in: RoundedRectangle(cornerRadius: compact ? 5 : 7, style: .continuous))
    }
}

extension DealStage {
    /// Darker than the palette colour so white text on the pill stays readable.
    var pillColor: Color {
        switch self {
        case .lead: Color(red: 0.42, green: 0.43, blue: 0.47)
        case .qualified: Color(red: 0.11, green: 0.42, blue: 0.86)
        case .proposal: Color(red: 0.49, green: 0.25, blue: 0.80)
        case .negotiation: Color(red: 0.70, green: 0.33, blue: 0.02)
        case .won: Color(red: 0.10, green: 0.53, blue: 0.29)
        case .lost: Color(red: 0.78, green: 0.16, blue: 0.19)
        }
    }
}

struct CustomerRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let contact: Contact
    let isSelected: Bool
    let showsCompany: Bool
    let showsEmail: Bool
    let open: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    AvatarView(name: contact.name, color: contact.color.color, imageData: contact.imageData, size: 24)
                    Text(contact.name)
                        .appFont(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if !showsCompany, !contact.company.isEmpty {
                        Text(contact.company).appFont(.system(size: 13)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if showsCompany {
                    cell(contact.company, width: 170)
                }
                if showsEmail {
                    cell(contact.email, width: 210)
                }
                Text(contact.dealValue > 0 ? CRMFormat.money(contact.dealValue) : "—")
                    .appFont(.system(size: 13.5).monospacedDigit())
                    .foregroundStyle(contact.dealValue > 0 ? Theme.text : Theme.tertiaryText)
                    .frame(width: 96, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .appFont(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
                    .opacity(isHovering || isSelected ? 1 : 0)
                    .frame(width: 24)
            }
            .fontRole(.data)
            .padding(.leading, 30)
            .padding(.trailing, 8)
            .frame(minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Theme.selection : (isHovering ? Theme.hover : .clear))
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 30)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .contextMenu {
            Menu("Move to") {
                ForEach(DealStage.allCases) { stage in
                    Button(stage.title, systemImage: stage.symbol) {
                        withMotion(.snappy) { WorkspaceActions(context: context).setStage(stage, for: contact) }
                    }
                    .disabled(stage == contact.stage)
                }
            }
            if !contact.email.isEmpty, let url = URL(string: "mailto:\(contact.email)") {
                Link(destination: url) { Label("Send email", systemImage: "envelope") }
            }
            Divider()
            Button("Delete customer…", systemImage: "trash", role: .destructive) {
                app.present(.deleteContact(contact.uuid))
            }
        }
    }

    private func cell(_ text: String, width: CGFloat) -> some View {
        Text(text.isEmpty ? "—" : text)
            .appFont(.system(size: 13.5))
            .foregroundStyle(text.isEmpty ? Theme.tertiaryText : Theme.secondaryText)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
    }

    private var accessibilityText: String {
        var parts = [contact.name]
        if !contact.company.isEmpty { parts.append(contact.company) }
        parts.append(contact.stage.title)
        if contact.dealValue > 0 { parts.append(CRMFormat.money(contact.dealValue)) }
        return parts.joined(separator: ", ")
    }
}

/// "⊕ Add customer" at the end of a group; becomes a field, Return creates the person
/// in that stage and keeps the field open for the next one, Esc closes it.
struct AddCustomerRow: View {
    @Environment(\.modelContext) private var context
    let stage: DealStage
    let created: (Contact) -> Void
    @State private var isEditing = false
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .appFont(.system(size: 15))
                .foregroundStyle(Theme.tertiaryText)
            if isEditing {
                TextField("Customer name", text: $name)
                    .textFieldStyle(.plain)
                    .appFont(.system(size: 14.5), role: .data)
                    .focused($focused)
                    .onSubmit(add)
                    .onKeyPress(.escape) { close(); return .handled }
                    .onChange(of: focused) { _, isFocused in if !isFocused { close() } }
            } else {
                Button("Add customer") {
                    isEditing = true
                    Task { await DialogTextField.claimFocus { focused = true } isFocused: { focused } }
                }
                .buttonStyle(.plain)
                .appFont(.system(size: 14.5))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityLabel("Add customer to \(stage.title)")
            }
            Spacer()
        }
        .padding(.leading, 34)
        .frame(minHeight: 40)
    }

    private func add() {
        let actions = WorkspaceActions(context: context)
        guard let contact = actions.createContact(name: name, stage: stage) else { return }
        actions.save()
        name = ""
        created(contact)
        focused = true
    }

    private func close() {
        name = ""
        isEditing = false
    }
}

// MARK: - Pipeline board

struct PipelineBoard: View {
    @Environment(\.modelContext) private var context
    let contacts: [Contact]
    @Binding var selection: UUID?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(DealStage.allCases) { stage in
                    column(stage)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
    }

    private func column(_ stage: DealStage) -> some View {
        let people = contacts.filter { $0.stage == stage }
        let total = people.reduce(0) { $0 + $1.dealValue }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StagePill(stage: stage, compact: true)
                Text("\(people.count)").appFont(.caption.weight(.medium)).foregroundStyle(Theme.secondaryText)
                Spacer()
                if total > 0 {
                    Text(CRMFormat.money(total)).appFont(.caption, role: .data).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 2)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(people) { contact in
                        PipelineCard(contact: contact, isSelected: selection == contact.uuid) {
                            selection = selection == contact.uuid ? nil : contact.uuid
                        }
                        .draggable(contact.uuid.uuidString)
                    }
                    if people.isEmpty {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [4]))
                            .frame(minHeight: 64)
                            .overlay { Text("Drop here").appFont(.caption).foregroundStyle(Theme.tertiaryText) }
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 240)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke) }
        .dropDestination(for: String.self) { ids, _ in
            let uuids = Set(ids.compactMap(UUID.init(uuidString:)))
            for contact in contacts where uuids.contains(contact.uuid) {
                withMotion(.snappy) { WorkspaceActions(context: context).setStage(stage, for: contact) }
            }
            return true
        }
    }
}

struct PipelineCard: View {
    let contact: Contact
    let isSelected: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    AvatarView(name: contact.name, color: contact.color.color, imageData: contact.imageData, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(contact.name).appFont(.subheadline.weight(.medium)).foregroundStyle(Theme.text).lineLimit(1)
                        if !contact.company.isEmpty {
                            Text(contact.company).appFont(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if contact.dealValue > 0 {
                    Text(CRMFormat.money(contact.dealValue))
                        .appFont(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.text)
                }
            }
            .fontRole(.data)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Theme.stroke, lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel([contact.name, contact.company, contact.dealValue > 0 ? CRMFormat.money(contact.dealValue) : ""].filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

// MARK: - Shared bits

/// Tabs with an underline under the selected one, as in the reference view switcher.
struct UnderlineTabs<Tab: Hashable & Identifiable, Label: View>: View {
    @Binding var selection: Tab
    let tabs: [Tab]
    @ViewBuilder let label: (Tab) -> Label
    @Namespace private var underline

    var body: some View {
        HStack(spacing: 22) {
            ForEach(tabs) { tab in
                let isSelected = tab == selection
                Button {
                    withMotion(.snappy(duration: 0.22)) { selection = tab }
                } label: {
                    HStack(spacing: 7) { label(tab) }
                        .appFont(.system(size: 14.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Theme.text : Theme.secondaryText)
                        .padding(.bottom, 10)
                        .overlay(alignment: .bottom) {
                            if isSelected {
                                Capsule()
                                    .fill(Theme.text)
                                    .frame(height: 2.5)
                                    .matchedGeometryEffect(id: "underline", in: underline)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
            Spacer()
        }
    }
}

/// Small coloured square with a white symbol, for tab labels.
struct TabGlyph: View {
    let symbol: String
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(color)
            .frame(width: 20, height: 20)
            .overlay {
                Image(systemName: symbol)
                    .appFont(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

struct SearchPill: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .appFont(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryText)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .appFont(.system(size: 13.5))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(Theme.field, in: Capsule())
        .overlay { Capsule().strokeBorder(Theme.stroke) }
    }
}

struct StageChip: View {
    let stage: DealStage

    var body: some View {
        Text(stage.title)
            .appFont(.caption.weight(.medium))
            .foregroundStyle(stage.color.color)
            .padding(.horizontal, 8)
            .frame(minHeight: 22)
            .background(stage.color.color.opacity(0.14), in: Capsule())
    }
}

// MARK: - Detail panel

struct ContactInspector: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var app
    @Bindable var contact: Contact
    var close: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let close {
                    HStack {
                        Spacer()
                        Button(action: close) {
                            Image(systemName: "xmark")
                                .appFont(.system(size: 11, weight: .semibold))
                                .frame(width: 26, height: 26)
                                .contentShape(.rect)
                        }
                        .buttonStyle(QuietButtonStyle())
                        .keyboardShortcut(.cancelAction)
                        .help("Close")
                        .accessibilityLabel("Close details")
                    }
                    .padding(.bottom, -12)
                }
                VStack(spacing: 10) {
                    AvatarView(name: contact.name, color: contact.color.color, imageData: contact.imageData, size: 64)
                    Text(contact.name).appFont(.title3.weight(.semibold), role: .data).foregroundStyle(Theme.text)
                    if !contact.company.isEmpty {
                        Text(contact.company).appFont(.subheadline, role: .data).foregroundStyle(Theme.secondaryText)
                    }
                    StagePill(stage: contact.stage, compact: true)
                    if contact.appleContactIdentifier != nil {
                        Label("Linked to Apple Contacts", systemImage: "person.crop.circle.badge.checkmark")
                            .appFont(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    action("envelope", "Mail", url: contact.email.isEmpty ? nil : URL(string: "mailto:\(contact.email)"))
                    action("phone", "Call", url: contact.phone.isEmpty ? nil : URL(string: "tel:\(contact.phone.filter { !$0.isWhitespace })"))
                    action("video", "FaceTime", url: facetimeURL)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Stage").appFont(.caption).foregroundStyle(Theme.secondaryText).frame(width: 64, alignment: .leading)
                        Picker("Stage", selection: Binding(get: { contact.stage }, set: { WorkspaceActions(context: context).setStage($0, for: contact) })) {
                            ForEach(DealStage.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                    }
                    HStack {
                        Text("Value").appFont(.caption).foregroundStyle(Theme.secondaryText).frame(width: 64, alignment: .leading)
                        TextField("Deal value", value: Binding<Double?>(get: { contact.dealValue > 0 ? contact.dealValue : nil }, set: { WorkspaceActions(context: context).setDealValue($0 ?? 0, for: contact) }), format: .currency(code: CRMFormat.currencyCode).precision(.fractionLength(0)))
                            .textFieldStyle(.plain)
                            .appFont(.subheadline.monospacedDigit(), role: .data)
                    }
                    .padding(.vertical, 4)
                    .overlay(alignment: .bottom) { SidebarDivider() }
                    field("Title", $contact.jobTitle)
                    field("Company", $contact.company)
                    field("Email", $contact.email)
                    field("Phone", $contact.phone)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes").appFont(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                    TextField("Add notes", text: $contact.notes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .fontRole(.data)
                        .lineLimit(3...10)
                        .padding(10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke) }
                }

                Button(role: .destructive) {
                    app.present(.deleteContact(contact.uuid))
                } label: {
                    Label("Delete customer…", systemImage: "trash").foregroundStyle(.red)
                }
                .buttonStyle(QuietButtonStyle())
            }
            .padding(20)
        }
    }

    private var facetimeURL: URL? {
        let handle = contact.phone.isEmpty ? contact.email : contact.phone.filter { !$0.isWhitespace }
        return handle.isEmpty ? nil : URL(string: "facetime:\(handle)")
    }

    private func action(_ symbol: String, _ title: String, url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).appFont(.system(size: 15))
                Text(title).appFont(.caption2)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .foregroundStyle(url == nil ? Theme.tertiaryText : Theme.text)
            .glassSurface(.rect(cornerRadius: 12), interactive: url != nil)
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label).appFont(.caption).foregroundStyle(Theme.secondaryText).frame(width: 64, alignment: .leading)
            TextField(label, text: text).textFieldStyle(.plain).appFont(.subheadline, role: .data)
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { SidebarDivider() }
    }
}

// MARK: - Reports

struct ReportsView: View {
    @Query private var tasks: [TaskItem]
    @Query(sort: \Project.sortIndex) private var projects: [Project]
    @Query private var contacts: [Contact]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "Reports", subtitle: "Computed on-device from your iCloud data")
                HStack(alignment: .top, spacing: 16) {
                    Card {
                        Text("Tasks by status").appFont(.headline).foregroundStyle(Theme.text)
                        RingBreakdown(slices: TaskStatus.allCases.map { status in
                            .init(label: status.title, value: Double(tasks.filter { $0.status == status }.count))
                        }, thickness: 26)
                    }
                    Card {
                        Text("Pipeline by stage").appFont(.headline).foregroundStyle(Theme.text)
                        RingBreakdown(slices: DealStage.allCases.map { stage in
                            .init(label: stage.title, value: Double(contacts.filter { $0.stage == stage }.count), color: stage.color.color)
                        }, thickness: 26)
                    }
                }
                Card {
                    Text("Open work per project").appFont(.headline).foregroundStyle(Theme.text)
                    RingBreakdown(slices: projects.map { project in
                        .init(label: project.name, value: Double(project.openTaskCount), color: project.color.color)
                    }, thickness: 26)
                }
            }
            .padding(28)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .navigationTitle("Reports")
    }
}
