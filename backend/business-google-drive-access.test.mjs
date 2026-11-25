import { test } from 'node:test';
import assert from 'node:assert/strict';
import { checkGoogleDriveFolderAccess, checkGoogleDriveRootAccess, verifyGoogleDriveFolderAccess } from './business-google-drive-access.mjs';

const folder = { id: 'folder-id', mimeType: 'application/vnd.google-apps.folder', trashed: false, writersCanShare: false, capabilities: { canListChildren: true } };
const owner = { id: 'owner-id', type: 'user', role: 'owner' };
const member = { id: 'member-id', type: 'user', role: 'writer' };
test('permits only the owner and the selected member', () => {
  assert.equal(verifyGoogleDriveFolderAccess({ folder, permissions: { permissions: [owner] }, ownerPermissionId: owner.id }), true);
  assert.equal(verifyGoogleDriveFolderAccess({ folder, permissions: { permissions: [owner, member] }, ownerPermissionId: owner.id, memberPermissionId: member.id }), true);
});

test('resolves the true root ID and refuses a root accessible to others', async () => {
  let publicAccess = false;
  const fetchImpl = async url => ({ status: 200, json: async () => url.includes('/permissions?')
    ? { permissions: [owner, ...(publicAccess ? [{ id: 'public', type: 'anyone', role: 'reader' }] : [])] }
    : { ...folder, id: 'actual-root' } });
  assert.deepEqual(await checkGoogleDriveRootAccess({ accessToken: 'private', ownerPermissionId: owner.id, fetchImpl }), { folderId: 'actual-root' });
  publicAccess = true;
  await assert.rejects(checkGoogleDriveRootAccess({ accessToken: 'private', ownerPermissionId: owner.id, fetchImpl }), /unsafe-google-folder/);
});

test('reads the fixed folder and complete ACL, and rejects a different parent', async () => {
  const calls = [];
  let parent = 'parent-id';
  const fetchImpl = async (url, options) => {
    calls.push({ url, options });
    return { status: 200, json: async () => url.includes('/permissions?')
      ? { permissions: [owner, member] } : { ...folder, parents: [parent] } };
  };
  const args = { accessToken: 'private-token', folderId: folder.id, expectedParentId: parent,
    ownerPermissionId: owner.id, memberPermissionId: member.id, fetchImpl };
  assert.deepEqual(await checkGoogleDriveFolderAccess(args), { folderId: folder.id });
  assert.equal(calls.length, 2);
  assert.ok(calls.every(call => call.url.startsWith('https://www.googleapis.com/drive/v3/files/folder-id')));
  assert.ok(calls.every(call => !call.url.includes(args.accessToken) && call.options.redirect === 'manual'));
  parent = 'different-parent'; calls.length = 0;
  await assert.rejects(checkGoogleDriveFolderAccess(args), /unsafe-google-folder/);
  assert.equal(calls.length, 1);
});
test('rejects incomplete, public, foreign and ambiguous folder access', () => {
  const base = { folder, permissions: { permissions: [owner, member] }, ownerPermissionId: owner.id, memberPermissionId: member.id };
  for (const input of [
    { ...base, permissions: { permissions: [owner, member], nextPageToken: 'more' } },
    { ...base, permissions: { permissions: [owner, member, { id: 'other', type: 'user', role: 'reader' }] } },
    { ...base, permissions: { permissions: [owner, member, { id: 'public', type: 'anyone', role: 'reader' }] } },
    { ...base, permissions: { permissions: [owner, owner, member] } },
    { ...base, folder: { ...folder, driveId: 'shared-drive' } },
    { ...base, folder: { ...folder, writersCanShare: true } },
    { ...base, folder: { ...folder, capabilities: { canListChildren: false } } },
    { ...base, permissions: { permissions: [owner] } },
  ]) assert.throws(() => verifyGoogleDriveFolderAccess(input), /unsafe-google-folder/);
});
