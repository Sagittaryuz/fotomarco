import { importPKCS8, SignJWT } from 'jose';

const tokenURL = 'https://oauth2.googleapis.com/token';
const scope = 'https://www.googleapis.com/auth/datastore';

/** Private key and email are supplied through trusted server secrets, never by the client. */
export function googleServiceAccountToken({ clientEmail, privateKey, fetchImpl = fetch, now = () => Date.now() }) {
  if (typeof clientEmail !== 'string' || !/^[a-z0-9-]+@[a-z0-9-]+\.iam\.gserviceaccount\.com$/.test(clientEmail) ||
      typeof privateKey !== 'string' || !privateKey.startsWith('-----BEGIN PRIVATE KEY-----')) throw new Error('invalid-server-credential');
  let cached, expires = 0, inFlight, key;
  return async () => {
    if (cached && now() < expires) return cached;
    if (inFlight) return inFlight;
    inFlight = (async () => {
      const issued = Math.floor(now() / 1000);
      key ??= await importPKCS8(privateKey, 'RS256');
      const assertion = await new SignJWT({ scope }).setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
        .setIssuer(clientEmail).setAudience(tokenURL).setIssuedAt(issued).setExpirationTime(issued + 3600).sign(key);
      const body = new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion });
      const response = await fetchImpl(tokenURL, { method: 'POST', redirect: 'manual',
        headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: body.toString() });
      if (!response.ok) throw new Error('server-token-unavailable');
      const data = await response.json();
      if (typeof data.access_token !== 'string' || !data.access_token || data.token_type?.toLowerCase() !== 'bearer' ||
          !Number.isFinite(data.expires_in) || data.expires_in <= 120 || data.expires_in > 3600) throw new Error('invalid-server-token');
      cached = data.access_token;
      expires = now() + (data.expires_in - 120) * 1000;
      return cached;
    })();
    try { return await inFlight; } finally { inFlight = undefined; }
  };
}
