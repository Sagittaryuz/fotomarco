import { test } from 'node:test';
import assert from 'node:assert/strict';
import { verifyOneDriveMemberFolder } from './business-onedrive-verify.mjs';

const args = { ownerToken: 'private-token', expectedOwnerId: 'owner', expectedDriveId: 'drive', expectedParentId: 'parent', folderId: 'folder!1', memberIdentityId: 'member' };
const entry = (id, roles) => ({ roles, grantedToV2: { user: { id } } });
const mock = changes => async (url, options) => {
  assert.equal(options.headers.authorization, 'Bearer private-token');
  assert.equal(options.redirect, 'manual');
  let data = url.endsWith('/permissions') ? { value: [entry('owner', ['owner']), entry('member', ['write'])] }
    : url.endsWith('/drive') ? { id: 'drive', owner: { user: { id: 'owner' } } }
      : { id: 'folder!1', folder: {}, parentReference: { driveId: 'drive', id: 'parent' } };
  data = changes?.(url, data) ?? data;
  return { ok: true, json: async () => data };
};

test('returns the verified folder only after checking account, parent, and effective access', async () => {
  assert.deepEqual(await verifyOneDriveMemberFolder({ ...args, fetchImpl: mock() }), { driveId: 'drive', folderId: 'folder!1' });
});

test('rejects a wrong owner, parent, or unexpected sharing', async () => {
  await assert.rejects(verifyOneDriveMemberFolder({ ...args, fetchImpl: mock((url, data) => url.endsWith('/drive') ? { ...data, owner: { user: { id: 'other' } } } : data) }), /wrong-owner-account/);
  await assert.rejects(verifyOneDriveMemberFolder({ ...args, fetchImpl: mock((url, data) => url.includes('/items/') && !url.endsWith('/permissions') ? { ...data, parentReference: { driveId: 'drive', id: 'other' } } : data) }), /invalid-member-folder/);
  await assert.rejects(verifyOneDriveMemberFolder({ ...args, fetchImpl: mock((url, data) => url.endsWith('/permissions') ? { value: [...data.value, entry('other', ['read'])] } : data) }), /unsafe-folder-permissions/);
});
