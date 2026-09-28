//
//  HomeDashboardView.swift
//  Colony
//
//  Created by Yoav Peretz on 18/06/2026.
//

import SwiftUI

struct HomeOverview: View {
    let store: WorkspaceStore
    let create: (WorkspaceCreationSheet) -> Void

    var body: some View {
        HomeQuickCreatePanel(accentColor: store.selectedTheme.accentColor, create: create)

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
            MetricCard(title: "Active channels", value: "\(store.activeChannelCount)", systemImage: "bubble.left.and.bubble.right", color: store.selectedTheme.accentColor)
            MetricCard(title: "Open tasks", value: "\(store.openTaskCount)", systemImage: "checklist", color: .green)
            MetricCard(title: "CRM records", value: "\(store.crmRecordCount)", systemImage: "person.crop.rectangle.stack", color: .orange)
            MetricCard(title: "SSO providers", value: "\(store.ssoProviderCount)", systemImage: "lock.shield", color: .purple)
        }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
            HomePriorityWorkCard(tasks: priorityTasks, accentColor: store.selectedTheme.accentColor)
            HomePipelineSnapshotCard(contacts: store.contacts)
        }

        ContentGroup(title: "Recent activity") {
            ForEach(store.updates) { update in
                UpdateRow(update: update)
                if update.id != store.updates.last?.id {
                    Divider()
                }
            }
        }
    }

    private var priorityTasks: [ColonyTask] {
        store.tasks
            .filter { $0.status != .review }
            .sorted { lhs, rhs in
                priorityRank(lhs.priority) > priorityRank(rhs.priority)
            }
    }

    private func priorityRank(_ priority: String) -> Int {
        switch priority {
        case "High":
            return 3
        case "Medium":
            return 2
        default:
            return 1
        }
    }
}

private struct HomeQuickCreatePanel: View {
    let accentColor: Color
    let create: (WorkspaceCreationSheet) -> Void

    var body: some View {
        ContentGroup(title: "Create") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                HomeQuickCreateButton(title: "Update", systemImage: "doc.text", color: accentColor) {
                    create(.update)
                }

                HomeQuickCreateButton(title: "Channel", systemImage: "number", color: .blue) {
                    create(.channel)
                }

                HomeQuickCreateButton(title: "Task", systemImage: "checkmark.circle", color: .green) {
                    create(.task(nil))
                }

                HomeQuickCreateButton(title: "Contact", systemImage: "person.badge.plus", color: .orange) {
                    create(.contact)
                }

                HomeQuickCreateButton(title: "Invite", systemImage: "person.2.badge.plus", color: .purple) {
                    create(.invite)
                }
            }
        }
    }
}

private struct HomeQuickCreateButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct HomePriorityWorkCard: View {
    let tasks: [ColonyTask]
    let accentColor: Color

    var body: some View {
        ContentGroup(title: "Priority work") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(tasks.prefix(4)) { task in
                    HomePriorityTaskRow(task: task, accentColor: accentColor)
                    if task.id != tasks.prefix(4).last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct HomePriorityTaskRow: View {
    let task: ColonyTask
    let accentColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: task.status.systemImage)
                .foregroundStyle(task.status == .active ? accentColor : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text("\(task.category) · \(task.owner)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(task.priority)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(priorityColor)

                Text(task.dueDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var priorityColor: Color {
        task.priority == "High" ? .orange : .secondary
    }
}

private struct HomePipelineSnapshotCard: View {
    let contacts: [ColonyContact]

    var body: some View {
        ContentGroup(title: "Pipeline snapshot") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(WorkspaceStore.contactStages, id: \.self) { stage in
                    HomePipelineStageRow(
                        stage: stage,
                        count: contacts.filter { $0.stage == stage }.count,
                        totalCount: contacts.count,
                        color: color(for: stage)
                    )

                    if stage != WorkspaceStore.contactStages.last {
                        Divider()
                    }
                }
            }
        }
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
            return .secondary
        }
    }
}

private struct HomePipelineStageRow: View {
    let stage: String
    let count: Int
    let totalCount: Int
    let color: Color

    private var progress: Double {
        guard totalCount > 0 else {
            return 0
        }

        return Double(count) / Double(totalCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(stage)
                    .font(.caption.weight(.semibold))

                Spacer()

                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.secondary.opacity(0.14))

                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 7)
        }
    }
}
