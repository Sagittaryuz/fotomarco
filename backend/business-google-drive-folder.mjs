import { checkGoogleDriveFolderAccess } from './business-google-drive-access.mjs';

/** Caller must hold a persisted per-organization provisioning lease and marker. */
export async function createGoogleDrivePrivateFolder({ accessToken, parentId, parentParentId, ownerPermissionId, name, marker, fetchImpl = fetch }) {
  const validId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,256}$/.test(value);
  if (!validId(parentId) || !validId(parentParentId) || !validId(ownerPermissionId) || typeof accessToken !== 'string' ||
      !accessToken || accessToken.length > 16384 || typeof name !== 'string' || !name.trim() || name.length > 200 ||
      /[\x00-\x1f\x7f/\\]/.test(name) || typeof marker !== 'string' ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(marker)) throw new Error('invalid-storage-configuration');
  const verify = folderId => checkGoogleDriveFolderAccess({ accessToken, folderId, expectedParentId: parentId, ownerPermissionId, fetchImpl });
  await checkGoogleDriveFolderAccess({ accessToken, folderId: parentId, expectedParentId: parentParentId, ownerPermissionId, fetchImpl });
  const headers = { authorization: `Bearer ${accessToken}` };
  const query = new URL('https://www.googleapis.com/drive/v3/files');
  query.searchParams.set('q', `'${parentId}' in parents and trashed = false and appProperties has { key='photomarkMarker' and value='${marker.toLowerCase()}' }`);
  query.searchParams.set('fields', 'nextPageToken,files(id,name,mimeType,parents,appProperties,trashed)');
  query.searchParams.set('pageSize', '100');
  let listing;
  try {
    const response = await fetchImpl(query.toString(), { headers, redirect: 'manual', signal: AbortSignal.timeout(15000) });
    if (response.status !== 200) throw new Error('upstream');
    listing = await response.json();
  } catch { throw new Error('storage-unavailable'); }
  if (!listing || !Array.isArray(listing.files) || listing.nextPageToken || listing.files.length > 1) throw new Error('ambiguous-google-folder');
  let folder = listing.files[0];
  if (!folder) {
    let response;
    try { response = await fetchImpl('https://www.googleapis.com/drive/v3/files?fields=id%2Cname%2CmimeType%2Cparents%2CappProperties%2Ctrashed', {
      method: 'POST', headers: { ...headers, 'content-type': 'application/json' }, redirect: 'manual', signal: AbortSignal.timeout(15000),
      body: JSON.stringify({ name: name.trim(), mimeType: 'application/vnd.google-apps.folder', parents: [parentId], writersCanShare: false, appProperties: { photomarkMarker: marker.toLowerCase() } })
    }); } catch { throw new Error('storage-create-unconfirmed'); }
    if (response.status !== 200) throw new Error('storage-create-unconfirmed');
    try { folder = await response.json(); } catch { throw new Error('storage-create-unconfirmed'); }
  }
  if (!folder || !validId(folder.id) || folder.name !== name.trim() || folder.mimeType !== 'application/vnd.google-apps.folder' ||
      folder.trashed !== false || !Array.isArray(folder.parents) || folder.parents.length !== 1 || folder.parents[0] !== parentId ||
      folder.appProperties?.photomarkMarker !== marker.toLowerCase()) throw new Error('unsafe-google-folder');
  await verify(folder.id);
  return { folderId: folder.id };
}
