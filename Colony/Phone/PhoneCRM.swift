//
//  PhoneCRM.swift
//  Colony
//
//  Customers on iPhone: a large title, Customers / Pipeline segments, stage sections
//  headed by a coloured dot and count, Contacts-style rows, swipe actions, and the
//  customer's details pushed full screen.
//

#if os(iOS)
import SwiftData
import SwiftUI

struct PhoneCRM: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneNavigator.self) private var nav
    @Environment(\.modelContext) private var context
    @Query(sort: \Contact.name) private var contactsEverywhere: [Contact]
    @State private var mode = 0
    @State private var query = ""

    var body: some View {
        let all = contactsEverywhere.inWorkspace()
        let q = ColonyText.trimmed(query).lowercased()
        let contacts = q.isEmpty ? all : all.filter { ($0.name + " " + $0.company).lowercased().contains(q) }

        List {
            Section {
                Picker("View", selection: $mode) {
                    Text("Customers").tag(0)
                    Text("Pipeline").tag(1)
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if all.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No customers yet", systemImage: "person.2")
                    } description: {
                        Text("Add one with +, or import from Contacts.")
                    } actions: {
                        Button("Import from Contacts") { app.present(.importContacts) }
                            .buttonStyle(.glass)
                    }
                }
                .listRowBackground(Color.clear)
            } else if mode == 0 {
                ForEach(DealStage.allCases) { stage in
                    let group = contacts.filter { $0.stage == stage }
                    if !group.isEmpty {
                        Section {
                            ForEach(group) { contact in PhoneCustomerRow(contact: contact) }
                        } header: {
                            PhoneStageHeader(stage: stage, count: group.count, total: group.reduce(0) { $0 + $1.dealValue })
                        }
                    }
                }
            } else {
                Section {
                    ForEach(DealStage.allCases) { stage in
                        let group = all.filter { $0.stage == stage }
                        PhonePipelineRow(stage: stage, count: group.count, total: group.reduce(0) { $0 + $1.dealValue }, largest: all.filter { $0.stage == stage }.count, of: max(all.count, 1))
                    }
                } footer: {
                    let open = all.filter { $0.stage.isOpen }.reduce(0) { $0 + $1.dealValue }
                    Text("\(PhoneToday.money(open)) open across \(all.filter { $0.stage.isOpen }.count) customers.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Phone.canvas)
        .navigationTitle("Customers")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Name or company")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New Customer", systemImage: "person.badge.plus") { app.present(.newContact) }
                    Button("Import from Contacts", systemImage: "person.crop.circle.badge.plus") { app.present(.importContacts) }
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add customer")
            }
        }
    }
}

private struct PhoneStageHeader: View {
    let stage: DealStage
    let count: Int
    let total: Double

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(stage.color.color).frame(width: 9, height: 9)
            Text(stage.title).appFont(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Color.primary)
            Text("\(count)").appFont(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
            Spacer()
            if total > 0 {
                Text(PhoneToday.money(total)).appFont(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .padding(.leading, -16)
        .accessibilityElement(children: .combine)
    }
}

private struct PhoneCustomerRow: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneNavigator.self) private var nav
    @Environment(\.modelContext) private var context
    let contact: Contact

    var body: some View {
        Button { nav.push(.contact(contact.uuid)) } label: {
            HStack(spacing: 12) {
                CustomerAvatar(contact: contact, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(contact.name).appFont(.system(size: 17, weight: .semibold)).foregroundStyle(.primary)
                    let line = [contact.company, contact.jobTitle].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !line.isEmpty {
                        Text(line).appFont(.system(size: 15)).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 6)
                if contact.dealValue > 0 {
                    Text(PhoneToday.money(contact.dealValue)).appFont(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").appFont(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            if let next = contact.stage.next {
                Button(next.title, systemImage: "arrow.right") { WorkspaceActions(context: context).setStage(next, for: contact) }
                    .tint(next.color.color)
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) { app.present(.deleteContact(contact.uuid)) }
        }
        .contextMenu {
            Picker("Stage", selection: Binding(get: { contact.stage }, set: { WorkspaceActions(context: context).setStage($0, for: contact) })) {
                ForEach(DealStage.allCases) { Text($0.title).tag($0) }
            }
            if !contact.phone.isEmpty, let url = URL(string: "tel:\(contact.phone.filter { $0.isNumber || $0 == "+" })") {
                Link(destination: url) { Label("Call", systemImage: "phone") }
            }
            if !contact.email.isEmpty, let url = URL(string: "mailto:\(contact.email)") {
                Link(destination: url) { Label("Email", systemImage: "envelope") }
            }
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive) { app.present(.deleteContact(contact.uuid)) }
        }
    }
}

struct CustomerAvatar: View {
    let contact: Contact
    var size: CGFloat = 40

    var body: some View {
        Text(contact.initials)
            .appFont(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.2), tint], startPoint: .top, endPoint: .bottom)))
            .accessibilityHidden(true)
    }

    /// The stored colour, or one picked from the name when it's still the default,
    /// so neighbouring customers don't all look the same.
    private var tint: Color {
        guard contact.color == .indigo else { return contact.color.color }
        let palette: [ColonyColor] = [.blue, .indigo, .purple, .pink, .orange, .teal, .green]
        let seed = contact.name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[seed % palette.count].color
    }
}

private struct PhonePipelineRow: View {
    let stage: DealStage
    let count: Int
    let total: Double
    let largest: Int
    let of: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(stage.color.color).frame(width: 10, height: 10)
                Text(stage.title).appFont(.system(size: 17, weight: .semibold))
                Spacer()
                Text(total > 0 ? PhoneToday.money(total) : "\(count)").appFont(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(count == 0 ? .secondary : .primary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Phone.well)
                    Capsule().fill(stage.color.color.gradient)
                        .frame(width: count == 0 ? 0 : max(10, proxy.size.width * Double(count) / Double(of)))
                }
            }
            .frame(height: 8)
            Text("\(count) customer\(count == 1 ? "" : "s")").appFont(.system(size: 14)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// A customer's details, pushed full screen.
struct PhoneContactPage: View {
    @Bindable var contact: Contact

    var body: some View {
        PhoneContactDetail(contact: contact)
    }
}

extension DealStage {
    /// The stage a swipe moves a customer to.
    var next: DealStage? {
        switch self {
        case .lead: .qualified
        case .qualified: .proposal
        case .proposal: .negotiation
        case .negotiation: .won
        case .won, .lost: nil
        }
    }
}
#endif
