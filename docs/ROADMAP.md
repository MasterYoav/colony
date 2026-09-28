# Roadmap

## Done: native redesign

- SwiftData models synced to the private iCloud database through CloudKit.
- Preferences synced with iCloud key-value storage.
- Sidebar rebuilt to match the reference: icon rail, expandable panel, collapsed icon column.
- Home, Updates, Messages, My tasks / All tasks (list and board), Projects, Pipeline, Contacts, Reports, Apple services, Settings.
- Apple Contacts import and Apple Reminders mirroring.
- ⌘K command palette, ⌘N new task, ⌘⇧N new project.
- Swift Pieces components across the UI.

## Next: team workspaces with CloudKit sharing

The private database is single-user: it syncs one person's data across their devices. To let a team share a workspace:

- Move shared records into a custom zone and share it with `CKShare` (Share with iCloud, participants, permissions).
- SwiftData doesn't expose CloudKit sharing yet, so this step needs either `NSPersistentCloudKitContainer` with a shared store or direct CloudKit record sync for the shared zone.
- Show participants and presence using `CKShare.Participant` data.

## Later

- Spotlight indexing (`CoreSpotlight`) and App Intents / Shortcuts ("Add a task to Launch").
- Widgets (due today, pipeline) and Live Activities for in-progress tasks.
- Calendar view using EventKit events alongside task due dates.
- Local notifications for tasks not mirrored to Reminders.
- Deploy the CloudKit schema to production before the first TestFlight build.

## Not planned

- Third-party sign-in (Google, GitHub, OIDC, SAML). Identity is the iCloud account.
- Self-hosted servers. Storage is CloudKit.
- Voice/video channels, app marketplace, federated chat.
