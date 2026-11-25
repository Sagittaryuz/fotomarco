import { verifyGoogleDriveUpload } from './business-google-drive-verify.mjs';

/** Caller must authorize the requester before and after preparing this stream. */
export async function openGoogleDrivePhoto({ accessToken, fileId, folderId, parentId, ownerPermissionId, memberPermissionId, expectedBytes, expectedSha256, marker, fetchImpl = fetch }) {
  await verifyGoogleDriveUpload({ accessToken, fileId, folderId, parentId, ownerPermissionId, memberPermissionId, expectedBytes, expectedSha256, marker, fetchImpl });
  const base = `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(fileId)}`;
  const headers = { authorization: `Bearer ${accessToken}` };
  const metadataURL = new URL(base);
  metadataURL.searchParams.set('fields', 'id,capabilities(canDownload)');
  let metadata;
  try {
    const response = await fetchImpl(metadataURL.toString(), { headers, redirect: 'manual', signal: AbortSignal.timeout(15000) });
    if (response.status !== 200) throw new Error('upstream');
    metadata = await response.json();
  } catch { throw new Error('storage-unavailable'); }
  if (metadata?.id !== fileId || metadata.capabilities?.canDownload !== true) throw new Error('storage-unavailable');
  const contentURL = new URL(base);
  contentURL.searchParams.set('alt', 'media');
  let response;
  try { response = await fetchImpl(contentURL.toString(), { headers, redirect: 'manual', signal: AbortSignal.timeout(30000) }); }
  catch { throw new Error('storage-unavailable'); }
  if (response.status !== 200 || !response.body) throw new Error('storage-unavailable');
  return response.body;
}
