//
//  WorkspaceComponents.swift
//  Colony
//
//  Created by Yoav Peretz on 17/06/2026.
//

import SwiftUI

struct ContentGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(.title, design: .rounded, weight: .semibold))
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ChannelRow: View {
    let channel: ColonyChannel
    var isSelected = false
    var accentColor: Color = .blue

    private var latestMessage: ColonyMessage? {
        channel.messages.last
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? accentColor.gradient : Color.secondary.opacity(0.18).gradient)
                    .frame(width: 34, height: 34)
                    .overlay {
                        if channel.kind == .directMessage {
                            Text(channelInitials)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(isSelected ? .white : .secondary)
                        } else {
                            Image(systemName: "number")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(isSelected ? .white : .secondary)
                        }
                    }

                if channel.unreadCount > 0 {
                    Circle()
                        .fill(.green)
                        .frame(width: 9, height: 9)
                        .overlay {
                            Circle().stroke(.background, lineWidth: 1.5)
                        }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(channel.name)
                        .font(.subheadline.weight(channel.unreadCount > 0 ? .semibold : .medium))
                        .lineLimit(1)

                    if channel.name == "founders" {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(latestMessageSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if channel.unreadCount > 0 {
                Text("\(channel.unreadCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(accentColor, in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    private var latestMessageSummary: String {
        guard let latestMessage else {
            return channel.description
        }

        return "\(latestMessage.author): \(latestMessage.body)"
    }

    private var channelInitials: String {
        let initials = channel.name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()

        return initials.isEmpty ? "?" : initials.uppercased()
    }
}

struct MessageRow: View {
    let message: ColonyMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(message.authorColor.color)
                .frame(width: 34, height: 34)
                .overlay {
                    Text(String(message.author.prefix(1)))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(message.author)
                        .font(.subheadline.weight(.semibold))
                    Text(message.time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(message.body)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct TaskRow: View {
    let task: ColonyTask

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: task.status.systemImage)
                .foregroundStyle(task.status.color)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                Text(task.owner)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(task.priority)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct TaskWorkflowRow: View {
    let task: ColonyTask
    let updateStatus: (TaskStatus) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: task.status.systemImage)
                .foregroundStyle(task.status.color)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                Text("\(task.owner) · \(task.priority)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Status", selection: statusBinding) {
                ForEach(TaskStatus.allCases) { status in
                    Text(status.title).tag(status)
                }
            }
            .labelsHidden()
            .frame(width: 110)
        }
    }

    private var statusBinding: Binding<TaskStatus> {
        Binding(
            get: { task.status },
            set: { updateStatus($0) }
        )
    }
}

struct ContactRow: View {
    let contact: ColonyContact

    var body: some View {
        HStack(spacing: 12) {
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
                Text("\(contact.company) · \(contact.stage)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

struct ContactPipelineRow: View {
    let contact: ColonyContact
    let updateStage: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
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
                Text(contact.company)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Stage", selection: stageBinding) {
                ForEach(WorkspaceStore.contactStages, id: \.self) { stage in
                    Text(stage).tag(stage)
                }
            }
            .labelsHidden()
            .frame(width: 150)
        }
    }

    private var stageBinding: Binding<String> {
        Binding(
            get: { contact.stage },
            set: { updateStage($0) }
        )
    }
}

struct UpdateRow: View {
    let update: ColonyUpdate

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: update.systemImage)
                .foregroundStyle(update.color.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(update.title)
                    .font(.subheadline.weight(.semibold))
                Text(update.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SettingsCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ProviderRow: View {
    let provider: AuthProvider

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: provider.kind.systemImage)
                .foregroundStyle(provider.status == .enabled ? .green : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(provider.kind.title)
                        .font(.subheadline.weight(.semibold))

                    Text(provider.status.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(provider.status == .enabled ? .green : .secondary)
                }

                Text(provider.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ThemeSwatchPicker: View {
    @Binding var selectedTheme: ColonyTheme

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ColonyTheme.allCases) { theme in
                Button {
                    selectedTheme = theme
                } label: {
                    VStack(spacing: 8) {
                        Circle()
                            .fill(theme.accentColor)
                            .frame(width: 24, height: 24)
                            .overlay {
                                if selectedTheme == theme {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }

                        Text(theme.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selectedTheme == theme ? theme.accentColor.opacity(0.16) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use \(theme.title) theme")
            }
        }
    }
}

struct AppearancePreview: View {
    let theme: ColonyTheme
    let preferences: AppearancePreferences

    var body: some View {
        VStack(alignment: .leading, spacing: previewSpacing) {
            HStack {
                Label("Product", systemImage: "number")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(preferences.density.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accentColor)
            }

            Text("Theme and density changes update the workspace immediately and persist for the next launch.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Capsule()
                    .fill(accentStyle)
                    .frame(width: 54, height: preferences.usesHighContrastAccents ? 10 : 7)
                Capsule()
                    .fill(theme.accentColor.opacity(0.32))
                    .frame(width: 34, height: preferences.usesHighContrastAccents ? 10 : 7)
                Capsule()
                    .fill(.secondary.opacity(0.22))
                    .frame(width: 44, height: preferences.usesHighContrastAccents ? 10 : 7)
            }
        }
        .padding(previewPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var accentStyle: Color {
        preferences.usesHighContrastAccents ? theme.accentColor : theme.accentColor.opacity(0.72)
    }

    private var previewSpacing: CGFloat {
        switch preferences.density {
        case .compact: 8
        case .comfortable: 12
        case .spacious: 16
        }
    }

    private var previewPadding: CGFloat {
        switch preferences.density {
        case .compact: 12
        case .comfortable: 16
        case .spacious: 20
        }
    }
}

struct ProviderControlRow: View {
    @Binding var provider: AuthProvider

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: provider.kind.systemImage)
                .foregroundStyle(provider.status == .enabled ? .green : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(provider.kind.title)
                    .font(.subheadline.weight(.semibold))

                Text(provider.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Picker("Status", selection: $provider.status) {
                ForEach(AuthProviderStatus.allCases) { status in
                    Text(status.title).tag(status)
                }
            }
            .labelsHidden()
            .frame(width: 120)
        }
    }
}

struct PolicyRow: View {
    let title: String
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isEnabled ? .green : .secondary)

            Text(title)
                .font(.subheadline)

            Spacer()

            Text(isEnabled ? "On" : "Off")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct PolicyToggleRow: View {
    let title: String
    let detail: String
    @Binding var isEnabled: Bool

    var body: some View {
        Toggle(isOn: $isEnabled) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
    }
}

struct SettingsChecklistRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct MemberRow: View {
    let member: WorkspaceMember

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(member.color.color.gradient)
                .frame(width: 36, height: 36)
                .overlay {
                    Text(member.initials)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(member.name)
                    .font(.subheadline.weight(.semibold))
                Text(member.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(member.role.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct InviteRow: View {
    let invite: PendingInvite

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.badge")
                .foregroundStyle(.orange)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(invite.email)
                    .font(.subheadline.weight(.semibold))
                Text("Pending invite")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(invite.role.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
