import { test } from 'node:test';
import assert from 'node:assert/strict';
import { revokeGoogleDriveMember } from './business-google-drive-revoke.mjs';
const args = { accessToken: 'private', folderId: 'folder', parentId: 'parent', ownerPermissionId: 'owner', memberPermissionId: 'member' };
test('removes only the selected member and verifies private access after deletion', async () => {
  let present = true, deletes = 0;
  const fetchImpl = async (url, options) => {
    if (options.method === 'DELETE') { deletes++; assert.ok(url.endsWith('/permissions/member')); present = false; return { status: 204 }; }
    if (url.includes('/permissions?')) return { status: 200, json: async () => ({ permissions: [
      { id: 'owner', type: 'user', role: 'owner' }, ...(present ? [{ id: 'member', type: 'user', role: 'writer' }] : [])] }) };
    return { status: 200, json: async () => ({ id: 'folder', parents: ['parent'], mimeType: 'application/vnd.google-apps.folder', trashed: false,
      writersCanShare: false, capabilities: { canListChildren: true } }) };
  };
  assert.deepEqual(await revokeGoogleDriveMember({ ...args, fetchImpl }), { revoked: true });
  assert.deepEqual(await revokeGoogleDriveMember({ ...args, fetchImpl }), { revoked: true });
  assert.equal(deletes, 1);
});
test('does not delete permissions when an unexpected person has access', async () => {
  let deletes = 0;
  const fetchImpl = async (url, options) => {
    if (options.method === 'DELETE') { deletes++; return { status: 204 }; }
    if (url.includes('/permissions?')) return { status: 200, json: async () => ({ permissions: [{ id: 'owner', type: 'user', role: 'owner' },
      { id: 'member', type: 'user', role: 'writer' }, { id: 'other', type: 'user', role: 'reader' }] }) };
    return { status: 200, json: async () => ({ id: 'folder', parents: ['parent'], mimeType: 'application/vnd.google-apps.folder', trashed: false,
      writersCanShare: false, capabilities: { canListChildren: true } }) };
  };
  await assert.rejects(revokeGoogleDriveMember({ ...args, fetchImpl }), /unsafe-google-folder/);
  assert.equal(deletes, 0);
});
test('does not report success when the member remains after deletion', async () => {
  const fetchImpl = async (url, options) => {
    if (options.method === 'DELETE') return { status: 204 };
    if (url.includes('/permissions?')) return { status: 200, json: async () => ({ permissions: [
      { id: 'owner', type: 'user', role: 'owner' }, { id: 'member', type: 'user', role: 'writer' }] }) };
    return { status: 200, json: async () => ({ id: 'folder', parents: ['parent'], mimeType: 'application/vnd.google-apps.folder',
      trashed: false, writersCanShare: false, capabilities: { canListChildren: true } }) };
  };
  await assert.rejects(revokeGoogleDriveMember({ ...args, fetchImpl }), /unsafe-google-folder/);
});
