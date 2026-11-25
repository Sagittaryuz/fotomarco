const validId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,256}$/.test(value);
const validSize = value => Number.isSafeInteger(value) && value > 0 && value <= 1024 * 1024 * 1024;
const markerPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function sessionURL(value) {
  let url;
  try { url = new URL(value); } catch { throw new Error('invalid-upload-session'); }
  if (url.protocol !== 'https:' || url.hostname !== 'www.googleapis.com' || url.port || url.username || url.password ||
      url.pathname !== '/upload/drive/v3/files' || url.hash || url.searchParams.get('uploadType') !== 'resumable' ||
      url.searchParams.getAll('uploadType').length !== 1 || url.searchParams.getAll('upload_id').length !== 1 ||
      !/^[A-Za-z0-9_-]{1,2048}$/.test(url.searchParams.get('upload_id') ?? '') ||
      [...url.searchParams.keys()].some(key => !['uploadType', 'upload_id'].includes(key))) throw new Error('invalid-upload-session');
  return url.toString();
}

/** Caller must authorize membership and encrypt the returned session URI. */
export async function startGoogleDriveUpload({ accessToken, folderId, name, mimeType, totalBytes, marker, fetchImpl = fetch }) {
  if (typeof accessToken !== 'string' || !accessToken || accessToken.length > 16384 || !validId(folderId) ||
      typeof name !== 'string' || !name.trim() || name.length > 200 || /[\x00-\x1f\x7f/\\]/.test(name) ||
      !['image/jpeg', 'image/heic', 'image/heif'].includes(mimeType) || !validSize(totalBytes) || !markerPattern.test(marker ?? '')) throw new Error('invalid-upload-request');
  let response;
  try { response = await fetchImpl('https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable', {
    method: 'POST', redirect: 'manual', signal: AbortSignal.timeout(15000),
    headers: { authorization: `Bearer ${accessToken}`, 'content-type': 'application/json', 'x-upload-content-type': mimeType, 'x-upload-content-length': String(totalBytes) },
    body: JSON.stringify({ name: name.trim(), mimeType, parents: [folderId], appProperties: { photomarkMarker: marker.toLowerCase() } })
  }); } catch { throw new Error('upload-start-unconfirmed'); }
  if (response.status !== 200) throw new Error('upload-start-unconfirmed');
  return { session: sessionURL(response.headers.get('location')) };
}

/** A provider-confirmed offset, not bytes sent, determines the next chunk. */
export async function sendGoogleDriveChunk({ session, offset, totalBytes, bytes, fetchImpl = fetch }) {
  const url = sessionURL(session);
  if (!validSize(totalBytes) || !Number.isSafeInteger(offset) || offset < 0 || offset >= totalBytes ||
      !(bytes instanceof Uint8Array) || bytes.length < 1 || offset + bytes.length > totalBytes ||
      (offset + bytes.length < totalBytes && bytes.length % (256 * 1024) !== 0)) throw new Error('invalid-upload-chunk');
  let response;
  try { response = await fetchImpl(url, { method: 'PUT', redirect: 'manual', signal: AbortSignal.timeout(300000),
    headers: { 'content-length': String(bytes.length), 'content-range': `bytes ${offset}-${offset + bytes.length - 1}/${totalBytes}` }, body: bytes }); }
  catch { throw new Error('upload-status-uncertain'); }
  if (response.status === 308) {
    const match = /^bytes=0-(\d+)$/.exec(response.headers.get('range') ?? '');
    const next = match ? Number(match[1]) + 1 : 0;
    if (!Number.isSafeInteger(next) || next < offset || next > offset + bytes.length || next >= totalBytes) throw new Error('upload-status-uncertain');
    return { complete: false, nextOffset: next };
  }
  if (response.status !== 200 && response.status !== 201) throw new Error('upload-status-uncertain');
  let file;
  try { file = await response.json(); } catch { throw new Error('upload-status-uncertain'); }
  if (!validId(file?.id) || offset + bytes.length !== totalBytes) throw new Error('upload-status-uncertain');
  return { complete: true, fileId: file.id };
}
