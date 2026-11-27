/** Match a delegated /me response to /me/drive and a trusted expected identity. */
export function matchesDelegatedDriveOwner({ user, drive, expectedOwnerId, expectedDriveId }) {
  const validId = id => typeof id === 'string' && id.length > 0 && id.length <= 256 && !/[\x00-\x20/\\?#]/.test(id);
  if (!validId(expectedOwnerId) || !validId(expectedDriveId) || user?.id !== expectedOwnerId || drive?.id !== expectedDriveId) return false;
  // Microsoft documents owner as optional. If present, it must identify the
  // expected user; malformed, conflicting or non-user identities fail closed.
  if (drive.owner == null) return true;
  return drive.owner?.user?.id === expectedOwnerId;
}

/** Read /me with the same delegated token as the /me/drive response. */
export async function readDelegatedUser(ownerToken, fetchImpl = fetch) {
  try {
    const response = await fetchImpl('https://graph.microsoft.com/v1.0/me?$select=id', {
      redirect: 'manual', signal: AbortSignal.timeout(15000), headers: { authorization: `Bearer ${ownerToken}` }
    });
    if (response.status !== 200) throw new Error('upstream');
    const user = await response.json();
    if (!user || typeof user !== 'object') throw new Error('invalid');
    return user;
  } catch { throw new Error('storage-unavailable'); }
}
