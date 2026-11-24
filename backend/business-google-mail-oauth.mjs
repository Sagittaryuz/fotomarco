/** Requests only the Gmail send scope and verifies the Google identity. */
export function googleBusinessMailCredential({ clientId, fetchImpl = fetch }) {
  if (typeof clientId !== 'string' || !/^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$/.test(clientId)) throw new Error('invalid-google-client');
  return async refreshToken => {
    if (typeof refreshToken !== 'string' || !refreshToken || refreshToken.length > 16384 || /[\x00-\x1f\x7f]/.test(refreshToken)) throw new Error('invalid-provider-credential');
    const form = new URLSearchParams({ client_id: clientId, grant_type: 'refresh_token', refresh_token: refreshToken });
    const response = await fetchImpl('https://oauth2.googleapis.com/token', { method: 'POST', redirect: 'manual',
      headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: form.toString() });
    if (response.status !== 200) throw new Error('provider-unavailable');
    const token = await response.json();
    const rotatedRefresh = token.refresh_token ?? refreshToken;
    if (typeof token.access_token !== 'string' || !token.access_token || token.access_token.length > 16384 ||
        typeof rotatedRefresh !== 'string' || !rotatedRefresh || rotatedRefresh.length > 16384 ||
        typeof token.scope !== 'string' || !token.scope.split(/\s+/).includes('https://www.googleapis.com/auth/gmail.send')) throw new Error('provider-permission-missing');
    const profileResponse = await fetchImpl('https://openidconnect.googleapis.com/v1/userinfo', { redirect: 'manual',
      headers: { authorization: `Bearer ${token.access_token}` } });
    if (profileResponse.status !== 200) throw new Error('provider-unavailable');
    const profile = await profileResponse.json();
    if (profile.email_verified !== true || typeof profile.email !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(profile.email) ||
        typeof profile.sub !== 'string' || !profile.sub || profile.sub.length > 256) throw new Error('provider-identity-mismatch');
    return { refreshToken: rotatedRefresh, providerAccountId: profile.sub, email: profile.email.toLowerCase(), accessToken: token.access_token };
  };
}
