import { test } from 'node:test';
import assert from 'node:assert/strict';
import { openGoogleDrivePhoto } from './business-google-drive-download.mjs';
const marker = '11111111-1111-4111-8111-111111111111', hash = 'a'.repeat(64);
const args = { accessToken: 'private', fileId: 'file', folderId: 'folder', parentId: 'parent', ownerPermissionId: 'owner', memberPermissionId: 'member', expectedBytes: 3, expectedSha256: hash, marker };
test('streams only the verified photo through a fixed Google endpoint', async () => {
  let contentCalls = 0;
  const stream = new ReadableStream({ start(controller) { controller.enqueue(new Uint8Array([1, 2, 3])); controller.close(); } });
  const fetchImpl = async (url, options) => {
    assert.equal(options.redirect, 'manual');
    if (url.includes('/permissions?')) return { status: 200, json: async () => ({ permissions: [{ id: 'owner', type: 'user', role: 'owner' }, { id: 'member', type: 'user', role: 'writer' }] }) };
    if (url.includes('/files/folder?')) return { status: 200, json: async () => ({ id: 'folder', parents: ['parent'], mimeType: 'application/vnd.google-apps.folder', trashed: false, writersCanShare: false, capabilities: { canListChildren: true } }) };
    if (url.includes('alt=media')) { contentCalls++; return { status: 200, body: stream }; }
    if (url.includes('canDownload')) return { status: 200, json: async () => ({ id: 'file', capabilities: { canDownload: true } }) };
    return { status: 200, json: async () => ({ id: 'file', mimeType: 'image/jpeg', parents: ['folder'], trashed: false, size: '3', sha256Checksum: hash, appProperties: { photomarkMarker: marker } }) };
  };
  assert.equal(await openGoogleDrivePhoto({ ...args, fetchImpl }), stream);
  assert.equal(contentCalls, 1);
});
test('never downloads when the folder access check fails', async () => {
  let contentCalls = 0;
  const fetchImpl = async url => {
    if (url.includes('alt=media')) contentCalls++;
    if (url.includes('/permissions?')) return { status: 200, json: async () => ({ permissions: [{ id: 'owner', type: 'user', role: 'owner' }, { id: 'public', type: 'anyone', role: 'reader' }] }) };
    return { status: 200, json: async () => ({ id: 'folder', parents: ['parent'], mimeType: 'application/vnd.google-apps.folder', trashed: false, writersCanShare: false, capabilities: { canListChildren: true } }) };
  };
  await assert.rejects(openGoogleDrivePhoto({ ...args, fetchImpl }), /unsafe-google-folder/);
  assert.equal(contentCalls, 0);
});
