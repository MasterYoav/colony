//
//  CRMDetailView.swift
//  Colony
//
//  Created by Yoav Peretz on 18/06/2026.
//

import SwiftUI

struct CRMOverview: View {
    @Binding var store: WorkspaceStore
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CRMPipelineHeader(
                searchText: $searchText,
                contactCount: filteredContacts.count,
                stageCount: WorkspaceStore.contactStages.count
            )

            HStack(alignment: .top, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(WorkspaceStore.contactStages, id: \.self) { stage in
                            let stageContacts = filteredContacts.filter { $0.stage == stage }

                            CRMStageColumn(
                                stage: stage,
                                contacts: stageContacts,
                                selectedContactID: selectedContact?.id,
                                accentColor: color(for: stage)
                            ) { contactID in
                                store.selectedContactID = contactID
                            } updateStage: { contactID, newStage in
                                store.updateContactStage(contactID: contactID, stage: newStage)
                            }
                            .frame(width: 220)
                        }
                    }
                    .padding(.bottom, 2)
                }

                if let selectedContact {
                    CRMAccountDetailPanel(
                        contact: selectedContact,
                        accentColor: color(for: selectedContact.stage)
                    ) { newStage in
                        store.updateContactStage(contactID: selectedContact.id, stage: newStage)
                    }
                    .frame(width: 280)
                }
            }
        }
    }

    private var filteredContacts: [ColonyContact] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return store.contacts
        }

        return store.contacts.filter { contact in
            contact.name.localizedCaseInsensitiveContains(query)
            || contact.company.localizedCaseInsensitiveContains(query)
            || contact.stage.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedContact: ColonyContact? {
        if let selectedContactID = store.selectedContactID,
           let contact = filteredContacts.first(where: { $0.id == selectedContactID }) {
            return contact
        }

        return filteredContacts.first
    }

    private func color(for stage: String) -> Color {
        switch stage {
        case "Discovery":
            return .blue
        case "Pilot":
            return .green
        case "Proposal":
            return .orange
        case "Security review":
            return .purple
        case "Customer":
            return .cyan
        default:
            return store.selectedTheme.accentColor
        }
    }
}

private struct CRMPipelineHeader: View {
    @Binding var searchText: String
    let contactCount: Int
    let stageCount: Int

    var body: some View {
        ContentGroup(title: "Pipeline") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    CRMMetricPill(value: "\(contactCount)", label: "Accounts", systemImage: "person.crop.rectangle.stack", color: .blue)
                    CRMMetricPill(value: "\(stageCount)", label: "Stages", systemImage: "rectangle.3.group", color: .green)
                    CRMMetricPill(value: "SSO", label: "Enterprise-ready", systemImage: "lock.shield", color: .purple)

                    Spacer()
                }

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search accounts, companies, or stages", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.separator.opacity(0.55), lineWidth: 1)
                }
            }
        }
    }
}

private struct CRMMetricPill: View {
    let value: String
    let label: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CRMStageColumn: View {
    let stage: String
    let contacts: [ColonyContact]
    let selectedContactID: ColonyContact.ID?
    let accentColor: Color
    let selectContact: (ColonyContact.ID) -> Void
    let updateStage: (ColonyContact.ID, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 8, height: 8)

                Text(stage)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Text("\(contacts.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: Capsule())
            }

            VStack(spacing: 10) {
                if contacts.isEmpty {
                    CRMEmptyStageCard()
                } else {
                    ForEach(contacts) { contact in
                        CRMContactCard(
                            contact: contact,
                            isSelected: contact.id == selectedContactID,
                            accentColor: accentColor
                        ) {
                            selectContact(contact.id)
                        } updateStage: { newStage in
                            updateStage(contact.id, newStage)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
    }
}

private struct CRMContactCard: View {
    let contact: ColonyContact
    let isSelected: Bool
    let accentColor: Color
    let select: () -> Void
    let updateStage: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(contact.color.color.gradient)
                    .frame(width: 38, height: 38)
                    .overlay {
                        Text(contact.initials)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(contact.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text(contact.company)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Label("2 tasks", systemImage: "checklist")
                Label("1 note", systemImage: "doc.text")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)

            Picker("Stage", selection: stageBinding) {
                ForEach(WorkspaceStore.contactStages, id: \.self) { stage in
                    Text(stage).tag(stage)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(12)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(cardBorderColor, lineWidth: isSelected ? 1.5 : 1)
        }
        .onTapGesture(perform: select)
    }

    private var stageBinding: Binding<String> {
        Binding(
            get: { contact.stage },
            set: { updateStage($0) }
        )
    }

    private var cardBorderColor: Color {
        isSelected ? accentColor.opacity(0.9) : Color.secondary.opacity(0.22)
    }
}

private struct CRMEmptyStageCard: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("No accounts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4]))
        }
    }
}

private struct CRMAccountDetailPanel: View {
    let contact: ColonyContact
    let accentColor: Color
    let updateStage: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(contact.color.color.gradient)
                    .frame(width: 46, height: 46)
                    .overlay {
                        Text(contact.initials)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(contact.name)
                        .font(.headline)
                        .lineLimit(1)

                    Text(contact.company)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Picker("Stage", selection: stageBinding) {
                ForEach(WorkspaceStore.contactStages, id: \.self) { stage in
                    Text(stage).tag(stage)
                }
            }
            .pickerStyle(.menu)

            VStack(spacing: 10) {
                CRMDetailRow(title: "Next step", detail: nextStep, systemImage: "arrow.forward.circle", color: accentColor)
                CRMDetailRow(title: "Linked tasks", detail: "2 open follow-ups", systemImage: "checklist", color: .green)
                CRMDetailRow(title: "Last activity", detail: "Security review note added today", systemImage: "clock", color: .orange)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Account notes")
                    .font(.subheadline.weight(.semibold))

                Text("Keep CRM context close to the conversation so sales, support, and product can move from account signal to execution without switching tools.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
            } label: {
                Label("Open full account", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
    }

    private var stageBinding: Binding<String> {
        Binding(
            get: { contact.stage },
            set: { updateStage($0) }
        )
    }

    private var nextStep: String {
        switch contact.stage {
        case "Discovery":
            return "Qualify workspace size and current tools"
        case "Pilot":
            return "Confirm pilot success criteria"
        case "Proposal":
            return "Send self-hosting and SSO scope"
        case "Security review":
            return "Answer identity and data residency questions"
        case "Customer":
            return "Schedule onboarding workspace review"
        default:
            return "Set the next account action"
        }
    }
}

private struct CRMDetailRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}
