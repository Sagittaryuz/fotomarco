import { test } from 'node:test';
import assert from 'node:assert/strict';
import { grantGoogleDriveMember } from './business-google-drive-grant.mjs';

const args = { accessToken: 'private', folderId: 'folder', parentId: 'parent', ownerPermissionId: 'owner',
  memberPermissionId: 'member', memberEmail: 'member@example.com', verifyRecipientIdentity: async (email, id) => email === 'member@example.com' && id === 'member' };
test('shares only with verified member and confirms the final ACL without sending email', async () => {
  let granted = false, posts = 0;
  const fetchImpl = async (url, options) => {
    if (options.method === 'POST') {
      posts++; assert.match(url, /sendNotificationEmail=false/);
      assert.equal(JSON.parse(options.body).emailAddress, args.memberEmail);
      granted = true;
      return { status: 200, json: async () => ({ id: 'member', type: 'user', role: 'writer' }) };
    }
    if (url.includes('/permissions?')) return { status: 200, json: async () => ({ permissions: [
      { id: 'owner', type: 'user', role: 'owner' }, ...(granted ? [{ id: 'member', type: 'user', role: 'writer' }] : [])] }) };
    return { status: 200, json: async () => ({ id: 'folder', parents: ['parent'], mimeType: 'application/vnd.google-apps.folder',
      trashed: false, writersCanShare: false, capabilities: { canListChildren: true } }) };
  };
  assert.deepEqual(await grantGoogleDriveMember({ ...args, fetchImpl }), { ready: true });
  assert.deepEqual(await grantGoogleDriveMember({ ...args, fetchImpl }), { ready: true });
  assert.equal(posts, 1);
});
test('refuses an unverified member before contacting Drive', async () => {
  let called = false;
  await assert.rejects(grantGoogleDriveMember({ ...args, verifyRecipientIdentity: async () => false, fetchImpl: async () => { called = true; } }), /invalid-member-identity/);
  assert.equal(called, false);
});
