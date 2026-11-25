import { test } from 'node:test';
import assert from 'node:assert/strict';
import { findVerifiedGoogleDriveUpload, verifyGoogleDriveUpload } from './business-google-drive-verify.mjs';
const marker = '11111111-1111-4111-8111-111111111111';
const hash = 'a'.repeat(64);
const args = { accessToken: 'private', fileId: 'file', folderId: 'folder', parentId: 'parent', ownerPermissionId: 'owner',
  memberPermissionId: 'member', expectedBytes: 123, expectedSha256: hash, marker };
function provider(overrides = {}) {
  return async url => ({ status: 200, json: async () => url.includes('/permissions?')
    ? { permissions: [{ id: 'owner', type: 'user', role: 'owner' }, { id: 'member', type: 'user', role: 'writer' }] }
    : url.includes('/files/folder?') ? { id: 'folder', parents: ['parent'], mimeType: 'application/vnd.google-apps.folder', trashed: false, writersCanShare: false, capabilities: { canListChildren: true } }
      : { id: 'file', mimeType: 'image/jpeg', parents: ['folder'], trashed: false, size: '123', sha256Checksum: hash, appProperties: { photomarkMarker: marker }, ...overrides } });
}
test('verifies file identity, parent, size and checksum in a private member folder', async () => {
  assert.deepEqual(await verifyGoogleDriveUpload({ ...args, fetchImpl: provider() }), { verified: true, fileId: 'file' });
  for (const override of [{ sha256Checksum: 'b'.repeat(64) }, { parents: ['other'] }, { size: '124' }, { appProperties: {} }]) {
    await assert.rejects(verifyGoogleDriveUpload({ ...args, fetchImpl: provider(override) }), /upload-integrity-mismatch/);
  }
});

test('a missing or ambiguous marked file is never assumed safe to retry or verified', async () => {
  let files = [];
  const base = provider();
  const fetchImpl = async (url, options) => url.startsWith('https://www.googleapis.com/drive/v3/files?')
    ? { status: 200, json: async () => ({ files }) } : base(url, options);
  assert.deepEqual(await findVerifiedGoogleDriveUpload({ ...args, fetchImpl }), { state: 'unconfirmed' });
  files = [{ id: 'file' }];
  assert.deepEqual(await findVerifiedGoogleDriveUpload({ ...args, fetchImpl }), { state: 'verified', fileId: 'file' });
  files = [{ id: 'file' }, { id: 'other' }];
  await assert.rejects(findVerifiedGoogleDriveUpload({ ...args, fetchImpl }), /upload-verification-ambiguous/);
});
