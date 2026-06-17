# Authentication

Authentication is a core product feature, not a bolt-on. Colony needs to support personal users, teams, and enterprise identity without forcing every self-hosted install to run complex identity infrastructure.

## Requirements

- Email sign-in.
- Google sign-in.
- GitHub sign-in.
- Microsoft sign-in.
- Passkey sign-in using WebAuthn/FIDO2.
- Optional 2FA using TOTP and security keys.
- Business SSO using Google Workspace and Microsoft Entra ID.
- Enterprise SSO using OIDC and SAML.
- Workspace-level auth provider configuration.
- Admin controls for requiring 2FA or SSO.
- Session management and device revocation.

## Recommended Model

Colony should have an auth abstraction inside the app, but avoid building every identity protocol from scratch.

For self-hosted deployments, support two modes:

- Built-in auth: email, social login, passkeys, and TOTP.
- External IdP mode: Keycloak, ZITADEL, Authentik, or another OIDC/SAML provider.

The application should trust OIDC as the main boundary for external identity. SAML should be supported for enterprise compatibility, either directly or through an identity provider adapter.

## Identity Providers

### Personal Providers

- Email magic link or email plus password.
- Google OAuth/OIDC.
- GitHub OAuth.
- Microsoft personal accounts later.
- Passkeys.

### Business Providers

- Google Workspace through OIDC.
- Microsoft Entra ID through OIDC.
- Generic OIDC.
- Generic SAML 2.0.

## Passkeys

Passkeys should be first-class:

- Users can create a passkey after account creation.
- Users can sign in with a passkey when supported by the client.
- Workspace admins can require passkeys or 2FA for members.
- Recovery flows must be explicit and auditable.

Native Apple clients should use platform passkey support. Web clients should use WebAuthn.

## 2FA

Supported methods:

- TOTP authenticator apps.
- Security keys through WebAuthn.
- Backup recovery codes.

Avoid SMS 2FA for the initial product.

## Sessions

Sessions should be workspace-aware but user-owned:

- Store refresh/session tokens securely.
- Support device list and revocation.
- Rotate refresh tokens.
- Expire inactive sessions.
- Keep audit logs for security-sensitive events.

## Authorization

Authentication proves who the user is. Authorization decides what they can do.

Initial roles:

- Owner: full workspace control.
- Admin: manage users, settings, channels, and objects.
- Member: normal collaboration.
- Guest: limited access to selected channels, projects, or CRM records.

Every API request must include workspace context and be checked against server-side permissions.

## Security Events

Audit these events:

- User invited.
- User joined.
- User removed.
- Role changed.
- Auth provider added, changed, or removed.
- Passkey added or removed.
- 2FA enabled or disabled.
- Session revoked.
- SSO enforced or disabled.
- Failed admin-level access attempt.

## Open Questions

- Should built-in auth use a library or a dedicated auth service?
- Should enterprise SAML be available in the open-source edition from day one?
- Should each workspace be allowed multiple active enterprise identity providers?
- Should personal accounts be able to belong to multiple workspaces with different auth policies?
