# Momentra OAuth broker (not yet native-validated)

One dependency-free module: `worker.mjs`. Deployment is NOT performed by these files. Default is identity-only (`openid email profile`). Version 0.4.0 additionally supports an opt-in exact personal Photos scope set when `ENABLE_GOOGLE_PHOTOS` is the string `true`: identity plus `photoslibrary.appendonly` and `photoslibrary.readonly.appcreateddata`. Scope set is authenticated inside both envelopes and must match the provider token response exactly. Basic login never adds Photos automatically. The broker handles OAuth only, not photo uploads, Maps, refresh tokens, account-management operations or a database.

`GET /privacy` serves a static Portuguese notice with hardened no-store/CSP headers. `GET /health` reports service version and `capabilities.photos`, not successful Google setup or native validation. App Photos tokens use separate device-local Keychain and an allowlisted Google transport; every operation binds the account and cancels on account changes. Scripting fetch uses documented `handleRedirect` rather than Web `redirect`; Cloudflare still uses its documented `redirect: manual`.

The sections below retain identity architecture and historical test evidence; the new exact Photos scope set is an explicit second mode, not unrestricted scope forwarding.

## Dedicated destination and setup

Only Worker `momentra-auth`, origin `https://momentra-auth.mrpires72.workers.dev`. Do not modify the account's other Worker or its bindings. Keep Workers Free; do not enable paid products, logs or billing. A free-account request quota is shared across its Workers; this broker can consume capacity and cannot guarantee availability to other Workers under abuse.

Google OAuth client type: Web application. Authorized redirect URI exactly:
`https://momentra-auth.mrpires72.workers.dev/callback`

Environment:
- `ENABLE_GOOGLE_PHOTOS`: optional plain string `true` only after dedicated Google Photos Library API/scopes have been configured; absent/other values disable Photos. No automatic consent or upload.
- `GOOGLE_CLIENT_ID`: public OAuth client ID, `486055841789-ogbp6b16gvl0nhtcdun8fvla56p5e0rc.apps.googleusercontent.com`.
- `GOOGLE_CLIENT_SECRET`: Cloudflare secret, never repository/code/log/chat.
- `BROKER_SECRET`: independent cryptographically random **32 bytes**, encoded base64url **without padding** (43 characters), stored as Cloudflare secret. Rotation invalidates pending logins, not Google grants.
- `AUTH_RATE_LIMITER`: Cloudflare Rate Limiting binding. Dedicated namespace not shared with other Workers; suggested limit 20 per 60 seconds. Requires this binding and Cloudflare's trusted CF-Connecting-IP header; missing/failing binding returns 503. Confirm its availability on the existing free account before enabling; do not upgrade to satisfy it.

No `BROKER_ORIGIN` setting: destination and app callback are constants. Disable Invocation logs, Workers observability, tail forwarding and any logs containing request URLs, query strings or headers. Do not configure external analytics for OAuth routes. The code has no logging. `/health` is a public readiness-independent identity of the service, not proof that OAuth works.

Example binding fragment for deployment tooling (select a unique namespace for this account):
```json
{"ratelimits":[{"name":"AUTH_RATE_LIMITER","namespace_id":"<dedicated-positive-integer>","simple":{"limit":20,"period":60}}]}
```
Rate limiting is approximate/per Cloudflare location, not a global strict counter or financial cap. Every request may still count against Free quota. No paid scaling is enabled here.

## Protocol and security boundary

1. Scripting OAuth2 calls `/authorize` with public Google client ID, EXACT `scripting://oauth_callback/Momentra`, response_type code, scope openid/email/profile, cryptographic state (>=32 characters), S256 challenge.
2. Worker substitutes its HTTPS callback and AES-256-GCM encrypts/authenticates state, challenge, client ID and 10-minute expiry. Google sees that envelope as state, never a client-controlled return address.
3. `/callback` authenticates state, normalizes errors, and returns only original client state plus an **encrypted/authenticated code envelope**, with maximum 2-minute expiry, to the fixed Scripting callback. Raw Google codes and tokens are never sent in the app callback URL.
4. OAuth2 sends envelope + verifier to `/token` as form POST. Worker authenticates the envelope, checks local S256 proof, then submits Google code/verifier using its server-side secret and HTTPS callback.
5. Worker returns access token/expiry/identity scope only in a no-store JSON body. Drops refresh token, ID token and unknown fields; rejects extra scopes. Google enforces code one-time use. Requests and all exceptions are sanitized, never logged.

The Worker is a PUBLIC-client bridge, not an attestation that code came from the genuine Momentra UI. Any person can start their own identity consent flow with this public client ID; that cannot be prevented by a secret embedded in a public script. State protects the caller's pending login; the PKCE verifier protects code redemption. Do not grant extra backend authority merely because somebody used this client. Never disable native state checks.

Stateless anti-replay relies on Google accepting each code only once, plus short TTL; there is no broker revocation database. Native custom schemes may be claimed/intercepted by other apps: envelopes still require the verifier. Native return behavior and Google's web-client PKCE interoperability remain deployment/iPhone test gates, not tested by Node mocks.

## Scripting contract

See `scripting-example.ts` (example only, not imported into the app). `consumerSecret:'public-client'` is a PUBLIC compatibility placeholder, not the Google secret. Native OAuth2 state validation stays enabled; Basic authentication stays disabled. Callback script name must be exactly Momentra. Token expiry is milliseconds per Scripting docs. Token/identity persist only in per-script Keychain, non-synchronizing and device-unlocked. Never print returned credentials or native errors. Login grants identity only; it does NOT configure Google Photos/Maps. Local disconnect does not revoke at Google.

## Local tests

Run `node --test backend/worker.test.mjs` from repo root. Tests use synthetic secrets and a mocked Google endpoint. Cover state/code tampering, expiry, verifier mismatch, scopes, destinations, query duplication, raw-code exchange rejection, replay response, size limits, rate-limit fail-closed, clean errors and standard Workers handler signature. No network or real OAuth grant is used.

## Official references consulted
- [Scripting OAuth2](https://scriptingapp.github.io/guide/Utilities/OAuth2), plus local official Keychain/Crypto/Data documentation.
- [Google web-server OAuth](https://developers.google.com/identity/protocols/oauth2/web-server) and [PKCE](https://developers.google.com/identity/protocols/oauth2/native-app).
- [Cloudflare rate limiting bindings](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/) and [secrets](https://developers.cloudflare.com/workers/configuration/secrets/).

## App integration delivered
`../google_auth.ts` exposes `getGoogleIdentity()` (synchronous local-only), `loginGoogle()` (explicit user consent only), and `logoutGoogle()` (local removal, not Google revocation). Status is `signed-out` / `unavailable`, or `connected` / `expired` with `{identity:{sub,name,email}, expiresAt}`. Returns never contain tokens. Email is returned only if Google marks it verified. Empty `consumerSecret` is intentional: the real secret lives only in the Worker. No automatic login at first opening; camera must remain usable without Google. In-flight login results are invalidated by sign-out. Host integration and real Google OAuth on iPhone remain unvalidated.

Run isolated mocked app tests: `node --test tests/google_auth.cjs` (14 cases). These do not replace native Scripting validation. Worker tests remain 26 synthetic cases. Binding configured by coordinator: `AUTH_RATE_LIMITER`, namespace `2026111601`, 20/60s. No deploy or app wiring performed by this module task.

### Callback issuer compatibility correction
Real Google consent returned the additional `iss` query parameter, causing the strict callback allowlist to reject the response. The callback now permits optional `iss` only when exactly `https://accounts.google.com`; empty, other and duplicate values are rejected. Regression suite: 28/28 synthetic tests. This addresses the observed parser failure, not proof of a complete real token exchange.

### Cloudflare redirect compatibility correction
Cloudflare documents `redirect: 'error'` as unsupported: it throws before sending the request. Changed only this option to `manual`. Existing `!response.ok` rejects 3xx as `invalid_grant` without following Location. Regression tests explicitly cover 301/302/303/307/308, single fetch call, no response Location and no follow. Backend suite: 29/29 synthetic tests. Source: https://developers.cloudflare.com/workers/runtime-apis/request/

### HTTPS callback landing · deployed in 0.3.7
The callback now returns an HTTPS200 HTML page with a single explicit “Voltar ao Momentra” link, instead of an automatic302 to the custom scheme. Scripting's official OAuth2 authorize API opens a browser and accepts callbackURL (default scripting://oauth_callback/{script}); this preserves that callback and the PKCE/state exchange. The documentation does not guarantee this particular intermediate page on every native version: physical iPhone validation remains required.

No JavaScript, automatic navigation, forms, external resources or raw Google code/token in HTML. The href is HTML-escaped and its destination remains the fixed Momentra callback with encrypted code and original state. Existing2min code TTL,10min state TTL, issuer validation and verifier checks are unchanged. Headers prohibit caching, referrers, framing, forms and base URL changes. Reloading can issue another opaque wrapper within the state lifetime, as before; Google single-use code and PKCE still govern exchange. The incoming HTTPS callback URL necessarily contains Google's authorization code/state and can remain in browser history: do not capture/share URLs or enable request logs. This is not a workaround for browser security warnings or blocked navigation. User gesture may permit returning to Scripting but Windows handler availability remains an unconfirmed hypothesis.

31 synthetic backend tests pass, including clean error return, header/script/resource constraints, hostile-looking state round-trip, TTL, tamper and replay rejection. App code and credentials unchanged. Published Worker revision 6b15eee7 after the owner explicitly approved this live authentication behavior. Real PC flow confirmed authorize/Google consent, HTTPS200 callback with matching state, Worker token200, userinfo200 with verified owner email, no refresh token, and replay400 invalid_grant. Tokens stayed in memory; temporary test file removal was verified by the coordinator. Native Scripting callback and Keychain remain untested.
