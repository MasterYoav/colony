# Colony

Colony is planned as a private, self-hosted collaboration workspace: team chat, project execution, CRM records, and business identity in one clean product.

The product direction is inspired by the strengths of Discord, Slack, Plane, ClickUp, and Twenty, but the goal is not to clone any one of them. Colony should feel calm, fast, customizable, and trustworthy: the kind of internal operating system a small team, agency, startup, or community could run on its own infrastructure.

## Product Goals

- Self-hosted by default, with a clean path to managed hosting later.
- Open source, with a license chosen intentionally before public release.
- Private team communication with channels, threads, reactions, files, and search.
- CRM objects for contacts, companies, deals, accounts, and custom records.
- Project management with tasks, boards, lists, timelines, docs, and views.
- Business SSO through Google Workspace, Microsoft Entra ID, OIDC, and SAML.
- Personal sign-in through email, Google, GitHub, passkeys, and optional 2FA.
- User-friendly theming for colors, density, button placement, and navigation style.
- Native-feeling clients, beginning with this SwiftUI app.

## Documentation

- [Product Vision](docs/PRODUCT.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Authentication](docs/AUTH.md)
- [Theming](docs/THEMING.md)
- [Self-Hosting](docs/SELF_HOSTING.md)
- [Roadmap](docs/ROADMAP.md)

## Recommended First Build

The first useful version should be small and complete:

1. Workspace creation.
2. User authentication.
3. Channels and messages.
4. Basic contacts and tasks.
5. Theme preferences.
6. Docker Compose deployment.

That gives Colony a real product core without committing too early to every advanced CRM, project management, automation, or enterprise feature.

## Current App

This repository currently contains a small SwiftUI project. The proposed direction is to use it as the first native Apple client while designing the platform as backend-first and client-agnostic.
