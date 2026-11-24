import { createBusinessApp } from './business-app.mjs';
import { createFirebaseVerifier } from './business-firebase-identity.mjs';
import { googleServiceAccountToken } from './business-google-credential.mjs';
import { createCredentialVault } from './business-credential-vault.mjs';
import { microsoftBusinessCredential } from './business-microsoft-oauth.mjs';
import { invitationLanding } from './business-invitation-landing.mjs';

/** Isolated Worker: never log credentials, tokens, emails, request bodies or provider responses. */
export function createBusinessWorker(env, overrides = {}) {
  const projectId = env.PHOTOMARK_FIREBASE_PROJECT_ID;
  const ownerEmail = env.BUSINESS_OWNER_EMAIL?.trim().toLowerCase();
  if (!ownerEmail || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(ownerEmail) ||
      !env.BUSINESS_IP_LIMIT || !env.BUSINESS_UID_LIMIT) throw new Error('missing-worker-configuration');
  const authenticate = overrides.authenticate ?? createFirebaseVerifier({ projectId });
  const serverAccessToken = overrides.serverAccessToken ?? googleServiceAccountToken({
    clientEmail: env.BUSINESS_SERVER_EMAIL, privateKey: env.BUSINESS_SERVER_PRIVATE_KEY,
  });
  const preAuthLimit = async request => {
    const ip = request.headers.get('cf-connecting-ip');
    if (!ip || !/^[0-9a-f:.]{2,45}$/i.test(ip)) return false;
    return (await env.BUSINESS_IP_LIMIT.limit({ key: ip })).success === true;
  };
  const rateLimit = async uid => (await env.BUSINESS_UID_LIMIT.limit({ key: uid })).success === true;
  const prepareOneDrive = overrides.prepareOneDrive ?? (async ({ organizationId, ownerId, refreshToken }) => {
    const exchange = microsoftBusinessCredential({ clientId: env.BUSINESS_MICROSOFT_CLIENT_ID,
      ...(overrides.fetchImpl ? { fetchImpl: overrides.fetchImpl } : {}) });
    const verified = await exchange(refreshToken);
    const vault = await createCredentialVault(env.BUSINESS_CREDENTIAL_KEY);
    const sealed = await vault.seal(organizationId, ownerId,
      { refreshToken: verified.refreshToken, providerAccountId: verified.providerAccountId });
    return { ...sealed, providerAccountId: verified.providerAccountId, driveId: verified.driveId };
  });
  const api = createBusinessApp({ projectId, authenticate, serverAccessToken, preAuthLimit, rateLimit,
    prepareOneDrive,
    canCreateOrganization: async identity => identity.emailVerified === true &&
      typeof identity.email === 'string' && identity.email.trim().toLowerCase() === ownerEmail,
    ...(overrides.fetchImpl ? { fetchImpl: overrides.fetchImpl } : {}),
    ...(overrides.emulatorOrigin ? { emulatorOrigin: overrides.emulatorOrigin } : {}),
  });
  return async request => {
    if (new URL(request.url).pathname === '/convite') {
      try { if (!await preAuthLimit(request)) return new Response('Indisponível.', { status: 429 }); }
      catch { return new Response('Indisponível.', { status: 503 }); }
      return invitationLanding(request);
    }
    return api(request);
  };
}

const workers = new WeakMap();
export default {
  async fetch(request, env) {
    try {
      let handler = workers.get(env);
      if (!handler) { handler = createBusinessWorker(env); workers.set(env, handler); }
      return await handler(request);
    } catch {
      return new Response('{"error":"unavailable"}', { status: 503,
        headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });
    }
  },
};
