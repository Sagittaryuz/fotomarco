import { decodeProtectedHeader, importX509, jwtVerify } from 'jose';

const certificatesURL = 'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';

/** Validates Firebase ID tokens, not Google/OneDrive OAuth tokens. */
export function createFirebaseVerifier({ projectId, fetchImpl = fetch, now = () => Date.now(), resolveKey } = {}) {
  if (typeof projectId !== 'string' || !/^[a-z0-9-]{6,30}$/.test(projectId)) throw new Error('invalid-project');
  let cached = null;
  let expires = 0;
  async function googleKey(kid) {
    if (!cached || now() >= expires || !cached[kid]) {
      const response = await fetchImpl(certificatesURL, { redirect: 'manual' });
      if (!response.ok) throw new Error('firebase-certificates-unavailable');
      const keys = await response.json();
      if (!keys || typeof keys !== 'object' || Array.isArray(keys)) throw new Error('invalid-certificates');
      const match = /(?:^|,)\s*max-age=(\d+)/i.exec(response.headers.get('cache-control') ?? '');
      const seconds = Math.min(match ? Number(match[1]) : 0, 86400);
      cached = keys;
      expires = now() + seconds * 1000;
    }
    if (typeof cached[kid] !== 'string') throw new Error('unknown-signing-key');
    return importX509(cached[kid], 'RS256');
  }
  return async token => {
    if (typeof token !== 'string' || token.length > 16384) throw new Error('invalid-token');
    const header = decodeProtectedHeader(token);
    if (header.alg !== 'RS256' || typeof header.kid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(header.kid)) throw new Error('invalid-token');
    const key = await (resolveKey ?? googleKey)(header.kid);
    const { payload } = await jwtVerify(token, key, { algorithms: ['RS256'], audience: projectId,
      issuer: `https://securetoken.google.com/${projectId}`, requiredClaims: ['exp', 'iat', 'sub', 'auth_time'], currentDate: new Date(now()) });
    const seconds = Math.floor(now() / 1000);
    if (typeof payload.sub !== 'string' || payload.sub.length === 0 || payload.sub.length > 128 ||
        !Number.isSafeInteger(payload.iat) || payload.iat > seconds ||
        !Number.isSafeInteger(payload.auth_time) || payload.auth_time > seconds) throw new Error('invalid-token');
    const displayName = typeof payload.name === 'string' ? payload.name.trim() : '';
    return { uid: payload.sub, email: typeof payload.email === 'string' ? payload.email : undefined,
      emailVerified: payload.email_verified === true,
      ...(displayName && displayName.length <= 160 && !/[\x00-\x1f\x7f]/.test(displayName) ? { displayName } : {}) };
  };
}
