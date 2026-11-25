/** Verify delegated Microsoft mail authority and mailbox identity before storing it. */
export function microsoftBusinessMailCredential({ clientId, fetchImpl = fetch }) {
  if (typeof clientId !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(clientId)) throw new Error('invalid-microsoft-client');
  return async refreshToken => {
    if (typeof refreshToken !== 'string' || !refreshToken || refreshToken.length > 16384 || /[\x00-\x1f\x7f]/.test(refreshToken)) throw new Error('invalid-provider-credential');
    const form = new URLSearchParams({ client_id: clientId, grant_type: 'refresh_token', refresh_token: refreshToken,
      scope: 'openid profile email offline_access https://graph.microsoft.com/User.Read https://graph.microsoft.com/Mail.Send' });
    let token;
    try {
      const response = await fetchImpl('https://login.microsoftonline.com/common/oauth2/v2.0/token', {
        method: 'POST', redirect: 'manual', headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: form.toString(), signal: AbortSignal.timeout(15000)
      });
      if (response.status !== 200) throw new Error('upstream failure');
      token = await response.json();
    } catch { throw new Error('mail-unavailable'); }
    const rotated = token?.refresh_token ?? refreshToken;
    if (typeof token?.access_token !== 'string' || !token.access_token || token.access_token.length > 16384 ||
        typeof rotated !== 'string' || !rotated || rotated.length > 16384 || typeof token.scope !== 'string' ||
        !token.scope.split(/\s+/).some(scope => /^(?:https:\/\/graph\.microsoft\.com\/)?Mail\.Send$/i.test(scope))) throw new Error('mail-permission-missing');
    let user;
    try {
      const response = await fetchImpl('https://graph.microsoft.com/v1.0/me?$select=id,mail', {
        headers: { authorization: `Bearer ${token.access_token}` }, redirect: 'manual', signal: AbortSignal.timeout(15000)
      });
      if (response.status !== 200) throw new Error('upstream failure');
      user = await response.json();
    } catch { throw new Error('mail-unavailable'); }
    if (typeof user?.id !== 'string' || !user.id || user.id.length > 256 || typeof user.mail !== 'string' ||
        user.mail.length > 254 || !/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(user.mail)) throw new Error('mailbox-unconfirmed');
    return { accessToken: token.access_token, refreshToken: rotated, providerAccountId: user.id, email: user.mail.toLowerCase() };
  };
}
