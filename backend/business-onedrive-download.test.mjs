import { test } from 'node:test';
import assert from 'node:assert/strict';
import { openBusinessPhoto } from './business-onedrive-download.mjs';
const args = { ownerToken: 'secret', itemId: 'item', folderId: 'folder', driveId: 'drive', filename: 'photo.jpg' };
function fetcher({ invalidHost = false, wrongFolder = false } = {}) {
  return async (url, request) => {
    if (url === 'https://graph.microsoft.com/v1.0/me/drive/items/item') {
      assert.equal(request.headers.authorization, 'Bearer secret');
      return { status: 200, json: async () => ({ id: 'item', name: 'photo.jpg', file: {}, parentReference: { id: wrongFolder ? 'other' : 'folder', driveId: 'drive' } }) };
    }
    if (url.startsWith('https://graph.microsoft.com/')) return { status: 302, headers: new Headers({ location: invalidHost ? 'https://attacker.test/x' : 'https://x.files.1drv.com/photo' }) };
    assert.equal(url, 'https://x.files.1drv.com/photo'); assert.equal(request.headers, undefined);
    return { status: 200, body: new ReadableStream() };
  };
}
test('proxies a verified photo without forwarding credentials to the download host', async () => {
  assert.ok(await openBusinessPhoto({ ...args, fetchImpl: fetcher() }));
  assert.ok(await openBusinessPhoto({ ...args, thumbnail: true, fetchImpl: fetcher() }));
});
test('refuses untrusted redirect hosts and changed folder bindings', async () => {
  await assert.rejects(openBusinessPhoto({ ...args, fetchImpl: fetcher({ invalidHost: true }) }), /invalid-download-url/);
  await assert.rejects(openBusinessPhoto({ ...args, fetchImpl: fetcher({ wrongFolder: true }) }), /storage-configuration-changed/);
});
