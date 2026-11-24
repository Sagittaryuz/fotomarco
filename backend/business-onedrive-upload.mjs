/** Internal Graph upload helpers. Session URLs are credentials: never send them to clients or logs. */
const graphRoot = 'https://graph.microsoft.com/v1.0/me/drive';
const chunkUnit = 320 * 1024;
const validId = value => typeof value === 'string' && value.length > 0 && value.length <= 256 && !/[\x00-\x20/\\?#]/.test(value);
const validUuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);

function sessionUrl(value) {
  let url;
  try { url = new URL(value); } catch { throw new Error('invalid-upload-session'); }
  const host = url.hostname.toLowerCase();
  if (url.protocol !== 'https:' || url.username || url.password || url.port || url.hash ||
      !(host.endsWith('.up.1drv.com') || host.endsWith('.sharepoint.com'))) throw new Error('invalid-upload-session');
  return url.href;
}

export function validBusinessPhotoName(filename, captureId) {
  if (!validUuid(captureId) || typeof filename !== 'string' || new TextEncoder().encode(filename).length > 240) return false;
  const pattern = /^(\d{2}-\d{2}-\d{4}) - OneDrive - (\d{2}-\d{2}-\d{2}) - ([0-9a-f-]{36})\.(\d{1,12})(?:\.([0-9a-f-]{36})\.([A-Za-z0-9_-]{0,48}))?-(stamped\.jpg|original\.[a-z0-9]{1,12})$/i;
  const match = pattern.exec(filename);
  return !!match && validUuid(match[3]) && match[3].toLowerCase() === captureId.toLowerCase() && (!match[5] || validUuid(match[5]));
}

export async function createBusinessUploadSession({ ownerToken, folderId, captureId, filename, fetchImpl = fetch, now = () => Date.now() }) {
  if (typeof ownerToken !== 'string' || !ownerToken || !validId(folderId) || !validBusinessPhotoName(filename, captureId)) throw new Error('invalid-upload-request');
  const url = `${graphRoot}/items/${encodeURIComponent(folderId)}:/${encodeURIComponent(filename)}:/createUploadSession`;
  const response = await fetchImpl(url, { method: 'POST', redirect: 'manual',
    headers: { authorization: `Bearer ${ownerToken}`, 'content-type': 'application/json' },
    body: JSON.stringify({ item: { name: filename, '@microsoft.graph.conflictBehavior': 'fail' } }) });
  if (response.status === 409) throw new Error('upload-name-conflict');
  if (response.status !== 200) throw new Error('upload-session-unavailable');
  const data = await response.json();
  const expiresAt = Date.parse(data.expirationDateTime);
  if (!Number.isFinite(expiresAt) || expiresAt <= now()) throw new Error('invalid-upload-session');
  return { uploadUrl: sessionUrl(data.uploadUrl), expiresAt };
}

export async function sendBusinessUploadChunk({ uploadUrl, bytes, offset, total, folderId, driveId, filename, fetchImpl = fetch }) {
  const url = sessionUrl(uploadUrl);
  if (!(bytes instanceof Uint8Array) || !Number.isSafeInteger(offset) || !Number.isSafeInteger(total) || offset < 0 || total < 1 ||
      offset >= total || bytes.length < 1 || bytes.length > 10 * chunkUnit || offset % chunkUnit !== 0 || offset + bytes.length > total ||
      (offset + bytes.length < total && bytes.length % chunkUnit !== 0) || !validId(folderId) || !validId(driveId) ||
      typeof filename !== 'string' || !filename) throw new Error('invalid-upload-chunk');
  const end = offset + bytes.length - 1;
  const response = await fetchImpl(url, { method: 'PUT', redirect: 'manual', body: bytes,
    headers: { 'content-length': String(bytes.length), 'content-range': `bytes ${offset}-${end}/${total}`, 'content-type': 'application/octet-stream' } });
  if (response.status === 202) {
    if (end + 1 >= total) throw new Error('upload-result-uncertain');
    const data = await response.json();
    if (!Array.isArray(data.nextExpectedRanges) || data.nextExpectedRanges.length !== 1 || data.nextExpectedRanges[0] !== `${end + 1}-`) throw new Error('upload-result-uncertain');
    return { state: 'pending', nextOffset: end + 1 };
  }
  if (response.status !== 200 && response.status !== 201) throw new Error('upload-result-uncertain');
  if (end + 1 !== total) throw new Error('upload-result-uncertain');
  const item = await response.json();
  if (!validId(item.id) || item.name !== filename || item.size !== total || !item.file || item.folder || item.remoteItem ||
      item.parentReference?.id !== folderId || item.parentReference?.driveId !== driveId) throw new Error('upload-result-uncertain');
  // A receipt alone does not establish content integrity. The caller must verify
  // the remote bytes against the capture fingerprint before local cleanup.
  return { state: 'uploaded-unverified', itemId: item.id };
}

/** A lost response may have uploaded bytes; ask Graph before any retry. */
export async function businessUploadOffset({ uploadUrl, total, fetchImpl = fetch }) {
  const url = sessionUrl(uploadUrl);
  if (!Number.isSafeInteger(total) || total < 1) throw new Error('invalid-upload-request');
  const response = await fetchImpl(url, { redirect: 'manual' });
  if (response.status !== 200) throw new Error('upload-result-uncertain');
  const data = await response.json();
  const ranges = data.nextExpectedRanges;
  if (!Array.isArray(ranges) || ranges.length !== 1 || typeof ranges[0] !== 'string') throw new Error('upload-result-uncertain');
  const match = /^(\d+)-(\d*)$/.exec(ranges[0]);
  const offset = match ? Number(match[1]) : NaN;
  if (!Number.isSafeInteger(offset) || offset < 0 || offset >= total || offset % chunkUnit !== 0 ||
      (match[2] && (!Number.isSafeInteger(Number(match[2])) || Number(match[2]) < offset || Number(match[2]) >= total))) throw new Error('upload-result-uncertain');
  return offset;
}

/** Verify remote bytes before acknowledging delivery or removing local copies. */
export async function verifyBusinessUploadedItem({ ownerToken, driveId, folderId, itemId, filename,
  expectedSize, expectedSha256, fetchImpl = fetch, makeDigest = () => new crypto.DigestStream('SHA-256') }) {
  if (typeof ownerToken !== 'string' || !ownerToken || ![driveId, folderId, itemId].every(validId) ||
      typeof filename !== 'string' || !filename || !Number.isSafeInteger(expectedSize) || expectedSize < 1 ||
      typeof expectedSha256 !== 'string' || !/^[0-9a-f]{64}$/.test(expectedSha256)) throw new Error('invalid-upload-request');
  const itemUrl = `${graphRoot}/items/${encodeURIComponent(itemId)}`;
  const metadataResponse = await fetchImpl(itemUrl, { redirect: 'manual', headers: { authorization: `Bearer ${ownerToken}` } });
  if (metadataResponse.status !== 200) throw new Error('upload-verification-unavailable');
  const item = await metadataResponse.json();
  if (item.id !== itemId || item.name !== filename || item.size !== expectedSize || !item.file || item.folder || item.remoteItem ||
      item.parentReference?.id !== folderId || item.parentReference?.driveId !== driveId) throw new Error('upload-verification-mismatch');
  const redirect = await fetchImpl(itemUrl + '/content', { redirect: 'manual', headers: { authorization: `Bearer ${ownerToken}` } });
  if (redirect.status !== 302) throw new Error('upload-verification-unavailable');
  let download;
  try { download = new URL(redirect.headers.get('location')); } catch { throw new Error('invalid-download-url'); }
  const host = download.hostname.toLowerCase();
  if (download.protocol !== 'https:' || download.username || download.password || download.port || download.hash ||
      !(host.endsWith('.1drv.com') || host.endsWith('.sharepoint.com'))) throw new Error('invalid-download-url');
  const content = await fetchImpl(download.href, { redirect: 'manual' });
  if (content.status !== 200 || !content.body) throw new Error('upload-verification-unavailable');
  const stream = makeDigest();
  const writer = stream.getWriter();
  const reader = content.body.getReader();
  let count = 0;
  try {
    for (;;) {
      const part = await reader.read();
      if (part.done) break;
      count += part.value.byteLength;
      if (count > expectedSize) throw new Error('upload-verification-mismatch');
      await writer.write(part.value);
    }
    if (count !== expectedSize) throw new Error('upload-verification-mismatch');
    await writer.close();
    const digest = new Uint8Array(await stream.digest);
    const actual = Array.from(digest, byte => byte.toString(16).padStart(2, '0')).join('');
    if (actual !== expectedSha256) throw new Error('upload-verification-mismatch');
    return { verified: true, itemId };
  } catch (error) {
    try { await reader.cancel(); } catch { /* preserve original error */ }
    try { await writer.abort(); } catch { /* preserve original error */ }
    throw error;
  }
}
