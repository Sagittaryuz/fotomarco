import { createGoogleDrivePrivateFolder } from './business-google-drive-folder.mjs';

/**
 * Create only application-marked private folders. The caller must persist the
 * three markers and serialize provisioning before calling this function.
 * Existing, unmarked folders are deliberately never renamed or reused.
 */
export async function prepareGoogleDriveMemberHierarchy({ accessToken, rootId, ownerPermissionId, memberName, memberEmail, markers, fetchImpl = fetch }) {
  const validId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,256}$/.test(value);
  const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
  if (!validId(rootId) || !validId(ownerPermissionId) || typeof accessToken !== 'string' || !accessToken || accessToken.length > 16384 ||
      typeof memberName !== 'string' || typeof memberEmail !== 'string' || !markers ||
      !['images', 'photomark', 'member'].every(key => uuid(markers[key])) ||
      new Set(['images', 'photomark', 'member'].map(key => markers[key].toLowerCase())).size !== 3) throw new Error('invalid-storage-configuration');
  const name = memberName.trim().replace(/\s+/g, ' ');
  const email = memberEmail.trim().toLowerCase();
  if (!name || name.length > 100 || /[\x00-\x1f\x7f/\\]/.test(name) || email.length > 120 ||
      !/^[^\s@<>/\\]+@[^\s@<>/\\]+\.[^\s@<>/\\]+$/.test(email)) throw new Error('invalid-member-name');
  const folderName = `${name} (${email})`;
  if (folderName.length > 200) throw new Error('invalid-member-name');

  const common = { accessToken, ownerPermissionId, fetchImpl };
  const images = await createGoogleDrivePrivateFolder({ ...common, parentId: rootId, parentIsRoot: true, name: 'Imagens', marker: markers.images });
  const photomark = await createGoogleDrivePrivateFolder({ ...common, parentId: images.folderId, parentParentId: rootId, name: 'Photomark', marker: markers.photomark });
  const member = await createGoogleDrivePrivateFolder({ ...common, parentId: photomark.folderId, parentParentId: images.folderId,
    name: folderName, marker: markers.member });
  return { imagesId: images.folderId, parentId: photomark.folderId, folderId: member.folderId };
}
