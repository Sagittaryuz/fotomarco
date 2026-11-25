import { checkGoogleDriveFolderAccess } from './business-google-drive-access.mjs';

/** Caller must serialize changes to this folder and recheck active membership. */
export async function grantGoogleDriveMember({ accessToken, folderId, parentId, ownerPermissionId, memberPermissionId, memberEmail, verifyRecipientIdentity, fetchImpl = fetch }) {
  const validId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,256}$/.test(value);
  if (!validId(folderId) || !validId(parentId) || !validId(ownerPermissionId) || !validId(memberPermissionId) ||
      memberPermissionId === ownerPermissionId || typeof memberEmail !== 'string' || memberEmail.length > 254 ||
      !/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(memberEmail) || typeof verifyRecipientIdentity !== 'function' ||
      await verifyRecipientIdentity(memberEmail.toLowerCase(), memberPermissionId) !== true) throw new Error('invalid-member-identity');
  const shared = { accessToken, folderId, expectedParentId: parentId, ownerPermissionId, memberPermissionId, requiredMemberRole: 'writer', fetchImpl };
  try {
    await checkGoogleDriveFolderAccess(shared);
    return { ready: true };
  } catch (error) {
    if (error?.message !== 'unsafe-google-folder') throw error;
  }
  // Only a private folder with onward sharing disabled can receive a new grant.
  await checkGoogleDriveFolderAccess({ accessToken, folderId, expectedParentId: parentId, ownerPermissionId, requireNoReshare: true, fetchImpl });
  const url = new URL(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(folderId)}/permissions`);
  url.searchParams.set('sendNotificationEmail', 'false');
  url.searchParams.set('fields', 'id,type,role');
  let response;
  try { response = await fetchImpl(url.toString(), { method: 'POST', redirect: 'manual', signal: AbortSignal.timeout(15000),
    headers: { authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'user', role: 'writer', emailAddress: memberEmail.toLowerCase() }) }); }
  catch { throw new Error('grant-unconfirmed'); }
  if (response.status !== 200) throw new Error('grant-unconfirmed');
  let permission;
  try { permission = await response.json(); } catch { throw new Error('grant-unconfirmed'); }
  if (permission?.id !== memberPermissionId || permission.type !== 'user' || permission.role !== 'writer') throw new Error('grant-unconfirmed');
  await checkGoogleDriveFolderAccess(shared);
  return { ready: true };
}
