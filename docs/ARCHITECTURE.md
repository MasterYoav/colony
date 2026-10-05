# Architecture

> **See it as a diagram:** [interactive architecture map](https://masteryoav.github.io/colony/architecture.html). Click any box to jump to its code. Its source is [`architecture.json`](architecture.json); to regenerate it, run `archify finalize architecture docs/architecture.json docs/architecture.html`.

Colony is a native Apple app. All data lives in the user's iCloud account and every integration uses a built-in Apple framework. There is no Colony server and no third-party SDK. The only optional exceptions are AI services the user connects with their own keys (Settings › AI).

## Storage

| What | Where | Framework |
| --- | --- | --- |
| Projects, lists, tasks, channels, messages, contacts, activity, agents and their conversations | Private CloudKit database `iCloud.yoavperetz.Colony` | SwiftData with `ModelConfiguration(cloudKitDatabase: .private(...))` |
| Preferences (appearance, name, workspace name, expanded sidebar projects, seed flag) | iCloud key-value store | `NSUbiquitousKeyValueStore`, mirrored to `UserDefaults` |
| Contact photos | CloudKit assets | `@Attribute(.externalStorage)` |

`CloudStore.makeContainer()` opens the CloudKit-backed store. If the build has no iCloud entitlement (for example an unsigned CI build) it falls back to a local-only store, and the UI says "Saved on this device only" instead of pretending to sync.

`ICloudStatus` watches `CKAccountChanged` and `NSPersistentCloudKitContainer.eventChangedNotification`, so the sidebar footer and Settings show the real account and mirroring state.

### CloudKit schema rules

Every `@Model` in `Models/ColonyModels.swift` follows these rules. `ColonyTests.schemaIsCloudKitCompatible` enforces them.

- Every attribute has a default value or is optional.
- Every relationship is optional and has an inverse.
- No `@Attribute(.unique)`.
- Enums are stored as raw strings with a safe fallback, so an older client can read records written by a newer one.

Before the first App Store release, deploy the schema to production in the CloudKit Console (Schema → Deploy Schema Changes).

## Apple services

| Feature | Framework | Notes |
| --- | --- | --- |
| Import people into the CRM | Contacts (`CNContactStore`) | Read-only. `appleContactIdentifier` makes imports idempotent. |
| Due-date alerts | EventKit (`EKReminder`) | Optional mirror of tasks into Apple Reminders. |
| Share, Mail, Phone, FaceTime | `ShareLink`, `mailto:`, `tel:`, `facetime:` | Hands off to system apps. |
| Due-date notifications | UserNotifications | Local alerts with Complete / Snooze; also agent notices. |
| Colony calendar | EventKit (`EKEvent`) | Dated tasks, automation and agent schedules. |
| Agents | Foundation Models (`LanguageModelSession`, `Tool`) | On device by default; optional cloud models and Jev with the user's own keys. See below. |
| AI keys | Security (Keychain, `kSecAttrSynchronizable`) | Synced by iCloud Keychain; never in SwiftData or KVS. |
| Identity | iCloud account | No separate sign-up. |

## Agents

An agent is an `Agent` record built from an AGENT.md file (`Agents/AgentDefinition.swift` parses and writes the format; [AGENTS.md](AGENTS.md) documents it). `AgentRunner` keeps one `LanguageModelSession` per agent while the app runs, seeded with the agent's instructions and its recent conversation, and streams replies into `AgentMessage` records.

Tools (`Agents/AgentTools.swift`) are Foundation Models `Tool`s that hop to the main actor and call `AgentWorkspace`, which reads the SwiftData context and changes it only through `WorkspaceActions`. Each change also adds an action row to the conversation. `AgentWorkspace` is plain Swift, so `AgentTests` covers the tools without a model.

Schedules run from a one-minute clock while the app is open. `Agent.lastScheduledSlot` syncs through iCloud, so each slot runs once across devices.

**Cloud models (optional).** `Agent.brainRaw` picks the model per agent (empty = the default in `AISettings`, a KVS preference). For OpenAI, Anthropic, Gemini and OpenAI-compatible servers, `AI/CloudModel.swift` runs a tool-calling loop over the *same* Foundation Models `Tool`s: each tool's `parameters` (`GenerationSchema`) encodes to JSON Schema, and the model's JSON arguments decode back with `GeneratedContent(json:)`. Each provider's wire format is a small `ChatFormat` value with pure request/parse functions, unit-tested without the network (`AITests`). Keys come from the Keychain (`AIAccounts`).

**Jev (optional).** `AI/Jev.swift` calls TypeSafe's System One API. With Jev on, `AgentRunner` adds `AskJevTool` (`ask_jev`) to every agent that has tools; answers are recorded as action rows.

## Automations

An `Automation` stores one trigger, filters and steps as small JSON blobs (CloudKit-safe) plus on/off and `lastScheduledSlot`; each run adds an `AutomationRun` (last 25 kept). `WorkspaceActions` announces changes on `AutomationBus` (task created, status changed, customer added or moved, message posted), so changes from you, agents and automations are all seen. `AutomationEngine` matches the event, checks the filters, runs the steps through `WorkspaceActions`, and caps chains at 3 automations in a row. The same one-minute clock handles schedules and the overdue check. `Automation.dryRun` powers the Test button without changing anything, and `AutomationTests` covers matching, filters, steps and sentences.

## Code layout

```
Colony/
  App/            ColonyApp entry, AppModel (navigation + sheets), RootView, starter content
  Models/         SwiftData models, WorkspaceActions (every mutation goes through here)
  Agents/         AGENT.md format, runner (Foundation Models), tools, agent screens
  AI/             AI accounts and Keychain, cloud model client, Jev
  Automations/    AutomationEngine, recipes, flow builder screens
  Services/       CloudStore, CloudPreferences, AppleServices (Contacts, Reminders)
  Sidebar/        Rail + expandable panel + collapsed icon column
  Screens/        Home, Tasks/Board/Projects, Messages, CRM/Pipeline/Reports, Settings, Sheets
  DesignSystem/   Theme tokens and shared primitives
  SwiftPieces/    Components installed from the Swift Pieces MCP (see below)
```

## Swift Pieces

UI components come from the Swift Pieces registry (`claude mcp add --transport http swiftpieces https://swiftpieces.com/api/mcp`) and are installed as source under `Colony/SwiftPieces/`:

GlassSurface, GlassSegments, FormField, FilterRail, TaskRow, LiveStat, RingBreakdown, ReactionToggle, CommitButton, Toast, ConfirmSheet, PermissionSheet.

The pieces are written for iOS. `SwiftPieces/PlatformCompat.swift` maps the few UIKit spellings they use onto AppKit so they also compile on macOS, and the Liquid Glass calls are compiled out on visionOS (where windows are already glass). Keep those shims when updating a piece.

## Platforms

iOS, iPadOS, macOS and visionOS 26.5+. iPhone uses a slide-in drawer for the sidebar. iPad, Mac and Vision Pro show the full sidebar.
