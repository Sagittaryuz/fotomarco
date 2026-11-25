/** Fail closed unless the full Drive ACL contains only the expected principals. */
export function verifyGoogleDriveFolderAccess({ folder, permissions, ownerPermissionId, memberPermissionId }) {
  const validId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,256}$/.test(value);
  if (!validId(ownerPermissionId) || (memberPermissionId !== undefined && (!validId(memberPermissionId) || memberPermissionId === ownerPermissionId)) ||
      !folder || !validId(folder.id) || folder.mimeType !== 'application/vnd.google-apps.folder' || folder.trashed !== false ||
      folder.driveId || !folder.capabilities || folder.capabilities.canListChildren !== true ||
      !permissions || !Array.isArray(permissions.permissions) || permissions.nextPageToken || !permissions.permissions.length) {
    throw new Error('unsafe-google-folder');
  }
  let owners = 0, members = 0;
  const seen = new Set();
  for (const permission of permissions.permissions) {
    if (!permission || !validId(permission.id) || seen.has(permission.id) || permission.type !== 'user' || permission.deleted === true ||
        !['owner', 'writer', 'reader'].includes(permission.role) || permission.allowFileDiscovery === true) throw new Error('unsafe-google-folder');
    seen.add(permission.id);
    if (permission.id === ownerPermissionId && permission.role === 'owner') owners++;
    else if (permission.id === memberPermissionId && ['writer', 'reader'].includes(permission.role)) members++;
    else throw new Error('unsafe-google-folder');
  }
  if (owners !== 1 || (memberPermissionId !== undefined && members !== 1)) throw new Error('unsafe-google-folder');
  return true;
}

/** Read a specific folder and its ACL using only fixed Drive API endpoints. */
export async function checkGoogleDriveFolderAccess({ accessToken, folderId, expectedParentId, ownerPermissionId, memberPermissionId, fetchImpl = fetch }) {
  const validId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,256}$/.test(value);
  if (typeof accessToken !== 'string' || !accessToken || accessToken.length > 16384 ||
      !validId(folderId) || !validId(expectedParentId)) throw new Error('invalid-storage-configuration');
  const base = `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(folderId)}`;
  const get = async url => {
    let response;
    try { response = await fetchImpl(url, { headers: { authorization: `Bearer ${accessToken}` }, redirect: 'manual', signal: AbortSignal.timeout(15000) }); }
    catch { throw new Error('storage-unavailable'); }
    if (response.status !== 200) throw new Error('storage-unavailable');
    try { return await response.json(); } catch { throw new Error('storage-unavailable'); }
  };
  const metadata = new URL(base);
  metadata.searchParams.set('fields', 'id,mimeType,trashed,driveId,parents,capabilities(canListChildren)');
  const folder = await get(metadata.toString());
  if (!folder || folder.id !== folderId || !Array.isArray(folder.parents) || folder.parents.length !== 1 || folder.parents[0] !== expectedParentId) throw new Error('unsafe-google-folder');
  const acl = new URL(`${base}/permissions`);
  acl.searchParams.set('fields', 'nextPageToken,permissions(id,type,role,deleted,allowFileDiscovery)');
  acl.searchParams.set('pageSize', '100');
  const permissions = await get(acl.toString());
  verifyGoogleDriveFolderAccess({ folder, permissions, ownerPermissionId, memberPermissionId });
  return { folderId };
}
