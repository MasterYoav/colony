# Architecture

Colony should be designed as a backend-first platform with multiple clients. The SwiftUI app in this repository can become the first Apple client, but the data model and API should not depend on Apple platforms.

## System Shape

The recommended initial architecture is a modular monolith with clear internal boundaries:

- Web/API server
- Realtime gateway
- Background worker
- PostgreSQL database
- Redis cache and pub/sub
- S3-compatible object storage
- Search service later
- Identity provider integration

A modular monolith is the right starting point because the product surface is large. It keeps deployment simple while still allowing modules to split into services if scale demands it.

## Suggested Stack

The exact stack can change, but the first serious implementation should optimize for self-hosting, hiring, and long-term maintenance.

- Backend: TypeScript with NestJS/Fastify, or Go if we prioritize a compact binary.
- Database: PostgreSQL.
- Realtime: WebSockets backed by Redis pub/sub.
- Jobs: worker process with durable job queue.
- Object storage: S3 API, with MinIO for local/self-hosted installs.
- Search: Meilisearch for simplicity or OpenSearch for heavier enterprise needs.
- Web client: React/Next.js if a web app is added.
- Apple client: SwiftUI.
- Auth: internal auth adapter backed by OIDC/SAML providers and optional external IdP.

## Modules

### Identity

Owns users, sessions, auth providers, passkeys, 2FA configuration, invitations, and workspace membership.

### Workspace

Owns tenant settings, roles, permissions, audit logs, theme defaults, notification policies, and admin controls.

### Messaging

Owns channels, direct messages, messages, threads, reactions, mentions, read state, attachments, and presence.

### CRM

Owns contacts, companies, deals, notes, activities, custom fields, and object relations.

### Work

Owns projects, tasks, statuses, labels, assignments, dates, views, docs, and milestones.

### Integrations

Owns OAuth connections, webhooks, sync jobs, external account links, and provider-specific adapters.

### Theming

Owns theme tokens, user preferences, workspace defaults, density, navigation layout, and command/button customization.

## Data Model Rules

- Every business record belongs to a workspace.
- Prefer stable IDs over mutable slugs.
- Model object relations explicitly so messages, tasks, contacts, companies, and deals can link to each other.
- Keep audit fields on important records: createdBy, updatedBy, createdAt, updatedAt.
- Use soft deletion for user-facing collaborative records.
- Treat files as metadata records pointing at object storage keys.

## API Design

Use a versioned API from the start:

- `/api/v1/auth`
- `/api/v1/workspaces`
- `/api/v1/channels`
- `/api/v1/messages`
- `/api/v1/crm`
- `/api/v1/projects`
- `/api/v1/tasks`
- `/api/v1/themes`

Realtime events should be explicit and typed:

- `message.created`
- `message.updated`
- `reaction.added`
- `channel.read`
- `task.updated`
- `contact.updated`
- `presence.changed`
- `theme.updated`

## Permission Model

Start with role-based access control and leave room for attribute-based rules later.

Default roles:

- Owner
- Admin
- Member
- Guest

Permission checks should happen server-side in every module. Clients can hide controls for UX, but the backend must enforce all access decisions.

## Client Architecture

Clients should consume the same API and realtime events.

The SwiftUI app should eventually use:

- A small API client layer.
- Observable state models.
- Local cache for recent messages and records.
- Optimistic updates for chat and task changes.
- System support for passkeys and secure token storage.

## Deployment Architecture

Initial Docker Compose services:

- `app`
- `worker`
- `postgres`
- `redis`
- `minio`
- `reverse-proxy`

Later optional services:

- `search`
- `metrics`
- `tracing`
- `identity`

## Architecture Decision Records

Major decisions should be captured in short ADR files under `docs/adr/` once implementation starts.
