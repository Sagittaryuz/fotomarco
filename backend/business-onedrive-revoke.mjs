import { verifyOneDriveMemberFolder } from './business-onedrive-verify.mjs';
import { validateMemberFolderPermissions } from './business-onedrive-access.mjs';

/** Revoke only the verified member's explicit permission; retain the folder and photos. */
export async function revokeOneDriveMemberFolder(configuration) {
  const { ownerToken, expectedOwnerId, memberIdentityId, folderId, fetchImpl = fetch } = configuration;
  await verifyOneDriveMemberFolder({ ...configuration, requireMember: false });
  const base = `https://graph.microsoft.com/v1.0/me/drive/items/${encodeURIComponent(folderId)}`;
  const headers = { authorization: `Bearer ${ownerToken}` };
  const itemResponse = await fetchImpl(base, { headers, redirect: 'manual' });
  if (itemResponse.status !== 200) throw new Error('storage-unavailable');
  const item = await itemResponse.json();
  if (item.id !== folderId || typeof item.eTag !== 'string' || !item.eTag || /[\r\n]/.test(item.eTag)) throw new Error('storage-version-unavailable');
  const permissionsResponse = await fetchImpl(base + '/permissions', { headers, redirect: 'manual' });
  if (permissionsResponse.status !== 200) throw new Error('storage-unavailable');
  const page = await permissionsResponse.json();
  if (!validateMemberFolderPermissions({ permissionPage: page, ownerIdentityId: expectedOwnerId,
      memberIdentityId, isOwnerListing: true, requireMember: false })) throw new Error('unsafe-folder-permissions');
  const entries = page.value.filter(p => (p.grantedToV2 ?? p.grantedTo)?.user?.id === memberIdentityId);
  if (entries.length > 1) throw new Error('ambiguous-member-permission');
  if (entries.length === 1) {
    const permission = entries[0];
    if (permission.inheritedFrom != null || typeof permission.id !== 'string' || !permission.id ||
        permission.id.length > 256 || /[\x00-\x20/\\?#]/.test(permission.id)) throw new Error('unsafe-member-permission');
    const response = await fetchImpl(`${base}/permissions/${encodeURIComponent(permission.id)}`, {
      method: 'DELETE', redirect: 'manual', headers: { ...headers, 'if-match': item.eTag }
    });
    if (response.status !== 204) throw new Error('storage-revocation-unconfirmed');
  }
  await verifyOneDriveMemberFolder({ ...configuration, requireMember: false, memberMustBeAbsent: true });
  return { revoked: true };
}
