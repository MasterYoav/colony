//
//  RecruitAgentDialog.swift
//  Colony
//
//  Recruiting an agent means giving Colony an AGENT.md file. Three ways in: import a
//  file (picker or drag and drop), start from a template, or write one here. Whatever
//  the source, the dialog shows the agent the file describes — name, face, tools,
//  schedule — and any problems, before it joins. The same dialog edits an existing
//  agent's AGENT.md.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct RecruitAgentDialog: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dialogDismiss) private var dismiss
    /// nil: recruit a new agent. Otherwise: edit this agent's AGENT.md.
    let editing: UUID?

    enum Source: String, CaseIterable, Identifiable {
        case file = "Import"
        case template = "Templates"
        case write = "Write"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .file: "square.and.arrow.down"
            case .template: "square.grid.2x2"
            case .write: "pencil.line"
            }
        }
    }

    @State private var source: Source = .file
    @State private var markdown = ""
    @State private var fileName: String?
    @State private var templateID: String?
    @State private var isImporting = false
    @State private var isTargeted = false
    @State private var importError: String?
    @State private var didLoad = false

    private var existing: Agent? { editing.flatMap { context.agent($0) } }

    private var parsed: Result<AgentDefinition, Error>? {
        guard !ColonyText.trimmed(markdown).isEmpty else { return nil }
        let fallback = fileName.map { ($0 as NSString).deletingPathExtension }.flatMap { $0.uppercased() == "AGENT" ? nil : $0 }
        return Result { try AgentDefinition.parse(markdown, fallbackName: fallback) }
    }

    private var definition: AgentDefinition? {
        if case .success(let value) = parsed { return value }
        return nil
    }

    var body: some View {
        DialogFrame(
            symbol: editing == nil ? "person.badge.plus" : "doc.text",
            tint: definition?.color.color ?? ColonyColor.blue.color,
            title: editing == nil ? "Recruit an agent" : "Edit \(existing?.name ?? "agent")",
            description: editing == nil
                ? "Agents are described by an AGENT.md file: a name and settings at the top, then plain-language instructions. They run on this device with Apple Intelligence."
                : "Change the agent's AGENT.md. Its conversation is kept."
        ) {
            if editing == nil {
                Picker("Source", selection: $source) {
                    ForEach(Source.allCases) { item in
                        Label(item.rawValue, systemImage: item.symbol).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Source")
            }

            switch editing == nil ? source : .write {
            case .file: importPane
            case .template: templatePane
            case .write: editorPane
            }

            preview
        } footer: {
            KeyHint(keys: ["⌘", "⏎"], label: editing == nil ? "recruit" : "save")
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.dialogGhost)
            Button(editing == nil ? "Recruit \(definition?.name ?? "agent")" : "Save", action: commit)
                .buttonStyle(.dialogPrimary)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(definition == nil)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: Self.fileTypes) { result in
            switch result {
            case .success(let url): load(url)
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .onAppear(perform: loadExisting)
    }

    static let fileTypes: [UTType] = [UTType(filenameExtension: "md") ?? .plainText, .plainText, .text]

    // MARK: Panes

    private var importPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { isImporting = true } label: {
                VStack(spacing: 8) {
                    Image(systemName: fileName == nil ? "doc.badge.plus" : "doc.text.fill")
                        .appFont(.system(size: 22, weight: .regular))
                        .foregroundStyle(isTargeted ? ColonyColor.blue.color : Theme.secondaryText)
                    Text(fileName ?? "Drop an AGENT.md file here")
                        .appFont(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Text(fileName == nil ? "or click to choose a Markdown file" : "Click to choose a different file")
                        .appFont(.system(size: 11.5))
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(isTargeted ? ColonyColor.blue.color.opacity(0.08) : Theme.surface.opacity(0.6), in: .rect(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isTargeted ? ColonyColor.blue.color : Theme.strongStroke, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(fileName.map { "Chosen file \($0). Choose a different AGENT.md file" } ?? "Choose an AGENT.md file")
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                load(url)
                return true
            } isTargeted: { isTargeted = $0 }

            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle.fill")
                    .appFont(.system(size: 12))
                    .foregroundStyle(ColonyColor.red.color)
            }
            if fileName != nil {
                DisclosureGroup("Show file") {
                    DialogTextEditor(placeholder: "AGENT.md", text: $markdown, lines: 6...14)
                        .fontDesign(.monospaced)
                        .padding(.top, 6)
                }
                .appFont(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            } else {
                Text("Where to find one: write it in any editor, or save one from another Colony agent with Export AGENT.md. See the format in Help › Agents.")
                    .appFont(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var templatePane: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], spacing: 8) {
            ForEach(AgentTemplates.all) { template in
                let selected = templateID == template.id
                let definition = try? AgentDefinition.parse(template.markdown)
                Button {
                    templateID = template.id
                    fileName = nil
                    markdown = template.markdown
                } label: {
                    HStack(spacing: 10) {
                        AgentFace(color: (definition?.color ?? .gray).color, size: 28, seed: template.id.count)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(template.title)
                                .appFont(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text(definition?.summary ?? "")
                                .appFont(.system(size: 11))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    .background(selected ? (definition?.color ?? .blue).color.opacity(0.12) : Theme.surface, in: .rect(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? (definition?.color ?? .blue).color : Theme.stroke, lineWidth: selected ? 1.5 : 1)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(template.title)
                .accessibilityHint(definition?.summary ?? "")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var editorPane: some View {
        DialogField(label: "AGENT.md", hint: "Settings between the --- lines: name, description, color, tools, schedule, prompts. Everything below is the agent's instructions.") {
            DialogTextEditor(placeholder: "---\nname: …\n---\n\nWhat the agent should do…", text: $markdown, lines: 10...18)
                .fontDesign(.monospaced)
        } accessory: {
            if editing == nil, markdown.isEmpty {
                Button("Start from blank") { markdown = AgentTemplates.blank.markdown }
                    .buttonStyle(.plain)
                    .appFont(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(ColonyColor.blue.color)
            }
        }
    }

    // MARK: Preview

    @ViewBuilder
    private var preview: some View {
        switch parsed {
        case .none:
            EmptyView()
        case .failure(let error):
            Label(error.localizedDescription, systemImage: "xmark.octagon.fill")
                .appFont(.system(size: 12.5))
                .foregroundStyle(ColonyColor.red.color)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ColonyColor.red.color.opacity(0.08), in: .rect(cornerRadius: 10, style: .continuous))
        case .success(let definition):
            AgentCard(definition: definition)
            ForEach(definition.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .appFont(.system(size: 12))
                    .foregroundStyle(ColonyColor.orange.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Actions

    private func loadExisting() {
        guard !didLoad else { return }
        didLoad = true
        if let existing {
            markdown = existing.definition.markdown
            source = .write
        }
    }

    private func load(_ url: URL) {
        importError = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard data.count < 200_000 else {
                importError = "That file is too big for an AGENT.md (over 200 KB)."
                return
            }
            guard let text = String(data: data, encoding: .utf8) else {
                importError = "That file isn't text. Choose a Markdown (.md) file."
                return
            }
            markdown = text
            fileName = url.lastPathComponent
            templateID = nil
        } catch {
            importError = "Couldn't open the file: \(error.localizedDescription)"
        }
    }

    private func commit() {
        guard let definition else { return }
        let actions = WorkspaceActions(context: context)
        if let existing {
            actions.update(existing, with: definition)
            app.agents.forget(existing)
            app.show("\(definition.name) updated")
        } else if let agent = actions.recruit(definition) {
            app.go(.agent(agent.uuid))
            app.show("\(agent.name) joined", detail: definition.schedule.map { "Runs \($0.label.lowercased())" } ?? "Ask them anything")
        }
        actions.save()
        dismiss()
    }
}

/// What an AGENT.md describes, as a card: face, name, summary, tools, schedule.
struct AgentCard: View {
    let definition: AgentDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AgentFace(color: definition.color.color, size: 42, seed: definition.name.count)
                VStack(alignment: .leading, spacing: 2) {
                    Text(definition.name)
                        .appFont(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(definition.summary.isEmpty ? "No description" : definition.summary)
                        .appFont(.system(size: 12.5))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            FlowRow(spacing: 6) {
                ForEach(definition.tools) { tool in
                    Label(tool.title, systemImage: tool.symbol)
                        .appFont(.system(size: 11, weight: .medium))
                        .foregroundStyle(tool.writes ? definition.color.color : Theme.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((tool.writes ? definition.color.color : Theme.text).opacity(0.08), in: Capsule())
                }
                if definition.tools.isEmpty {
                    Text("No tools: chat only")
                        .appFont(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }

            HStack(spacing: 14) {
                Label(definition.schedule?.label ?? "Runs when you ask", systemImage: definition.schedule == nil ? "hand.tap" : "clock")
                Label("\(definition.instructions.split(separator: "\n").count) lines of instructions", systemImage: "text.alignleft")
            }
            .appFont(.system(size: 11.5))
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke) }
        .accessibilityElement(children: .combine)
    }
}

/// Wraps chips onto new lines.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * spacing
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].indices.isEmpty
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += isFirst ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

struct DeleteAgentDialog: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let agentID: UUID

    var body: some View {
        let agent = context.agent(agentID)
        ConfirmDialog(
            symbol: "person.badge.minus",
            title: "Remove \(agent?.name ?? "this agent")?",
            message: "The agent and its conversation are removed from all your devices. Tasks and updates it made stay. Export its AGENT.md first if you might want it back.",
            confirmTitle: "Remove agent"
        ) {
            guard let agent else { return }
            app.agents.forget(agent)
            if app.destination == .agent(agentID) { app.go(.crew(.agents)) }
            WorkspaceActions(context: context).delete(agent)
        }
    }
}
