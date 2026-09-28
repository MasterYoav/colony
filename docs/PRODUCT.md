# Product Vision

Colony is a private workspace for Apple devices. It brings projects and tasks, channels, and a lightweight CRM into one calm app that helps you see what's happening, who it affects, and what needs to move next.

## Principles

- **Your iCloud, your data.** Everything is stored in the user's private iCloud database. Colony runs no server and uses no third-party services.
- **Apple-native integrations.** Contacts, Reminders, Mail, Phone, FaceTime and the share sheet instead of external accounts.
- **Calm by default.** Dark, low-contrast chrome, hairline borders and quiet counts. Color is reserved for projects and status.
- **Fast everywhere.** Navigation is instant and data is local-first; CloudKit syncs in the background.
- **One workspace graph.** Tasks, projects, messages and people are linked.

## Core objects

- **Project**: a group of lists and tasks, with an icon and color.
- **List**: a sub-group inside a project (sprints, months, phases). Lists appear as expandable children in the sidebar.
- **Task**: status, priority, due date and notes. Can be mirrored to Apple Reminders.
- **Channel / Message**: threaded notes and conversations.
- **Contact**: a person in the CRM with a pipeline stage. Can be imported from Apple Contacts.
- **Activity**: the Updates feed of what changed.

## Navigation

The sidebar follows the reference design:

1. **Header**: workspace switcher and collapse button, sharing the title bar with the window controls on Mac.
2. **Panel**: ⌘K command field, Home / Updates / Inbox / My tasks, a **Workspace** section and a **Projects** section. Projects expand to show their lists with open-task counts.
3. **Footer**: account, appearance, iCloud status and settings.
4. **Collapsed**: icon-only column with the same items, project glyphs and footer.

## Out of scope for now

- Multi-person workspaces (see Roadmap: CloudKit sharing).
- Voice and video.
- Importers from Slack, Discord or other tools.
- AI features.
