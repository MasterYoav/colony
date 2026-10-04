//
//  AutomationViews.swift
//  Colony
//
//  Automations for beginners: a flow reads top to bottom like a sentence.
//
//    WHEN   something happens   (one trigger)
//    ONLY IF  it matches        (optional filters)
//    THEN   do this, then that  (one or more steps)
//
//  Blocks sit on a dotted canvas joined by a line, like n8n, but there's no wiring to
//  do: you pick a block and fill in the blanks right on it. The same flow is always
//  spelled out in plain English at the top, and Test shows what would happen, on a
//  real item, without changing anything.
//

import SwiftData
import SwiftUI

// MARK: - Home

struct AutomationsHome: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Automation.sortIndex) private var automationsEverywhere: [Automation]
    private var automations: [Automation] { automationsEverywhere.inWorkspace() }
    @Query private var projectsEverywhere: [Project]
    private var projects: [Project] { projectsEverywhere.inWorkspace() }
    @Query private var channelsEverywhere: [Channel]
    private var channels: [Channel] { channelsEverywhere.inWorkspace() }
    @Query private var agentsEverywhere: [Agent]
    private var agents: [Agent] { agentsEverywhere.inWorkspace() }

    private var names: AutomationNames {
        AutomationNames(
            projects: Dictionary(projects.map { ($0.uuid, $0.name) }, uniquingKeysWith: { a, _ in a }),
            channels: Dictionary(channels.map { ($0.uuid, $0.name) }, uniquingKeysWith: { a, _ in a }),
            agents: Dictionary(agents.map { ($0.uuid, $0.name) }, uniquingKeysWith: { a, _ in a })
        )
    }

    var body: some View {
        let names = names
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                if !automations.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "Your automations", detail: "\(automations.filter { $0.isEnabled && $0.isComplete }.count) on")
                        VStack(spacing: 0) {
                            ForEach(Array(automations.enumerated()), id: \.element.uuid) { index, automation in
                                if index > 0 { Divider().overlay(Theme.stroke) }
                                AutomationRow(automation: automation, names: names, seed: index)
                            }
                        }
                        .background(Theme.surface, in: .rect(cornerRadius: 12, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke) }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: automations.isEmpty ? "Start with a recipe" : "Recipes", detail: "Ready-made; change anything")
                    RecipeGrid { recipe in create(recipe) }
                }
                HowItWorks()
            }
            .padding(.horizontal, 28)
            .padding(.leading, app.preferences.isSidebarCollapsed && isMacPlatform ? 22 : 0)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.canvas)
        .navigationTitle("Automations")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Automations")
                    .appFont(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Let Colony do the busywork. Pick what starts it, then what should happen. No code, and nothing leaves your devices.")
                    .appFont(.system(size: 13.5))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: 560, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { app.present(.newAutomation) } label: {
                Label("New automation", systemImage: "plus")
            }
            .buttonStyle(.dialogPrimary)
            .help("Create an automation (⌥⌘A)")
        }
    }

    private func create(_ recipe: AutomationRecipe) {
        let automation = WorkspaceActions(context: context).createAutomation(from: recipe)
        try? context.save()
        app.go(.automation(automation.uuid))
    }
}

var isMacPlatform: Bool {
    #if os(macOS)
    true
    #else
    false
    #endif
}

private struct SectionTitle: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .appFont(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            if let detail {
                Text(detail)
                    .appFont(.system(size: 12))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

private struct AutomationRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let automation: Automation
    let names: AutomationNames
    let seed: Int
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Button { app.go(.automation(automation.uuid)) } label: {
                HStack(spacing: 12) {
                    AgentFace(color: automation.color.color, size: 34, isRound: false, seed: seed + 40)
                        .opacity(automation.isEnabled ? 1 : 0.5)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(automation.name)
                            .appFont(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text(automation.sentence(names))
                            .appFont(.system(size: 12.5))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text(lastRun)
                        .appFont(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(automation.name), \(automation.isEnabled ? "on" : "off")")
            .accessibilityHint(automation.sentence(names))
            Toggle("\(automation.name) on", isOn: Binding(get: { automation.isEnabled }, set: { WorkspaceActions(context: context).setEnabled($0, for: automation) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!automation.isComplete)
                .help(automation.isComplete ? (automation.isEnabled ? "Turn off" : "Turn on") : "Finish setting it up first")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(isHovering ? Theme.hover : .clear)
        .onHover { isHovering = $0 }
        .contextMenu { AutomationMenuItems(automation: automation) }
    }

    private var lastRun: String {
        if !automation.isComplete { return "Not set up" }
        guard let date = automation.lastRunAt else { return automation.isEnabled ? "Hasn't run yet" : "Off" }
        return "Ran " + date.formatted(.relative(presentation: .named))
    }
}

/// Shared by rows, the sidebar and the editor's menu.
struct AutomationMenuItems: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let automation: Automation

    var body: some View {
        Button("Open", systemImage: "arrow.up.forward.app") { app.go(.automation(automation.uuid)) }
        Button(automation.isEnabled ? "Turn Off" : "Turn On", systemImage: automation.isEnabled ? "pause.circle" : "play.circle") {
            WorkspaceActions(context: context).setEnabled(!automation.isEnabled, for: automation)
        }
        .disabled(!automation.isComplete)
        Button("Duplicate", systemImage: "plus.square.on.square") {
            let copy = WorkspaceActions(context: context).duplicate(automation)
            try? context.save()
            app.go(.automation(copy.uuid))
        }
        Divider()
        Button("Delete Automation…", systemImage: "trash", role: .destructive) { app.present(.deleteAutomation(automation.uuid)) }
    }
}

// MARK: - Recipes

struct RecipeGrid: View {
    var columns = 260.0
    let pick: (AutomationRecipe) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: columns), spacing: 12)], spacing: 12) {
            ForEach(AutomationRecipes.all) { recipe in
                RecipeCard(recipe: recipe) { pick(recipe) }
            }
        }
    }
}

private struct RecipeCard: View {
    let recipe: AutomationRecipe
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    BlockIcon(symbol: recipe.trigger.kind.symbol, color: recipe.trigger.kind.category.color, size: 26)
                    Image(systemName: "arrow.right")
                        .appFont(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Theme.tertiaryText)
                    ForEach(Array(recipe.steps(ModelContext.placeholder).prefix(3).enumerated()), id: \.offset) { _, step in
                        BlockIcon(symbol: step.kind.symbol, color: step.kind.category.color, size: 26)
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.name)
                        .appFont(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(recipe.pitch)
                        .appFont(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? Theme.raised : Theme.surface, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isHovering ? Theme.strongStroke : Theme.stroke) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Recipe: \(recipe.name)")
        .accessibilityHint(recipe.pitch)
    }
}

extension ModelContext {
    /// An empty in-memory context, for drawing recipe previews (steps that look up a
    /// channel or agent just find none).
    @MainActor static let placeholder = ModelContext(CloudStore.inMemoryContainer())
}

private struct HowItWorks: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            item(1, "When", "Pick what starts it: a new task, a deal that's won, a time of day…", .blue)
            item(2, "Only if", "Optional. Narrow it down: only in Sales, only urgent tasks…", .purple)
            item(3, "Then", "Add what should happen, one step after another.", .green)
        }
        .padding(16)
        .background(Theme.surface.opacity(0.6), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
        .accessibilityElement(children: .combine)
    }

    private func item(_ n: Int, _ title: String, _ text: String, _ color: ColonyColor) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .appFont(.system(size: 11.5, weight: .bold))
                .foregroundStyle(color.color)
                .frame(width: 22, height: 22)
                .background(color.color.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).appFont(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                Text(text).appFont(.system(size: 11.5)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Coloured rounded square with a white glyph: the face of every block.
struct BlockIcon: View {
    let symbol: String
    let color: ColonyColor
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .appFont(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.color.gradient, in: .rect(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - New automation dialog

struct NewAutomationDialog: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dialogDismiss) private var dismiss

    var body: some View {
        DialogFrame(
            symbol: "bolt.fill",
            tint: ColonyColor.orange.color,
            title: "New automation",
            description: "Start from a recipe and change what you like, or build one from scratch. It stays off until you switch it on."
        ) {
            Button { create(nil) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .appFont(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 30, height: 30)
                        .background(Theme.text.opacity(0.06), in: .rect(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start from scratch").appFont(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.text)
                        Text("An empty flow: choose When, then add steps.").appFont(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").appFont(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
                }
                .padding(12)
                .background(Theme.surface, in: .rect(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke) }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start from scratch")

            Text("Or pick a recipe")
                .appFont(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            RecipeGrid(columns: 250) { recipe in create(recipe) }
        }
    }

    private func create(_ recipe: AutomationRecipe?) {
        let automation = WorkspaceActions(context: context).createAutomation(from: recipe)
        try? context.save()
        dismiss()
        app.go(.automation(automation.uuid))
    }
}

struct DeleteAutomationDialog: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let automationID: UUID

    var body: some View {
        let automation = context.automation(automationID)
        ConfirmDialog(
            symbol: "trash",
            title: "Delete \(automation?.name ?? "this automation")?",
            message: "It stops running and is removed from all your devices, with its history. Things it already did stay.",
            confirmTitle: "Delete automation"
        ) {
            guard let automation else { return }
            if app.destination == .automation(automationID) { app.go(.crew(.automations)) }
            WorkspaceActions(context: context).delete(automation)
        }
    }
}

// MARK: - Editor

struct AutomationEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Bindable var automation: Automation
    @Query private var projectsEverywhere: [Project]
    private var projects: [Project] { projectsEverywhere.inWorkspace() }
    @Query(sort: \Channel.sortIndex) private var channelsEverywhere: [Channel]
    private var channels: [Channel] { channelsEverywhere.inWorkspace() }
    @Query(sort: \Agent.sortIndex) private var agentsEverywhere: [Agent]
    private var agents: [Agent] { agentsEverywhere.inWorkspace() }
    @State private var test: AutomationOutcome?
    @State private var testNote: String?
    @State private var picker: BlockPicker.Mode?
    @State private var focusName = false
    @FocusState private var nameFocused: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// iPhone: no desktop header row or dotted canvas; controls live in the
    /// navigation bar and a status card.
    private var isPhone: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    private var names: AutomationNames {
        AutomationNames(
            projects: Dictionary(projects.map { ($0.uuid, $0.name) }, uniquingKeysWith: { a, _ in a }),
            channels: Dictionary(channels.map { ($0.uuid, $0.name) }, uniquingKeysWith: { a, _ in a }),
            agents: Dictionary(agents.map { ($0.uuid, $0.name) }, uniquingKeysWith: { a, _ in a })
        )
    }

    var body: some View {
        let names = names
        VStack(spacing: 0) {
            if !isPhone {
                header
                Divider().overlay(Theme.stroke)
            }
            ScrollView {
                VStack(spacing: 0) {
                    if isPhone {
                        phoneStatus.padding(.bottom, 14)
                    }
                    SentenceCard(automation: automation, names: names)
                        .padding(.bottom, 18)
                    if let test {
                        TestResultCard(outcome: test, note: testNote, onRun: runForReal, onClose: { withMotion(.snappy(duration: 0.2)) { self.test = nil } })
                            .padding(.bottom, 18)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    flow(names)
                    RunHistory(automation: automation)
                        .padding(.top, 34)
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, isPhone ? 16 : 24)
                .padding(.top, isPhone ? 8 : 22)
                .padding(.bottom, 40)
            }
            .background { if !isPhone { DotGrid() } }
        }
        .background(Theme.canvas)
        .navigationTitle(automation.name)
        #if os(iOS)
        .toolbar(isPhone ? .hidden : .automatic, for: .tabBar)
        .toolbar {
            if isPhone {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Test", systemImage: "play.circle", action: runTest)
                        .disabled(!automation.isComplete)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu { moreItems } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel("More")
                }
            }
        }
        #endif
        .defaultFocus($nameFocused, false)
        .onAppear { nameFocused = false }
        .popover(item: $picker) { mode in
            BlockPicker(mode: mode, subject: automation.trigger?.kind.subject ?? .none) { choice in
                apply(choice, mode: mode)
                picker = nil
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            AgentFace(color: automation.color.color, size: 32, isRound: false, seed: automation.name.count + 40)
                .opacity(automation.isEnabled ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: Binding(get: { automation.name }, set: { automation.name = String($0.prefix(60)) }))
                    .textFieldStyle(.plain)
                    .appFont(.headline)
                    .foregroundStyle(Theme.text)
                    .focused($nameFocused)
                    .onSubmit {
                        if ColonyText.trimmed(automation.name).isEmpty { automation.name = "New automation" }
                        nameFocused = false
                    }
                    .accessibilityLabel("Automation name")
                    .frame(maxWidth: 320, alignment: .leading)
                HStack(spacing: 6) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 6, height: 6)
                        .phaseAnimator(app.automations.isRunning(automation) ? [0.3, 1] : [1]) { v, p in v.opacity(p) } animation: { _ in .easeInOut(duration: 0.4) }
                    Text(stateText)
                        .appFont(.system(size: 11.5))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 8)
            Button(action: runTest) { Label("Test", systemImage: "play.circle") }
                .buttonStyle(.dialogSecondary)
                .disabled(!automation.isComplete)
                .help("See what it would do right now, without changing anything")
            Toggle(isOn: Binding(get: { automation.isEnabled }, set: { on in
                WorkspaceActions(context: context).setEnabled(on, for: automation)
                app.show(on ? "\(automation.name) is on" : "\(automation.name) is off")
            })) {
                Text(automation.isEnabled ? "On" : "Off")
                    .appFont(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(automation.isEnabled ? Theme.text : Theme.secondaryText)
                    .frame(minWidth: 22, alignment: .trailing)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!automation.isComplete)
            .help(automation.isComplete ? "Switch the automation on or off" : "Choose When and add a step first")
            .accessibilityLabel("Automation on")
            Menu {
                moreItems
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize()
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 22)
        .padding(.leading, app.preferences.isSidebarCollapsed && isMacPlatform ? 22 : 0)
        .frame(minHeight: 60)
    }

    @ViewBuilder
    private var moreItems: some View {
        Picker("Colour", selection: Binding(get: { automation.color }, set: { automation.color = $0 })) {
            ForEach(ColonyColor.allCases) { color in Text(color.title).tag(color) }
        }
        Divider()
        Button("Duplicate", systemImage: "plus.square.on.square") {
            let copy = WorkspaceActions(context: context).duplicate(automation)
            try? context.save()
            app.go(.automation(copy.uuid))
        }
        Button("Clear History", systemImage: "eraser") {
            (automation.runs ?? []).forEach(context.delete)
        }
        Divider()
        Button("Delete Automation…", systemImage: "trash", role: .destructive) { app.present(.deleteAutomation(automation.uuid)) }
    }

    /// iPhone: name and the on/off switch as two grouped rows, like Settings.
    private var phoneStatus: some View {
        VStack(spacing: 0) {
            TextField("Name", text: Binding(get: { automation.name }, set: { automation.name = String($0.prefix(60)) }))
                .appFont(.system(size: 17, weight: .semibold))
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit {
                    if ColonyText.trimmed(automation.name).isEmpty { automation.name = "New automation" }
                    nameFocused = false
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 50)
                .accessibilityLabel("Automation name")
            Rectangle().fill(Theme.stroke).frame(height: 0.5).padding(.leading, 16)
            Toggle(isOn: Binding(get: { automation.isEnabled }, set: { on in
                WorkspaceActions(context: context).setEnabled(on, for: automation)
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enabled").appFont(.system(size: 17))
                    HStack(spacing: 6) {
                        Circle().fill(stateColor).frame(width: 7, height: 7)
                        Text(stateText).appFont(.system(size: 14)).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .disabled(!automation.isComplete)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var stateText: String {
        if app.automations.isRunning(automation) { return "Running…" }
        if !automation.isComplete { return automation.trigger == nil ? "Choose what starts it" : "Add a step" }
        if !automation.isEnabled { return "Off · switch on when ready" }
        if let last = automation.lastRunAt { return "On · ran \(last.formatted(.relative(presentation: .named)))" }
        return "On · waiting for \(automation.trigger?.shortLabel(names).lowercased() ?? "its trigger")"
    }

    private var stateColor: Color {
        if app.automations.isRunning(automation) { return automation.color.color }
        if !automation.isComplete { return ColonyColor.orange.color }
        return automation.isEnabled ? ColonyColor.green.color : Theme.tertiaryText
    }

    // MARK: Flow

    @ViewBuilder
    private func flow(_ names: AutomationNames) -> some View {
        let subject = automation.trigger?.kind.subject ?? .none
        VStack(spacing: 0) {
            // WHEN
            if let trigger = automation.trigger {
                FlowNode(role: .when, symbol: trigger.kind.symbol, color: trigger.kind.category.color, title: trigger.kind.title, menu: {
                    Button("Change Trigger…", systemImage: "arrow.left.arrow.right") { picker = .trigger }
                }) {
                    TriggerSettings(trigger: Binding(get: { trigger }, set: { WorkspaceActions(context: context).setTrigger($0, for: automation) }), channels: channels)
                }
            } else {
                EmptyNode(role: .when, title: "Choose what starts it", detail: "A new task, a deal that's won, a time of day…") { picker = .trigger }
            }

            // ONLY IF
            if automation.trigger != nil {
                if automation.conditions.isEmpty {
                    Connector {
                        if subject != .none {
                            ConnectorButton(title: "Only if…", symbol: "line.3.horizontal.decrease") { picker = .condition }
                                .help("Optional: only continue when it matches")
                        }
                    }
                } else {
                    Connector()
                    FlowNode(role: .onlyIf, symbol: "line.3.horizontal.decrease", color: .purple, title: automation.conditions.count == 1 ? "When it matches" : "When all of these match", menu: {
                        Button("Remove All Filters", systemImage: "xmark.circle") { automation.conditions = [] }
                    }) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(automation.conditions) { condition in
                                ConditionRow(condition: binding(condition), projects: projects.filter { $0.archivedAt == nil }, fits: condition.kind.subject == subject) {
                                    automation.conditions.removeAll { $0.id == condition.id }
                                }
                            }
                            Button { picker = .condition } label: {
                                Label("And…", systemImage: "plus")
                                    .appFont(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add another filter")
                        }
                    }
                }
            }

            // THEN
            ForEach(Array(automation.steps.enumerated()), id: \.element.id) { index, step in
                Connector {
                    if index > 0 {
                        ConnectorPlus { picker = .step(at: index) }
                    }
                }
                FlowNode(role: .then(index + 1), symbol: step.kind.symbol, color: step.kind.category.color, title: step.kind.title,
                         warning: warning(for: step, subject: subject), menu: {
                    Button("Move Up", systemImage: "arrow.up") { move(step, by: -1) }.disabled(index == 0)
                    Button("Move Down", systemImage: "arrow.down") { move(step, by: 1) }.disabled(index == automation.steps.count - 1)
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        var copy = step
                        copy.id = UUID()
                        automation.steps.insert(copy, at: index + 1)
                    }
                    Divider()
                    Button("Remove Step", systemImage: "trash", role: .destructive) { automation.steps.removeAll { $0.id == step.id } }
                }) {
                    StepSettings(step: binding(step), subject: subject, projects: projects.filter { $0.archivedAt == nil }, channels: channels, agents: agents)
                }
            }

            if automation.trigger != nil {
                Connector()
                AddStepButton(isFirst: automation.steps.isEmpty) { picker = .step(at: automation.steps.count) }
            }
        }
        .motion(.snappy(duration: 0.22), value: automation.stepsJSON)
        .motion(.snappy(duration: 0.22), value: automation.conditionsJSON)
    }

    private func warning(for step: AutomationStep, subject: AutomationSubjectKind) -> String? {
        if !step.kind.fits(subject) {
            return step.kind.needs == .task ? "Needs a task, and this trigger doesn't give one." : "Needs a customer, and this trigger doesn't give one."
        }
        if !step.isComplete {
            switch step.kind {
            case .postMessage: return step.channelID == nil ? "Choose a channel." : "Write the message."
            case .moveTask: return "Choose a project."
            case .askAgent: return step.agentID == nil ? "Choose an agent." : "Write what to ask."
            default: return "Fill in the blank."
            }
        }
        return nil
    }

    private func binding(_ step: AutomationStep) -> Binding<AutomationStep> {
        Binding(get: { automation.steps.first { $0.id == step.id } ?? step }, set: { new in
            var steps = automation.steps
            if let i = steps.firstIndex(where: { $0.id == step.id }) { steps[i] = new; automation.steps = steps }
        })
    }

    private func binding(_ condition: AutomationCondition) -> Binding<AutomationCondition> {
        Binding(get: { automation.conditions.first { $0.id == condition.id } ?? condition }, set: { new in
            var conditions = automation.conditions
            if let i = conditions.firstIndex(where: { $0.id == condition.id }) { conditions[i] = new; automation.conditions = conditions }
        })
    }

    private func move(_ step: AutomationStep, by offset: Int) {
        var steps = automation.steps
        guard let i = steps.firstIndex(where: { $0.id == step.id }), steps.indices.contains(i + offset) else { return }
        steps.swapAt(i, i + offset)
        automation.steps = steps
    }

    private func apply(_ choice: BlockPicker.Choice, mode: BlockPicker.Mode) {
        let actions = WorkspaceActions(context: context)
        switch choice {
        case .trigger(let kind):
            let old = automation.trigger
            actions.setTrigger(AutomationTrigger(kind: kind), for: automation)
            // Filters that don't apply to the new kind of item go.
            if old?.kind.subject != kind.subject {
                automation.conditions = automation.conditions.filter { $0.kind.subject == kind.subject }
            }
        case .condition(let kind):
            let projectID = kind == .inProject ? projects.first(where: { $0.archivedAt == nil })?.uuid : nil
            automation.conditions.append(AutomationCondition(kind: kind, projectID: projectID))
        case .step(let kind):
            var step = AutomationStep(kind: kind)
            switch kind {
            case .postMessage: step.channelID = (channels.first { $0.name == "general" } ?? channels.first)?.uuid
            case .askAgent: step.agentID = agents.first?.uuid
            case .moveTask: step.projectID = projects.first { $0.archivedAt == nil }?.uuid
            case .notify: step.text = automation.trigger?.kind.subject.tokens.first?.token ?? ""
            default: break
            }
            var steps = automation.steps
            if case .step(let index) = mode { steps.insert(step, at: min(index, steps.count)) } else { steps.append(step) }
            automation.steps = steps
        }
        try? context.save()
    }

    // MARK: Test

    private func runTest() {
        guard let trigger = automation.trigger else { return }
        let executor = AutomationExecutor(context: context, dryRun: true)
        let subject = executor.sampleSubject(for: trigger)
        if trigger.kind.subject != .none, case .none = subject {
            testNote = "There's nothing to try it on yet: this needs a \(trigger.kind.subject == .task ? "task" : trigger.kind.subject == .customer ? "customer" : "message")."
            withMotion(.snappy(duration: 0.2)) { test = AutomationOutcome(kind: .skipped, title: "Nothing to test with", lines: []) }
            return
        }
        testNote = nil
        withMotion(.snappy(duration: 0.2)) { test = executor.run(automation, subject: subject) }
    }

    private func runForReal() {
        guard let outcome = app.automations.runNow(automation) else { return }
        withMotion(.snappy(duration: 0.2)) { test = nil }
        app.show(outcome.kind == .ran ? "\(automation.name) ran" : outcome.kind == .skipped ? "Didn't match, so nothing ran" : "Some steps didn't work", detail: outcome.lines.last, style: outcome.kind == .failed ? .error : .success)
    }
}

// MARK: - Canvas pieces

/// n8n-style dotted background.
private struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 18
            var path = Path()
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8))
                    x += spacing
                }
                y += spacing
            }
            context.fill(path, with: .color(Theme.strongStroke.opacity(0.7)))
        }
        .accessibilityHidden(true)
    }
}

private struct SentenceCard: View {
    let automation: Automation
    let names: AutomationNames

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "text.quote")
                .appFont(.system(size: 13, weight: .semibold))
                .foregroundStyle(automation.color.color)
                .padding(.top, 2)
            Text(automation.sentence(names))
                .appFont(.system(size: 14.5, weight: .medium))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(automation.color.color.opacity(0.08), in: .rect(cornerRadius: 12, style: .continuous))
        .background(Theme.canvas, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(automation.color.color.opacity(0.25)) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("In short: \(automation.sentence(names))")
    }
}

enum FlowRole: Equatable {
    case when, onlyIf, then(Int)

    var label: String {
        switch self {
        case .when: "WHEN"
        case .onlyIf: "ONLY IF"
        case .then(let n): n == 1 ? "THEN" : "THEN · \(n)"
        }
    }
}

/// One block on the canvas: role label, icon, title, a menu, and its settings.
private struct FlowNode<Settings: View, MenuItems: View>: View {
    let role: FlowRole
    let symbol: String
    let color: ColonyColor
    let title: String
    var warning: String? = nil
    @ViewBuilder var menu: () -> MenuItems
    @ViewBuilder var settings: () -> Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                BlockIcon(symbol: symbol, color: color, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(role.label)
                        .appFont(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(color.color)
                    Text(title)
                        .appFont(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
                Spacer(minLength: 6)
                Menu { menu() } label: {
                    Image(systemName: "ellipsis")
                        .appFont(.system(size: 13, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(.rect)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize()
                .accessibilityLabel("\(title) options")
            }
            settings()
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .appFont(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(ColonyColor.orange.color)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(warning == nil ? Theme.stroke : ColonyColor.orange.color.opacity(0.5))
        }
        .overlay(alignment: .leading) {
            // Coloured edge, so the flow reads by colour at a glance.
            UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14, style: .continuous)
                .fill(color.color)
                .frame(width: 3)
        }
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(role.label.capitalized): \(title)")
    }
}

/// A dashed placeholder block: "Choose what starts it".
private struct EmptyNode: View {
    let role: FlowRole
    let title: String
    let detail: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .appFont(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ColonyColor.blue.color)
                    .frame(width: 30, height: 30)
                    .background(ColonyColor.blue.color.opacity(0.12), in: .rect(cornerRadius: 8.5, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(role.label).appFont(.system(size: 10, weight: .bold)).tracking(0.6).foregroundStyle(ColonyColor.blue.color)
                    Text(title).appFont(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(detail).appFont(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }
            .padding(14)
            .background(isHovering ? Theme.raised : Theme.surface, in: .rect(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(ColonyColor.blue.color.opacity(isHovering ? 0.8 : 0.45), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
    }
}

/// The line between blocks, optionally with a button on it.
private struct Connector<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Theme.strongStroke)
                .frame(width: 2)
            content()
        }
        .frame(height: 38)
        .frame(maxWidth: .infinity)
    }
}

extension Connector where Content == EmptyView {
    init() { self.init(content: { EmptyView() }) }
}

private struct ConnectorPlus: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .appFont(.system(size: 10, weight: .bold))
                .foregroundStyle(isHovering ? .white : Theme.secondaryText)
                .frame(width: 22, height: 22)
                .background(isHovering ? ColonyColor.blue.color : Theme.surface, in: Circle())
                .overlay { Circle().strokeBorder(isHovering ? .clear : Theme.strongStroke) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Add a step here")
        .accessibilityLabel("Add a step here")
    }
}

private struct ConnectorButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .appFont(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isHovering ? Theme.text : Theme.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.surface, in: Capsule())
                .overlay { Capsule().strokeBorder(isHovering ? Theme.secondaryText : Theme.strongStroke) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Add a filter")
    }
}

private struct AddStepButton: View {
    let isFirst: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .appFont(.system(size: 12, weight: .bold))
                Text(isFirst ? "Then do this…" : "Add a step")
                    .appFont(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isHovering || isFirst ? .white : Theme.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(isHovering || isFirst ? ColonyColor.blue.color : Theme.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(isHovering || isFirst ? .clear : Theme.strongStroke) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(isFirst ? "Add the first step" : "Add a step")
    }
}

// MARK: - Inline settings

/// A compact menu that looks like a filled-in blank: "In review ⌄".
struct BlankMenu<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    var placeholder = "Choose…"

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(options.first { $0.value == selection }?.title ?? placeholder)
                    .appFont(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .appFont(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Theme.text.opacity(0.05), in: .rect(cornerRadius: 7, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.strongStroke) }
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// "Label  [blank]" on one line.
private struct BlankRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .appFont(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryText)
            content()
            Spacer(minLength: 0)
        }
    }
}

private struct TriggerSettings: View {
    @Binding var trigger: AutomationTrigger
    let channels: [Channel]

    var body: some View {
        switch trigger.kind {
        case .taskStatusChanged:
            BlankRow(label: "Moves to") {
                BlankMenu(selection: $trigger.status, options: [(nil, "Any status")] + TaskStatus.allCases.map { (Optional($0), $0.title) })
            }
        case .dealStageChanged:
            BlankRow(label: "Moves to") {
                BlankMenu(selection: $trigger.stage, options: [(nil, "Any stage")] + DealStage.allCases.map { (Optional($0), $0.title) })
            }
        case .messagePosted:
            BlankRow(label: "In") {
                BlankMenu(selection: $trigger.channelID, options: [(nil, "Any channel")] + channels.map { (Optional($0.uuid), "#\($0.name)") })
            }
        case .schedule:
            ScheduleSettings(text: Binding(get: { trigger.scheduleText ?? "weekdays 09:00" }, set: { trigger.scheduleText = $0 }))
        case .taskCreated, .taskOverdue, .customerAdded:
            Text(trigger.kind.detail)
                .appFont(.system(size: 12))
                .foregroundStyle(Theme.tertiaryText)
        }
    }
}

private struct ScheduleSettings: View {
    @Binding var text: String

    private enum Repeat: Hashable {
        case hourly, daily, weekdays, weekly(Int)
    }

    var body: some View {
        let schedule = AgentSchedule(text) ?? AgentSchedule(kind: .weekdays)
        HStack(spacing: 8) {
            BlankMenu(selection: Binding(get: { repeatOf(schedule) }, set: { update(schedule, repeat: $0) }), options: options)
            if schedule.kind != .hourly {
                Text("at").appFont(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
                DatePicker("Time", selection: Binding(get: {
                    Calendar.current.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: .now) ?? .now
                }, set: { date in
                    var s = schedule
                    s.hour = Calendar.current.component(.hour, from: date)
                    s.minute = Calendar.current.component(.minute, from: date)
                    text = s.text
                }), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Time")
            }
            Spacer(minLength: 0)
        }
    }

    private var options: [(value: Repeat, title: String)] {
        [(.hourly, "Every hour"), (.daily, "Every day"), (.weekdays, "Every weekday")]
            + (1...7).map { day in (Repeat.weekly(day), "Every \(Calendar.current.weekdaySymbols[day - 1])") }
    }

    private func repeatOf(_ schedule: AgentSchedule) -> Repeat {
        switch schedule.kind {
        case .hourly: .hourly
        case .daily: .daily
        case .weekdays: .weekdays
        case .weekly(let day): .weekly(day)
        }
    }

    private func update(_ schedule: AgentSchedule, repeat value: Repeat) {
        var s = schedule
        switch value {
        case .hourly: s = AgentSchedule(kind: .hourly, hour: 0, minute: 0)
        case .daily: s.kind = .daily
        case .weekdays: s.kind = .weekdays
        case .weekly(let day): s.kind = .weekly(weekday: day)
        }
        text = s.text
    }
}

private struct ConditionRow: View {
    @Binding var condition: AutomationCondition
    let projects: [Project]
    let fits: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: condition.kind.symbol)
                .appFont(.system(size: 11))
                .foregroundStyle(ColonyColor.purple.color)
                .frame(width: 16)
            Text(condition.kind.title)
                .appFont(.system(size: 12.5))
                .foregroundStyle(fits ? Theme.secondaryText : ColonyColor.orange.color)
                .fixedSize()
            value
            Spacer(minLength: 0)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .appFont(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: 20, height: 20)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove filter: \(condition.kind.title)")
        }
    }

    @ViewBuilder
    private var value: some View {
        switch condition.kind {
        case .inProject:
            BlankMenu(selection: $condition.projectID, options: projects.map { (Optional($0.uuid), $0.name) })
        case .priorityIs:
            BlankMenu(selection: $condition.priority, options: TaskPriority.allCases.map { (Optional($0), $0.title) })
        case .titleContains, .companyContains, .messageContains:
            InlineField(placeholder: "word or phrase", text: $condition.text)
        case .dealValueAtLeast:
            TextField("Amount", value: $condition.number, format: .number)
                .textFieldStyle(.plain)
                .appFont(.system(size: 12.5), role: .data)
                .frame(width: 90)
                .modifier(InlineChrome())
        case .isFlagged:
            EmptyView()
        }
    }
}

private struct InlineChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.field, in: .rect(cornerRadius: 7, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.strongStroke) }
    }
}

private struct InlineField: View {
    let placeholder: String
    @Binding var text: String
    var multiline = false

    var body: some View {
        TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(Theme.tertiaryText), axis: multiline ? .vertical : .horizontal)
            .textFieldStyle(.plain)
            .appFont(.system(size: 12.5), role: .data)
            .foregroundStyle(Theme.text)
            .lineLimit(multiline ? 1...4 : 1...1)
            .modifier(InlineChrome())
            .accessibilityLabel(placeholder)
    }
}

private struct StepSettings: View {
    @Binding var step: AutomationStep
    let subject: AutomationSubjectKind
    let projects: [Project]
    let channels: [Channel]
    let agents: [Agent]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            switch step.kind {
            case .createTask:
                TextWithTokens(placeholder: "Task name, e.g. Follow up with {customer}", text: $step.text, subject: subject)
                HStack(spacing: 8) {
                    BlankRow(label: "In") {
                        BlankMenu(selection: $step.projectID, options: [(nil, "My tasks")] + projects.map { (Optional($0.uuid), $0.name) })
                    }
                }
                DaysRow(label: "Due", days: $step.days, zero: "No date")
            case .setPriority:
                BlankRow(label: "Set to") { BlankMenu(selection: $step.priority, options: TaskPriority.allCases.map { (Optional($0), $0.title) }) }
            case .setStatus:
                BlankRow(label: "Move to") { BlankMenu(selection: $step.status, options: TaskStatus.allCases.map { (Optional($0), $0.title) }) }
            case .flagTask:
                Text("Adds it to the Flagged list.").appFont(.system(size: 12)).foregroundStyle(Theme.tertiaryText)
            case .moveTask:
                BlankRow(label: "To") { BlankMenu(selection: $step.projectID, options: projects.map { (Optional($0.uuid), $0.name) }) }
            case .setDue:
                DaysRow(label: "Due", days: $step.days, zero: "Today")
            case .setStage:
                BlankRow(label: "Move to") { BlankMenu(selection: $step.stage, options: DealStage.allCases.map { (Optional($0), $0.title) }) }
            case .postMessage:
                BlankRow(label: "In") { BlankMenu(selection: $step.channelID, options: channels.map { (Optional($0.uuid), "#\($0.name)") }) }
                TextWithTokens(placeholder: "Message", text: $step.text, subject: subject, multiline: true)
            case .postUpdate:
                TextWithTokens(placeholder: "What to note in Updates", text: $step.text, subject: subject)
            case .notify:
                TextWithTokens(placeholder: "What the notification says", text: $step.text, subject: subject)
            case .askAgent:
                BlankRow(label: "Agent") { BlankMenu(selection: $step.agentID, options: agents.map { (Optional($0.uuid), $0.name) }) }
                TextWithTokens(placeholder: "What to ask, e.g. Draft a follow-up for {customer}", text: $step.text, subject: subject, multiline: true)
            case .clearCompleted:
                DaysRow(label: "Done more than", days: $step.days, zero: "", suffix: "ago", range: 1...365)
            }
        }
    }
}

private struct DaysRow: View {
    let label: String
    @Binding var days: Int
    let zero: String
    var suffix = "from the day it runs"
    var range: ClosedRange<Int> = 0...60

    var body: some View {
        HStack(spacing: 8) {
            Text(label).appFont(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
            Stepper(value: $days, in: range) {
                Text(days == 0 && !zero.isEmpty ? zero : "\(AutomationStep.days(days)) \(suffix)")
                    .appFont(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .monospacedDigit()
            }
            .fixedSize()
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A text field with the trigger's words ({task}, {customer}…) as chips to drop in.
private struct TextWithTokens: View {
    let placeholder: String
    @Binding var text: String
    let subject: AutomationSubjectKind
    var multiline = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InlineField(placeholder: placeholder, text: $text, multiline: multiline)
            HStack(spacing: 5) {
                Text("Insert")
                    .appFont(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
                ForEach(subject.tokens, id: \.token) { token in
                    Button {
                        let spacer = text.isEmpty || text.hasSuffix(" ") ? "" : " "
                        text += spacer + token.token
                    } label: {
                        Text(token.title)
                            .appFont(.system(size: 11, weight: .medium))
                            .foregroundStyle(ColonyColor.blue.color)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(ColonyColor.blue.color.opacity(0.1), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Adds \(token.token): replaced with the \(token.title.lowercased()) when it runs")
                    .accessibilityLabel("Insert \(token.title)")
                }
            }
        }
    }
}

// MARK: - Block picker

struct BlockPicker: View {
    enum Mode: Identifiable, Hashable {
        case trigger, condition, step(at: Int)
        var id: String {
            switch self {
            case .trigger: "trigger"
            case .condition: "condition"
            case .step(let i): "step-\(i)"
            }
        }
    }

    enum Choice {
        case trigger(TriggerKind), condition(ConditionKind), step(StepKind)
    }

    let mode: Mode
    let subject: AutomationSubjectKind
    let pick: (Choice) -> Void
    @State private var query = ""

    private struct Entry: Identifiable {
        let id: String
        let choice: Choice
        let title: String
        let detail: String
        let symbol: String
        let category: AutomationCategory
        var disabledReason: String?
    }

    private var entries: [Entry] {
        switch mode {
        case .trigger:
            return TriggerKind.allCases.map { Entry(id: $0.rawValue, choice: .trigger($0), title: $0.title, detail: $0.detail, symbol: $0.symbol, category: $0.category) }
        case .condition:
            return ConditionKind.allCases.filter { $0.subject == subject }.map {
                Entry(id: $0.rawValue, choice: .condition($0), title: $0.title, detail: "", symbol: $0.symbol, category: .tasks)
            }
        case .step:
            return StepKind.allCases.map { kind in
                var entry = Entry(id: kind.rawValue, choice: .step(kind), title: kind.title, detail: kind.detail, symbol: kind.symbol, category: kind.category)
                if !kind.fits(subject) {
                    entry.disabledReason = kind.needs == .task ? "Only when a task starts it" : "Only when a customer starts it"
                }
                return entry
            }
        }
    }

    private var filtered: [Entry] {
        let q = ColonyText.trimmed(query).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.title.lowercased().contains(q) || $0.detail.lowercased().contains(q) || $0.category.title.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(heading)
                    .appFont(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                DialogTextField(placeholder: "Search", text: $query, symbol: "magnifyingglass", autofocus: true) {
                    if let first = filtered.first(where: { $0.disabledReason == nil }) { pick(first.choice) }
                }
            }
            .padding(14)
            Divider().overlay(Theme.stroke)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groups, id: \.0) { category, items in
                        VStack(alignment: .leading, spacing: 2) {
                            if mode != .condition {
                                Text(category.title.uppercased())
                                    .appFont(.system(size: 10, weight: .bold))
                                    .tracking(0.5)
                                    .foregroundStyle(Theme.tertiaryText)
                                    .padding(.horizontal, 8)
                                    .padding(.bottom, 2)
                            }
                            ForEach(items) { entry in row(entry) }
                        }
                    }
                    if filtered.isEmpty {
                        Text("Nothing matches “\(query)”.")
                            .appFont(.system(size: 12.5))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(8)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 420)
        }
        .frame(width: 360)
        .background(Theme.raised)
    }

    private var heading: String {
        switch mode {
        case .trigger: "What starts it?"
        case .condition: "Only continue if…"
        case .step: "Then what should happen?"
        }
    }

    private var groups: [(AutomationCategory, [Entry])] {
        let items = filtered
        var order: [AutomationCategory] = []
        for entry in items where !order.contains(entry.category) { order.append(entry.category) }
        return order.map { category in (category, items.filter { $0.category == category }) }
    }

    private func row(_ entry: Entry) -> some View {
        PickerRow(title: entry.title, detail: entry.disabledReason ?? entry.detail, symbol: entry.symbol,
                  color: mode == .condition ? .purple : entry.category.color, isDisabled: entry.disabledReason != nil) {
            pick(entry.choice)
        }
    }
}

private struct PickerRow: View {
    let title: String
    let detail: String
    let symbol: String
    let color: ColonyColor
    let isDisabled: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                BlockIcon(symbol: symbol, color: isDisabled ? .gray : color, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .appFont(.system(size: 13, weight: .medium))
                        .foregroundStyle(isDisabled ? Theme.tertiaryText : Theme.text)
                    if !detail.isEmpty {
                        Text(detail)
                            .appFont(.system(size: 11.5))
                            .foregroundStyle(Theme.tertiaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHovering && !isDisabled ? Theme.hover : .clear, in: .rect(cornerRadius: 8, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}

// MARK: - Test and history

private struct TestResultCard: View {
    let outcome: AutomationOutcome
    let note: String?
    let onRun: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .appFont(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .appFont(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close test")
            }
            if let note {
                Text(note).appFont(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(outcome.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .appFont(.system(size: 12.5))
                        .foregroundStyle(line.hasPrefix("✕") || line.hasPrefix("Stopped") ? ColonyColor.orange.color : Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if note == nil {
                HStack {
                    Text("Nothing was changed.")
                        .appFont(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiaryText)
                    Spacer()
                    if outcome.kind == .ran {
                        Button("Run it for real", action: onRun)
                            .buttonStyle(.dialogSecondary)
                            .help("Do these steps now")
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.45)) }
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        if note != nil { return outcome.title }
        switch outcome.kind {
        case .ran: return "Test with “\(outcome.title)”"
        case .skipped: return "“\(outcome.title)” wouldn't match"
        case .failed: return "Some steps wouldn't work"
        }
    }

    private var icon: String {
        switch outcome.kind {
        case .ran: "checkmark.circle.fill"
        case .skipped: "minus.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch outcome.kind {
        case .ran: ColonyColor.green.color
        case .skipped: Theme.secondaryText
        case .failed: ColonyColor.orange.color
        }
    }
}

private struct RunHistory: View {
    let automation: Automation
    @State private var expanded: UUID?

    var body: some View {
        let runs = automation.sortedRuns
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Activity", detail: runs.isEmpty ? nil : "\(automation.runCount) \(automation.runCount == 1 ? "run" : "runs")")
            if runs.isEmpty {
                Text(automation.isEnabled ? "Nothing yet. Each time it runs, you'll see what it did here." : "Switch it on and each run shows up here.")
                    .appFont(.system(size: 12.5))
                    .foregroundStyle(Theme.tertiaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(runs.enumerated()), id: \.element.uuid) { index, run in
                        if index > 0 { Divider().overlay(Theme.stroke) }
                        runRow(run)
                    }
                }
                .background(Theme.surface, in: .rect(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func runRow(_ run: AutomationRun) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withMotion(.snappy(duration: 0.18)) { expanded = expanded == run.uuid ? nil : run.uuid }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: run.outcome == .ran ? "checkmark.circle.fill" : run.outcome == .skipped ? "minus.circle" : "exclamationmark.triangle.fill")
                        .appFont(.system(size: 12))
                        .foregroundStyle(run.outcome == .ran ? ColonyColor.green.color : run.outcome == .skipped ? Theme.tertiaryText : ColonyColor.orange.color)
                    Text(run.outcome == .skipped ? "Skipped · \(run.title)" : run.title)
                        .appFont(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(run.startedAt.formatted(.relative(presentation: .named)))
                        .appFont(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiaryText)
                    Image(systemName: "chevron.right")
                        .appFont(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.tertiaryText)
                        .rotationEffect(.degrees(expanded == run.uuid ? 90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(run.outcome == .skipped ? "Skipped" : run.outcome == .failed ? "Had problems" : "Ran"): \(run.title), \(run.startedAt.formatted(.relative(presentation: .named)))")
            if expanded == run.uuid {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(run.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .appFont(.system(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

extension ModelContext {
    func automation(_ id: UUID) -> Automation? {
        try? fetch(FetchDescriptor<Automation>(predicate: #Predicate { $0.uuid == id })).first
    }
}
