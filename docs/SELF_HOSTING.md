# Self-Hosting

Self-hosting is a primary product requirement. Colony should be easy to run for a small team and still have a path to serious production deployments.

## Principles

- Docker Compose first.
- Clear environment variables.
- No required outbound calls for core usage.
- Local object storage support.
- Backup and restore documented early.
- Production deployment should not require deep platform knowledge.

## Initial Services

The first self-hosted deployment should include:

- App/API service.
- Worker service.
- PostgreSQL.
- Redis.
- MinIO or another S3-compatible object store.
- Reverse proxy with TLS.

Optional later:

- Search service.
- Metrics.
- Tracing.
- External identity provider.
- Email delivery service.

## Required Configuration

Expected environment categories:

- Public URL.
- Database URL.
- Redis URL.
- Object storage endpoint and credentials.
- Email SMTP settings.
- Signing secrets.
- OAuth provider credentials.
- OIDC/SAML provider settings.

## Deployment Targets

### Local Development

Use Docker Compose with seeded data and local services.

### Small Team Production

Use Docker Compose on a VPS or private server:

- PostgreSQL volume.
- Object storage volume or external S3 bucket.
- Reverse proxy with HTTPS.
- Scheduled backups.

### Larger Production

Use Kubernetes or a managed container platform:

- Managed PostgreSQL if acceptable.
- S3-compatible object storage.
- Redis with persistence if needed.
- Horizontal app and worker replicas.
- Separate search and observability services.

## Backups

Backups must cover:

- PostgreSQL database.
- Object storage files.
- Environment and secrets.
- Identity provider configuration if external.

Restore should be tested and documented before beta release.

## Updates

Self-hosted updates should be predictable:

- Versioned releases.
- Database migrations.
- Release notes.
- Rollback guidance where possible.
- Compatibility notes for clients.

## Security Baseline

Production installs should require:

- HTTPS.
- Strong app secrets.
- Secure cookies or equivalent token storage.
- Restricted admin registration.
- Email verification.
- Optional 2FA enforcement.
- Audit logging.

## Open Questions

- Should the official deployment include an embedded identity provider, or only document external IdP setup?
- Should search be required from day one or optional?
- Should object storage default to local filesystem for the smallest installs?
