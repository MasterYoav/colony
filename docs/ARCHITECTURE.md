# Architecture

Colony is a native Apple app. All data lives in the user's iCloud account and every integration uses a built-in Apple framework. There is no Colony server and no third-party SDK.

## Storage

| What | Where | Framework |
| --- | --- | --- |
| Projects, lists, tasks, channels, messages, contacts, activity | Private CloudKit database `iCloud.yoavperetz.Colony` | SwiftData with `ModelConfiguration(cloudKitDatabase: .private(...))` |
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
| Identity | iCloud account | No separate sign-up. |

## Code layout

```
Colony/
  App/            ColonyApp entry, AppModel (navigation + sheets), RootView, starter content
  Models/         SwiftData models, WorkspaceActions (every mutation goes through here)
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
