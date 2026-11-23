import { test } from 'node:test';
import assert from 'node:assert/strict';
import { grantOneDriveMemberFolder } from './business-onedrive-grant.mjs';

const config = { ownerToken: 'private-token', expectedOwnerId: 'owner', expectedDriveId: 'drive', expectedParentId: 'parent', folderId: 'folder', memberIdentityId: 'member', memberVerifiedEmail: 'member@example.com' };
const entry = (id, roles) => ({ roles, grantedToV2: { user: { id } } });

test('grants only the verified recipient and confirms the effective access', async () => {
  let shared = false, invitations = 0;
  const fetchImpl = async (url, request) => {
    let body;
    if (url.endsWith('/invite')) {
      invitations++;
      body = JSON.parse(request.body);
      assert.deepEqual(body.recipients, [{ email: 'member@example.com' }]);
      assert.equal(body.requireSignIn, true);
      assert.equal(body.sendInvitation, false);
      shared = true;
      return { status: 200, ok: true, json: async () => ({}) };
    }
    body = url.endsWith('/permissions') ? { value: [entry('owner', ['owner']), ...(shared ? [entry('member', ['write'])] : [])] }
      : url.endsWith('/drive') ? { id: 'drive', owner: { user: { id: 'owner' } } }
        : { id: 'folder', folder: {}, parentReference: { id: 'parent', driveId: 'drive' } };
    return { status: 200, ok: true, json: async () => body };
  };
  assert.deepEqual(await grantOneDriveMemberFolder({ ...config, fetchImpl }), { driveId: 'drive', folderId: 'folder' });
  assert.deepEqual(await grantOneDriveMemberFolder({ ...config, fetchImpl }), { driveId: 'drive', folderId: 'folder' });
  assert.equal(invitations, 1);
});

test('does not grant access when an unexpected recipient already has access', async () => {
  let posted = false;
  const fetchImpl = async (url, request) => {
    if (request.method === 'POST') posted = true;
    const body = url.endsWith('/permissions') ? { value: [entry('owner', ['owner']), entry('stranger', ['read'])] }
      : url.endsWith('/drive') ? { id: 'drive', owner: { user: { id: 'owner' } } }
        : { id: 'folder', folder: {}, parentReference: { id: 'parent', driveId: 'drive' } };
    return { status: 200, ok: true, json: async () => body };
  };
  await assert.rejects(grantOneDriveMemberFolder({ ...config, fetchImpl }), /unsafe-folder-permissions/);
  assert.equal(posted, false);
});
