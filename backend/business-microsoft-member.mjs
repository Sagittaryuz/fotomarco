/** Resolve a member from the Microsoft Graph token presented by that member.
 * Never derive an account ID from client supplied identity fields. */
export async function verifiedMicrosoftMember(accessToken, { fetchImpl = fetch } = {}) {
  if (typeof accessToken !== 'string' || !accessToken || accessToken.length > 16384 || /[\x00-\x20\x7f]/.test(accessToken)) throw new Error('invalid-provider-credential');
  const response = await fetchImpl('https://graph.microsoft.com/v1.0/me?$select=id,mail,userPrincipalName', {
    method: 'GET', redirect: 'manual', headers: { authorization: `Bearer ${accessToken}` }
  });
  if (response.status !== 200) throw new Error('provider-unavailable');
  const user = await response.json();
  const email = (typeof user.mail === 'string' && user.mail ? user.mail : user.userPrincipalName)?.trim().toLowerCase();
  if (typeof user.id !== 'string' || !user.id || user.id.length > 256 || /[\x00-\x20/\\?#]/.test(user.id) ||
      typeof email !== 'string' || email.length > 120 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || /[\\/:*?"<>|\x00-\x1f]/.test(email)) {
    throw new Error('provider-identity-mismatch');
  }
  return { providerAccountId: user.id, email };
}
