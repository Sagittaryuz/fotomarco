# Photomark Business: deployment configuration

`wrangler.business.json` is an isolated Worker configuration; it does not deploy the installer or change any existing Worker. Deploy only after authorization, security checks, and successful real-provider testing. The Firebase project is the dedicated Photomark Business project.

The deployment must provision these environment values through protected secrets or configuration; never commit private keys, refresh tokens, or account credentials:

- `BUSINESS_OWNER_EMAIL`: initial owner identity; the server requires a verified Firebase identity matching this value.
- `BUSINESS_SERVER_EMAIL`, `BUSINESS_SERVER_PRIVATE_KEY`: dedicated Google service identity with only the Firestore permissions required by the backend.
- `BUSINESS_CREDENTIAL_KEY`: independent cryptographically random key accepted by the credential vault. Losing or rotating it without a migration invalidates the encrypted provider credentials.
- `BUSINESS_MICROSOFT_CLIENT_ID`, `BUSINESS_GOOGLE_CLIENT_ID`: registered client identifiers matching the official provider configurations.
- `BUSINESS_PUBLIC_ORIGIN`: verified HTTPS origin of this isolated Worker for invitation callbacks.

The configuration binds `BUSINESS_IP_LIMIT` and `BUSINESS_UID_LIMIT` separately. Cloudflare's limits are approximate and local to each location, not globally strict; account-wide free quotas are still shared. Confirm namespaces are unused and verify account limits before deployment. Do not enable request logging because request data and identifiers can be sensitive.

Before enabling the app endpoint, confirm anonymous requests fail closed, use a synthetic test organization and two consenting test identities to verify OneDrive folder ACLs and revocation, and confirm private profile and photo access. Then configure the app's `PHOTOMARK_BUSINESS_API` for the signed candidate. Do not migrate or rename historical user photographs until the upgraded app, provider receipts, and rollback behavior have been verified. See `firestore.rules` for the deny-all client access policy: the backend's IAM permissions still need separate review.

## Local validation (24 Nov 2026)

The current business service passed the Firestore emulator suite (9 tests, no skips), including owner bootstrap idempotency, membership isolation, invitation acceptance, folder binding and capture reservation. The separate client security-rules emulator test denies anonymous and signed-in reads, writes and deletes. These tests use synthetic users and fake provider responses; they do not verify real Microsoft sharing, email delivery, deployment, or device behavior.

## Initial organization storage

The initial organization is named JMD Hamoa, but its initial storage is the owner's personal OneDrive account associated with `mrpires72@gmail.com`. The organization name must not be interpreted as a request to connect a JMD corporate Microsoft tenant. The storage account still needs to be connected and verified using the actual Microsoft identity and drive ID; the email alone does not prove ownership or access.

A later change to another OneDrive account requires an explicit, separately verified migration. Preserve the originals and access to the existing drive until every copy and its ownership, metadata, integrity, member access, and gallery references have been checked. Do not switch the active drive or delete original photos merely because a new account has been connected. The current implementation intentionally rejects switching to a different account or drive; a migration workflow has not yet been implemented or validated.

The development branch contains a user-scoped storage identity comparison and migration bookkeeping. These do not by themselves establish a working transfer: the worker, real provider access, persistent copy orchestration, member permissions and rollback still require end-to-end verification. Business-personal delivery must remain pending when an identity cannot be verified, and local copies must be retained.
