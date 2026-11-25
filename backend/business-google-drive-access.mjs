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
