# Product Vision

Colony is a private workspace for Apple devices. It brings projects and tasks, channels, and a lightweight CRM into one calm app that helps you see what's happening, who it affects, and what needs to move next.

## Principles

- **Your iCloud, your data.** Everything is stored in the user's private iCloud database. Colony runs no server and uses no third-party services.
- **Apple-native integrations.** Contacts, Reminders, Calendar, notifications, Music, Mail, Phone, FaceTime and the share sheet instead of external accounts.
- **Calm by default.** Dark, low-contrast chrome, hairline borders and quiet counts. Color is reserved for projects and status.
- **Fast everywhere.** Navigation is instant and data is local-first; CloudKit syncs in the background.
- **One workspace graph.** Tasks, projects, messages and people are linked.

## Core objects

- **Project**: a group of lists and tasks, with an icon and color.
- **List**: a sub-group inside a project (sprints, months, phases). Lists appear as expandable children in the sidebar.
- **Task**: status, priority, flag, due date (with or without a time) and notes. Laid out like Apple Reminders (smart lists Today, Scheduled, All, Flagged, Urgent, Completed; edit in place). Optional due-time alerts, a "Colony" calendar in Apple Calendar, and mirroring to Apple Reminders.
- **Channel / Message**: threaded notes and conversations.
- **Customer**: a person in the CRM with a deal stage and an optional deal value. Can be imported from Apple Contacts.
- **Activity**: the Updates feed of what changed.
- **Agents**: on-device assistants, each defined by an AGENT.md file, that read and change the workspace through the same actions you use. See [Agents](AGENTS.md).

## Navigation

The sidebar follows the reference design:

1. **Header**: workspace switcher and collapse button, sharing the title bar with the window controls on Mac.
2. **Panel**: Search (⌘K) beside the workspace switcher, one reorderable list (Home, Updates, Projects, Tasks, CRM, Inbox, Reports) with projects nested under Projects, then the Agents and Automations sections.
3. **Bottom**: the music controller, then account, appearance, iCloud status and settings.
4. **Collapsed**: icon-only column with the same items and footer.

## Out of scope for now

- Multi-person workspaces (see Roadmap: CloudKit sharing).
- Voice and video.
- Importers from Slack, Discord or other tools.
- Cloud AI. Agents use Apple Intelligence on the device only.
