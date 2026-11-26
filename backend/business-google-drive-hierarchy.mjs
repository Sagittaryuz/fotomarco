import { createGoogleDrivePrivateFolder } from './business-google-drive-folder.mjs';
import { checkGoogleDriveFolderAccess, checkGoogleDriveRootAccess } from './business-google-drive-access.mjs';

/**
 * Use the owner's explicitly selected Images folder; never create another one
 * based on an incomplete drive.file listing. The caller must persist both
 * application markers and serialize provisioning before calling this function.
 */
export async function prepareGoogleDriveMemberHierarchy({ accessToken, rootId, imagesId, ownerPermissionId, memberName, memberEmail, markers, fetchImpl = fetch }) {
  const validId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,256}$/.test(value);
  const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
  if (!validId(rootId) || !validId(imagesId) || rootId === imagesId || !validId(ownerPermissionId) || typeof accessToken !== 'string' || !accessToken || accessToken.length > 16384 ||
      typeof memberName !== 'string' || typeof memberEmail !== 'string' || !markers ||
      !['photomark', 'member'].every(key => uuid(markers[key])) ||
      markers.photomark.toLowerCase() === markers.member.toLowerCase()) throw new Error('invalid-storage-configuration');
  const name = memberName.trim().replace(/\s+/g, ' ');
  const email = memberEmail.trim().toLowerCase();
  if (!name || name.length > 100 || /[\x00-\x1f\x7f/\\]/.test(name) || email.length > 120 ||
      !/^[^\s@<>/\\]+@[^\s@<>/\\]+\.[^\s@<>/\\]+$/.test(email)) throw new Error('invalid-member-name');
  const folderName = `${name} (${email})`;
  if (folderName.length > 200) throw new Error('invalid-member-name');

  const common = { accessToken, ownerPermissionId, fetchImpl };
  const root = await checkGoogleDriveRootAccess(common);
  if (root.folderId !== rootId) throw new Error('unsafe-google-folder');
  await checkGoogleDriveFolderAccess({ ...common, folderId: imagesId, expectedParentId: rootId });
  const photomark = await createGoogleDrivePrivateFolder({ ...common, parentId: imagesId, parentParentId: rootId, name: 'Photomark', marker: markers.photomark });
  const member = await createGoogleDrivePrivateFolder({ ...common, parentId: photomark.folderId, parentParentId: imagesId,
    name: folderName, marker: markers.member });
  return { imagesId, parentId: photomark.folderId, folderId: member.folderId };
}
