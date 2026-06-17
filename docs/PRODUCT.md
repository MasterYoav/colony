# Product Vision

Colony is a self-hosted workspace for communication, customer context, and execution. The product should help a team understand what is happening, who it affects, and what needs to move next.

## Positioning

Colony combines four product categories:

- Team chat: channels, direct messages, threads, reactions, calls later.
- CRM: contacts, companies, deals, notes, activity history, custom objects.
- Project management: tasks, projects, boards, lists, docs, reminders, timelines.
- Internal workspace: search, permissions, notifications, integrations, automation.

The core promise is privacy and ownership without giving up polish. A team should be able to run Colony on its own server and still get an interface that feels smooth, coherent, and modern.

## Target Users

- Small companies that want Slack, CRM, and project work in one place.
- Agencies that manage clients, conversations, deliverables, and sales pipeline.
- Technical teams that prefer self-hosting and open-source infrastructure.
- Personal power users who want a private workspace with GitHub, Google, email, and passkey sign-in.
- Communities that want Discord-like spaces without giving ownership to a cloud platform.

## Product Principles

- Calm by default: avoid clutter, heavy colors, and noisy dashboards.
- Fast everywhere: chat and navigation should feel instant.
- One workspace graph: messages, tasks, contacts, companies, files, and docs should be linkable.
- Customizable without chaos: themes and layout preferences should be structured, not arbitrary CSS pasted into the app.
- Secure by design: authentication, permissions, audit logs, and admin controls are first-class.
- Self-hostable without pain: one-command local deployment first, deeper deployment options later.

## Core Objects

- Workspace: a tenant boundary for users, settings, billing later, auth providers, themes, and data.
- User: a person with identity, security settings, preferences, memberships, and presence.
- Channel: a shared conversation space.
- Message: a chat entry with attachments, reactions, mentions, edits, and thread links.
- Contact: a person tracked in CRM.
- Company: an account or organization tracked in CRM.
- Deal: an opportunity, renewal, partnership, or sales process.
- Project: a group of tasks, docs, and milestones.
- Task: assignable work with status, priority, dates, labels, and relations.
- View: a saved representation of objects, such as list, board, table, calendar, or timeline.
- Theme: a user or workspace visual configuration.

## MVP Scope

The MVP should prove that the product can be useful and self-hosted:

- Create a workspace.
- Invite users.
- Sign in with email, Google, GitHub, and passkeys.
- Create channels.
- Send messages.
- Create contacts and tasks.
- Link a task or contact inside a message.
- Customize basic theme settings.
- Deploy with Docker Compose.

## Out of Scope for MVP

- Native voice and video.
- Full Slack/Discord importers.
- Deep workflow automation.
- Public app marketplace.
- Advanced CRM reporting.
- Enterprise data retention policies.
- Mobile push notification infrastructure.
- AI features.

These can be designed later, after the foundation is stable.
