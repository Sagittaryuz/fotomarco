import { matchesDelegatedDriveOwner } from './business-onedrive-identity.mjs';

/** Validates the delegated account against Graph before a credential is retained. */
export function microsoftBusinessCredential({ clientId, fetchImpl = fetch }) {
  if (typeof clientId !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(clientId)) throw new Error('invalid-microsoft-client');
  return async refreshToken => {
    if (typeof refreshToken !== 'string' || refreshToken.length < 1 || refreshToken.length > 16384 || /[\x00-\x1f\x7f]/.test(refreshToken)) throw new Error('invalid-provider-credential');
    const form = new URLSearchParams({ client_id: clientId, grant_type: 'refresh_token', refresh_token: refreshToken,
      scope: 'openid profile email offline_access https://graph.microsoft.com/User.Read https://graph.microsoft.com/Files.ReadWrite' });
    let token;
    try {
      const tokenResponse = await fetchImpl('https://login.microsoftonline.com/common/oauth2/v2.0/token', {
        method: 'POST', redirect: 'manual', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: form.toString(),
        signal: AbortSignal.timeout(15000)
      });
      if (tokenResponse.status !== 200) throw new Error('upstream failure');
      token = await tokenResponse.json();
      if (!token || typeof token !== 'object') throw new Error('invalid response');
    } catch {
      throw new Error('provider-token-unavailable');
    }
    const rotatedRefresh = token.refresh_token ?? refreshToken;
    if (typeof token.access_token !== 'string' || !token.access_token || token.access_token.length > 16384 ||
        typeof rotatedRefresh !== 'string' || !rotatedRefresh || rotatedRefresh.length > 16384 ||
        typeof token.scope !== 'string' || !token.scope.split(/\s+/).some(s => /^(?:https:\/\/graph\.microsoft\.com\/)?Files\.ReadWrite$/i.test(s))) {
      throw new Error('provider-permission-missing');
    }
    const get = async url => {
      try {
        const response = await fetchImpl(url, { redirect: 'manual', headers: { authorization: `Bearer ${token.access_token}` },
          signal: AbortSignal.timeout(15000) });
        if (response.status !== 200) throw new Error('upstream failure');
        const result = await response.json();
        if (!result || typeof result !== 'object') throw new Error('invalid response');
        return result;
      } catch {
        throw new Error('provider-graph-unavailable');
      }
    };
    const user = await get('https://graph.microsoft.com/v1.0/me?$select=id,mail,userPrincipalName');
    const drive = await get('https://graph.microsoft.com/v1.0/me/drive');
    if (!matchesDelegatedDriveOwner({ user, drive, expectedOwnerId: user.id, expectedDriveId: drive.id })) throw new Error('provider-identity-mismatch');
    return { refreshToken: rotatedRefresh, providerAccountId: user.id, driveId: drive.id, accessToken: token.access_token };
  };
}
