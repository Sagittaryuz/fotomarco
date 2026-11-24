/** Stream only a verified capture through the trusted backend; never return provider URLs or credentials. */
export async function openBusinessPhoto({ ownerToken, itemId, folderId, driveId, filename, thumbnail = false, fetchImpl = fetch }) {
  const validId = id => typeof id === 'string' && !!id && id.length <= 256 && !/[\x00-\x20/\\?#]/.test(id);
  if (typeof ownerToken !== 'string' || !ownerToken || ![itemId, folderId, driveId].every(validId) ||
      typeof filename !== 'string' || !filename || typeof thumbnail !== 'boolean') throw new Error('invalid-request');
  const base = `https://graph.microsoft.com/v1.0/me/drive/items/${encodeURIComponent(itemId)}`;
  const headers = { authorization: `Bearer ${ownerToken}` };
  const meta = await fetchImpl(base, { redirect: 'manual', headers });
  if (meta.status !== 200) throw new Error('storage-unavailable');
  const item = await meta.json();
  if (item.id !== itemId || item.name !== filename || !item.file || item.folder || item.remoteItem ||
      item.parentReference?.id !== folderId || item.parentReference?.driveId !== driveId) throw new Error('storage-configuration-changed');
  const redirect = await fetchImpl(base + (thumbnail ? '/thumbnails/0/medium/content' : '/content'), { redirect: 'manual', headers });
  if (redirect.status !== 302) throw new Error('storage-unavailable');
  let url;
  try { url = new URL(redirect.headers.get('location')); } catch { throw new Error('invalid-download-url'); }
  const host = url.hostname.toLowerCase();
  if (url.protocol !== 'https:' || url.username || url.password || url.port || url.hash ||
      !(host.endsWith('.1drv.com') || host.endsWith('.sharepoint.com'))) throw new Error('invalid-download-url');
  // The preauthenticated download URL is itself a secret; the owner token must not be forwarded.
  const response = await fetchImpl(url.href, { redirect: 'manual' });
  if (response.status !== 200 || !response.body) throw new Error('storage-unavailable');
  return response.body;
}
