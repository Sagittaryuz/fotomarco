import { test } from 'node:test';
import assert from 'node:assert/strict';
import { verifyGoogleDriveFolderAccess } from './business-google-drive-access.mjs';

const folder = { id: 'folder-id', mimeType: 'application/vnd.google-apps.folder', trashed: false, capabilities: { canListChildren: true } };
const owner = { id: 'owner-id', type: 'user', role: 'owner' };
const member = { id: 'member-id', type: 'user', role: 'writer' };
test('permits only the owner and the selected member', () => {
  assert.equal(verifyGoogleDriveFolderAccess({ folder, permissions: { permissions: [owner] }, ownerPermissionId: owner.id }), true);
  assert.equal(verifyGoogleDriveFolderAccess({ folder, permissions: { permissions: [owner, member] }, ownerPermissionId: owner.id, memberPermissionId: member.id }), true);
});
test('rejects incomplete, public, foreign and ambiguous folder access', () => {
  const base = { folder, permissions: { permissions: [owner, member] }, ownerPermissionId: owner.id, memberPermissionId: member.id };
  for (const input of [
    { ...base, permissions: { permissions: [owner, member], nextPageToken: 'more' } },
    { ...base, permissions: { permissions: [owner, member, { id: 'other', type: 'user', role: 'reader' }] } },
    { ...base, permissions: { permissions: [owner, member, { id: 'public', type: 'anyone', role: 'reader' }] } },
    { ...base, permissions: { permissions: [owner, owner, member] } },
    { ...base, folder: { ...folder, driveId: 'shared-drive' } },
    { ...base, folder: { ...folder, capabilities: { canListChildren: false } } },
    { ...base, permissions: { permissions: [owner] } },
  ]) assert.throws(() => verifyGoogleDriveFolderAccess(input), /unsafe-google-folder/);
});
