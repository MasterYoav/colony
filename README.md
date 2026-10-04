<div align="center">

<img src="docs/assets/banner-fade.png" alt="Colony" width="100%">

<h3><b>Private workspace for Apple devices</b></h3>

projects, tasks, team channels, and a lightweight CRM in one native SwiftUI app for iPhone, iPad and Mac.

There's no Colony server and no third-party SDK. Your data lives in your iCloud account, and integrations use Apple's built-in apps. AI services are optional and use your own accounts.

[![CI](https://github.com/MasterYoav/colony/actions/workflows/swift.yml/badge.svg)](https://github.com/MasterYoav/colony/actions/workflows/swift.yml)
[![Swift](https://img.shields.io/badge/Swift-F54A2A?logo=swift&logoColor=white)](https://developer.apple.com/swift/)
[![iOS](https://img.shields.io/badge/iOS-000000?&logo=apple&logoColor=white)](#requirements)
[![macOS](https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=F0F0F0)](#requirements)

</div>

## Highlights

- **iCloud storage.** SwiftData models are mirrored to your private CloudKit database. Preferences, such as appearance and sidebar layout, sync through iCloud key-value storage.
- **Apple services.** Import people from Contacts, mirror due dates into Reminders, and reach contacts through Mail, Phone, FaceTime and the share sheet.
- **Agents.** On-device assistants powered by Apple Intelligence. Recruit one from an `AGENT.md` file, a template, or write your own. Agents read and change your tasks, customers and channels through the same actions you use, run on a schedule, and ask before big changes. Optionally run them on your own OpenAI, Claude or Gemini account, and let them ask [Jev](https://docs.typesafe.ai/introduction) for calibrated judgment calls (Settings › AI). See [Agents](docs/AGENTS.md).
- **Automations.** "When this happens, do that" for beginners, built from blocks instead of code: pick a trigger (a new task, a deal won, a message, a time of day), optional filters, and steps. Each automation reads as one sentence, can be tested without changing anything, and keeps a run log. Start from 8 recipes. See [Automations](docs/AUTOMATIONS.md).
- **Tasks like Reminders.** Smart lists, due-time notifications, and an optional Colony calendar in Apple Calendar.
- **Keyboard-first on Mac.** The ⌘K command center searches actions, projects, tasks and contacts. ⌘N creates a task, ⌘⇧N a project, and ⌃⌘S collapses the sidebar.
- **Workspaces.** Click the workspace name to switch or create a blank one (Personal, Sales, Team or Everything). Each has its own projects, tasks, customers, channels, agents and automations.
- **A sidebar that fits you.** Settings › Sidebar shows or hides every page and section, per workspace; drag items to reorder them. It syncs to your other devices.
- **Reports in plain language.** How it's going, what got done, what needs attention, and how each project and the pipeline are doing.
- **UI pieces.** Several components come from [Swift Pieces](https://swiftpieces.com), vendored in `Colony/SwiftPieces/` with a small AppKit compatibility shim.

## Requirements

- Xcode 26 or later.
- iOS, iPadOS, macOS or visionOS 26.5 or later.
- An Apple Developer account for iCloud sync. Without one the app still runs, but saves on the device only (see below).

## Try it out

```bash
git clone git@github.com:MasterYoav/colony.git
cd colony
open Colony.xcodeproj
```

Choose the **Colony** scheme and a destination, then press Run.

**Running without iCloud.** Builds without the iCloud entitlement, such as simulator runs without a team, fall back to an on-device store automatically. The sidebar footer then shows *Saved on this device only*. This is the quickest way to explore the UI.

**Running with your own iCloud container.** The project is set up for team `N6883L5366` and container `iCloud.yoavperetz.Colony`. To use your own:

1. In **Signing & Capabilities**, choose your team and change the bundle identifier.
2. Under **iCloud**, replace the container with one of yours (`iCloud.<your.bundle.id>`), and update `CloudStore.containerIdentifier` in `Colony/Services/CloudStore.swift` to match.
3. Sign in to iCloud on the device or simulator and run. The first launch can take a minute while CloudKit provisions the container.

Starter content is created once per iCloud account. To seed it again, pass `-didSeedStarterContent NO` as a launch argument (`-didSeedStarterAgents NO` for the starter agents). Agents need a device with Apple Intelligence turned on; elsewhere they can be recruited and edited but don't run.

## Tests

```bash
xcodebuild test -project Colony.xcodeproj -scheme Colony \
  -destination 'platform=macOS' -only-testing:ColonyTests CODE_SIGNING_ALLOWED=NO
```

The unit tests use an in-memory store and throwaway preferences, so they never touch your iCloud data.

## Project layout

```
Colony/
  App/           app model, root view, starter content
  Models/        SwiftData models and WorkspaceActions (the single mutation path)
  Agents/        AGENT.md format, on-device runner (Foundation Models), tools, agent screens
  AI/            AI accounts (Keychain), cloud model client, Jev
  Automations/   Automation engine (triggers, filters, steps, schedules), recipes, flow builder
  Services/      CloudStore (SwiftData + CloudKit), CloudPreferences (iCloud KVS), Apple services
  Sidebar/       sidebar, drag-and-drop layout
  Screens/       Home, Tasks, Messages, CRM, Settings, dialogs, command palette
  DesignSystem/  theme tokens and the shared dialog system
  SwiftPieces/   vendored Swift Pieces components
  Colony.icon    app icon (Icon Composer)
```

When changing models, keep them CloudKit-compatible: every attribute needs a default value, relationships must be optional with inverses, and `.unique` isn't allowed. [Architecture](docs/ARCHITECTURE.md) covers the details.

## Documentation

- [Architecture](docs/ARCHITECTURE.md): storage, CloudKit schema rules, Apple services, code layout
- [Agents and AGENT.md](docs/AGENTS.md)
- [Automations](docs/AUTOMATIONS.md)
- [Product](docs/PRODUCT.md)
- [Theming](docs/THEMING.md)
- [Roadmap](docs/ROADMAP.md)
