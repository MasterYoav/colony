# Roadmap

## Done: native redesign

- SwiftData models synced to the private iCloud database through CloudKit.
- Preferences synced with iCloud key-value storage.
- Sidebar rebuilt to match the reference: single panel with footer controls, collapsible to an icon column.
- Home, Updates, Inbox, Tasks (list and board), Projects, CRM (customers table grouped by stage + pipeline board), Reports, Settings (System Settings layout, profile photo).
- Sidebar music controller for the device's own player (Music on Mac, system music player on iPhone/iPad).
- Frosted glass sidebar with Agents and Automations sections (preview crew with blinking faces; the features themselves are the next two phases).
- Apple Contacts import and Apple Reminders mirroring.
- Tasks laid out like Apple Reminders: smart-list tiles, in-place editing, flags, date-only or timed due dates.
- Due-time notifications with Complete / Remind Me in 1 Hour (delivered with Colony closed), an optional menu-bar mode and Open at Login on Mac.
- "Colony" calendar in Apple Calendar with dated tasks and automation schedules.
- ⌘K command palette, ⌘N new task, ⌘⇧N new project.
- Swift Pieces components across the UI.

## Done — Phase 1: Agents

Assistants that work alongside you, running on device with Apple Intelligence (Foundation Models framework). No third-party AI. See [Agents and AGENT.md](AGENTS.md).

- [x] `Agent` and `AgentMessage` models in SwiftData, synced through iCloud; the sidebar shows the real crew.
- [x] Recruit agents from AGENT.md files (import, drag and drop, templates, or write one), with a preview and warnings; edit and export AGENT.md.
- [x] Agent page: streaming chat, suggested prompts, action rows for everything the agent did, AGENT.md inspector, Run now, pause, clear.
- [x] Tools through `WorkspaceActions`: tasks, projects, customers, channels, Updates, and `ask_user`.
- [x] Schedules (hourly, daily, weekdays, weekly), once per slot across devices; shown in the Colony calendar.
- [x] Live status in the sidebar pill (Idle / Thinking / Waiting for you / Done) and a notification when an agent needs you.
- [x] Starter agents: daily planner, customer follow-ups, channel digest, weekly report.
- [x] Fallback when Apple Intelligence isn't available: explains why; agents stay readable and editable.
- [x] Privacy policy updated.

Later: background runs on iPhone and iPad with `BGTaskScheduler`, and agents that hand work to automations.

## Next — Phase 2: Automations

Rules that run when something changes in the workspace. No AI required.

- [ ] `Automation` model in SwiftData (trigger, conditions, actions, enabled, last run) synced through iCloud; replace the preview list.
- [ ] Triggers: task status or due date changes, task overdue, customer stage changes, new message, schedule (daily/weekly).
- [ ] Actions: set priority or status, create a task or list, move a customer, post to a channel, add to Updates, mirror to Reminders.
- [ ] Builder UI: "When … if … then …" with a run log and a test-run button.
- [ ] Runs while the app is open, and in the background via `BGTaskScheduler` on iPhone/iPad where allowed.
- [ ] Starter automations: overdue nudge, deal won → onboarding list, ready for review → post to channel, weekly cleanup.

## Then: team workspaces with CloudKit sharing

The private database is single-user: it syncs one person's data across their devices. To let a team share a workspace:

- Move shared records into a custom zone and share it with `CKShare` (Share with iCloud, participants, permissions).
- SwiftData doesn't expose CloudKit sharing yet, so this step needs either `NSPersistentCloudKitContainer` with a shared store or direct CloudKit record sync for the shared zone.
- Show participants and presence using `CKShare.Participant` data.

## Later

- Spotlight indexing (`CoreSpotlight`) and App Intents / Shortcuts ("Add a task to Launch").
- Widgets (due today, pipeline) and Live Activities for in-progress tasks.
- Calendar view inside Colony using EventKit events alongside task due dates.
- Real automation schedules in Calendar once Automations ship (Phase 2); today it shows the preview crew's.
- Early reminders (e.g. 15 minutes before) and repeating tasks.
- Deploy the CloudKit schema to production before the first TestFlight build.

## Not planned

- Third-party sign-in (Google, GitHub, OIDC, SAML). Identity is the iCloud account.
- Self-hosted servers. Storage is CloudKit.
- Voice/video channels, app marketplace, federated chat.
