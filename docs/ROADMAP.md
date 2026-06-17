# Roadmap

This roadmap keeps the project focused. The product is large enough that sequencing matters more than feature count.

## Phase 0: Foundation

- Decide license.
- Decide backend stack.
- Create architecture decision records.
- Define database schema for workspaces, users, channels, messages, contacts, and tasks.
- Define API and realtime event conventions.
- Define design tokens.
- Create local development deployment.

## Phase 1: Usable Core

- Workspace creation.
- Email auth.
- Google and GitHub login.
- Passkey registration and sign-in.
- User invitations.
- Channels.
- Messages.
- Threads.
- Reactions.
- Basic file attachments.
- Contacts.
- Tasks.
- User theme preferences.

## Phase 2: Team Workflow

- Projects.
- Boards and lists.
- Saved views.
- Mentions.
- Notifications.
- Message search.
- Object links inside messages.
- CRM company and deal records.
- Activity timeline across CRM and work objects.
- Role-based permissions.

## Phase 3: Business Identity

- Microsoft Entra ID login.
- Google Workspace controls.
- Generic OIDC.
- Generic SAML.
- Workspace SSO enforcement.
- 2FA enforcement.
- Session/device management.
- Security audit log.

## Phase 4: Self-Hosted Production

- Docker Compose production template.
- Backup and restore docs.
- Upgrade docs.
- Admin setup screen.
- Health checks.
- Metrics endpoint.
- Email configuration test tools.
- Object storage configuration test tools.

## Phase 5: Polish and Scale

- Advanced theming.
- Keyboard command menu.
- Import/export.
- Webhooks.
- Automation rules.
- Search service.
- Mobile push notification architecture.
- AI features if they can run with user-controlled providers.

## Non-Goals Until Later

- Full Discord voice channels.
- Large app marketplace.
- Advanced BI/reporting.
- Public community discovery.
- Federated chat.
- Complex enterprise retention and legal hold.
