import { validateMemberFolderPermissions, validateOwnerFolderPermissions } from './business-onedrive-access.mjs';

/** All IDs and the delegated owner token must come from trusted server records. */
export async function verifyOneDriveMemberFolder({ ownerToken, expectedOwnerId, expectedDriveId,
  expectedParentId, folderId, memberIdentityId, requireMember = true, memberMustBeAbsent = false, fetchImpl = fetch }) {
  const validId = id => typeof id === 'string' && id.length > 0 && id.length <= 256 && !/[\x00-\x20/\\?#]/.test(id);
  if (typeof ownerToken !== 'string' || !ownerToken || ![expectedOwnerId, expectedDriveId, expectedParentId, folderId, memberIdentityId].every(validId)) throw new Error('invalid-storage-configuration');
  const base = 'https://graph.microsoft.com/v1.0/me/drive';
  async function get(suffix) {
    const response = await fetchImpl(base + suffix, { redirect: 'manual', headers: { authorization: `Bearer ${ownerToken}` } });
    if (!response.ok) throw new Error('storage-unavailable');
    return response.json();
  }
  const drive = await get('');
  if (drive.id !== expectedDriveId || drive.owner?.user?.id !== expectedOwnerId) throw new Error('wrong-owner-account');
  const path = `/items/${encodeURIComponent(folderId)}`;
  const folder = await get(path);
  if (folder.id !== folderId || !folder.folder || folder.file || folder.remoteItem ||
      folder.parentReference?.driveId !== expectedDriveId || folder.parentReference?.id !== expectedParentId) throw new Error('invalid-member-folder');
  const permissions = await get(path + '/permissions');
  const valid = memberIdentityId === expectedOwnerId ? !memberMustBeAbsent && validateOwnerFolderPermissions({
    permissionPage: permissions, ownerIdentityId: expectedOwnerId, isOwnerListing: true
  }) : validateMemberFolderPermissions({ permissionPage: permissions, ownerIdentityId: expectedOwnerId,
    memberIdentityId, isOwnerListing: true, requireMember, memberMustBeAbsent });
  if (!valid) throw new Error('unsafe-folder-permissions');
  return { driveId: expectedDriveId, folderId };
}
