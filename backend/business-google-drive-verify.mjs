import { checkGoogleDriveFolderAccess } from './business-google-drive-access.mjs';

/** Confirm a binary belongs to the expected private member folder and matches its bytes. */
export async function verifyGoogleDriveUpload({ accessToken, fileId, folderId, parentId, ownerPermissionId, memberPermissionId, expectedBytes, expectedSha256, marker, fetchImpl = fetch }) {
  const validId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,256}$/.test(value);
  if (!validId(fileId) || !Number.isSafeInteger(expectedBytes) || expectedBytes <= 0 ||
      typeof expectedSha256 !== 'string' || !/^[0-9a-f]{64}$/i.test(expectedSha256) ||
      typeof marker !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(marker)) throw new Error('invalid-upload-verification');
  await checkGoogleDriveFolderAccess({ accessToken, folderId, expectedParentId: parentId, ownerPermissionId, memberPermissionId, requiredMemberRole: 'writer', fetchImpl });
  const url = new URL(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(fileId)}`);
  url.searchParams.set('fields', 'id,mimeType,parents,trashed,size,sha256Checksum,appProperties');
  let file;
  try {
    const response = await fetchImpl(url.toString(), { redirect: 'manual', signal: AbortSignal.timeout(15000), headers: { authorization: `Bearer ${accessToken}` } });
    if (response.status !== 200) throw new Error('upstream');
    file = await response.json();
  } catch { throw new Error('upload-verification-unavailable'); }
  if (!file || file.id !== fileId || file.trashed !== false || !['image/jpeg', 'image/heic', 'image/heif'].includes(file.mimeType) ||
      !Array.isArray(file.parents) || file.parents.length !== 1 || file.parents[0] !== folderId || file.size !== String(expectedBytes) ||
      typeof file.sha256Checksum !== 'string' || file.sha256Checksum.toLowerCase() !== expectedSha256.toLowerCase() ||
      file.appProperties?.photomarkMarker !== marker.toLowerCase()) throw new Error('upload-integrity-mismatch');
  return { verified: true, fileId };
}
