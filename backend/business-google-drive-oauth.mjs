/** Verify a delegated app-file Drive credential and bind it to a verified owner. */
export function googleBusinessDriveCredential({ clientId, fetchImpl = fetch }) {
  if (typeof clientId !== 'string' || !/^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$/.test(clientId)) throw new Error('invalid-google-client');
  return async refreshToken => {
    if (typeof refreshToken !== 'string' || !refreshToken || refreshToken.length > 16384 || /[\x00-\x1f\x7f]/.test(refreshToken)) throw new Error('invalid-provider-credential');
    const request = async (url, options) => {
      try {
        const response = await fetchImpl(url, { ...options, redirect: 'manual', signal: AbortSignal.timeout(15000) });
        if (response.status !== 200) throw new Error('upstream failure');
        const body = await response.json();
        if (!body || typeof body !== 'object') throw new Error('invalid response');
        return body;
      } catch { throw new Error('provider-unavailable'); }
    };
    const form = new URLSearchParams({ client_id: clientId, grant_type: 'refresh_token', refresh_token: refreshToken });
    const token = await request('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: form.toString() });
    const rotated = token.refresh_token ?? refreshToken;
    if (typeof token.access_token !== 'string' || !token.access_token || token.access_token.length > 16384 ||
        typeof rotated !== 'string' || !rotated || rotated.length > 16384 || typeof token.scope !== 'string' ||
        !token.scope.split(/\s+/).includes('https://www.googleapis.com/auth/drive.file')) throw new Error('provider-permission-missing');
    const headers = { authorization: `Bearer ${token.access_token}` };
    const profile = await request('https://openidconnect.googleapis.com/v1/userinfo', { headers });
    if (profile.email_verified !== true || typeof profile.email !== 'string' || profile.email.length > 254 ||
        !/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(profile.email) || typeof profile.sub !== 'string' || !profile.sub || profile.sub.length > 256) throw new Error('provider-identity-mismatch');
    const about = await request('https://www.googleapis.com/drive/v3/about?fields=user(me%2CpermissionId%2CemailAddress)', { headers });
    if (about.user?.me !== true || typeof about.user.permissionId !== 'string' || !/^[A-Za-z0-9_-]{1,256}$/.test(about.user.permissionId) ||
        typeof about.user.emailAddress !== 'string' || about.user.emailAddress.toLowerCase() !== profile.email.toLowerCase()) throw new Error('provider-identity-mismatch');
    return { accessToken: token.access_token, refreshToken: rotated, providerAccountId: profile.sub,
      ownerPermissionId: about.user.permissionId, email: profile.email.toLowerCase() };
  };
}
