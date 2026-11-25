/** Bind a verified Google identity to its Drive permission ID before sharing. */
export async function verifiedGoogleDriveMember(accessToken, { fetchImpl = fetch } = {}) {
  if (typeof accessToken !== 'string' || !accessToken || accessToken.length > 16384 || /[\x00-\x20\x7f]/.test(accessToken)) throw new Error('invalid-provider-credential');
  const get = async url => {
    try {
      const response = await fetchImpl(url, { redirect: 'manual', signal: AbortSignal.timeout(15000), headers: { authorization: `Bearer ${accessToken}` } });
      if (response.status !== 200) throw new Error('upstream');
      const value = await response.json();
      if (!value || typeof value !== 'object') throw new Error('invalid response');
      return value;
    } catch { throw new Error('provider-unavailable'); }
  };
  const profile = await get('https://openidconnect.googleapis.com/v1/userinfo');
  if (profile.email_verified !== true || typeof profile.email !== 'string' || profile.email.length > 254 ||
      !/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(profile.email) || typeof profile.sub !== 'string' || !profile.sub || profile.sub.length > 256) throw new Error('provider-identity-mismatch');
  const about = await get('https://www.googleapis.com/drive/v3/about?fields=user(me%2CpermissionId%2CemailAddress)');
  if (about.user?.me !== true || typeof about.user.permissionId !== 'string' || !/^[A-Za-z0-9_-]{1,256}$/.test(about.user.permissionId) ||
      typeof about.user.emailAddress !== 'string' || about.user.emailAddress.toLowerCase() !== profile.email.toLowerCase()) throw new Error('provider-identity-mismatch');
  return { providerAccountId: profile.sub, permissionId: about.user.permissionId, email: profile.email.toLowerCase() };
}
