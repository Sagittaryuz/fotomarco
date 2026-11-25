import { checkGoogleDriveFolderAccess } from './business-google-drive-access.mjs';

/** Caller must serialize permission changes and confirm that membership was revoked. */
export async function revokeGoogleDriveMember({ accessToken, folderId, parentId, ownerPermissionId, memberPermissionId, fetchImpl = fetch }) {
  const validId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,256}$/.test(value);
  if (!validId(folderId) || !validId(parentId) || !validId(ownerPermissionId) || !validId(memberPermissionId) || memberPermissionId === ownerPermissionId) throw new Error('invalid-member-identity');
  const privateFolder = { accessToken, folderId, expectedParentId: parentId, ownerPermissionId, requireNoReshare: true, fetchImpl };
  try {
    await checkGoogleDriveFolderAccess(privateFolder);
    return { revoked: true };
  } catch (error) {
    if (error?.message !== 'unsafe-google-folder') throw error;
  }
  await checkGoogleDriveFolderAccess({ ...privateFolder, memberPermissionId });
  const url = `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(folderId)}/permissions/${encodeURIComponent(memberPermissionId)}`;
  let response;
  try { response = await fetchImpl(url, { method: 'DELETE', redirect: 'manual', signal: AbortSignal.timeout(15000), headers: { authorization: `Bearer ${accessToken}` } }); }
  catch { throw new Error('revocation-unconfirmed'); }
  if (response.status !== 204) throw new Error('revocation-unconfirmed');
  await checkGoogleDriveFolderAccess(privateFolder);
  return { revoked: true };
}
