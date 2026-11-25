import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createGoogleDrivePrivateFolder } from './business-google-drive-folder.mjs';

const folderMime = 'application/vnd.google-apps.folder';
const marker = '11111111-1111-4111-8111-111111111111';
const args = { accessToken: 'private', parentId: 'parent', parentParentId: 'root', ownerPermissionId: 'owner', name: 'Photomark', marker };

test('creates a marked private folder only after verifying its parent and ACL', async () => {
  let created = 0;
  const fetchImpl = async (url, options) => {
    if (url.includes('/permissions?')) return { status: 200, json: async () => ({ permissions: [{ id: 'owner', type: 'user', role: 'owner' }] }) };
    if (url.includes('/files/parent?')) return { status: 200, json: async () => ({ id: 'parent', parents: ['root'], mimeType: folderMime, trashed: false, capabilities: { canListChildren: true } }) };
    if (url.includes('/files/child?')) return { status: 200, json: async () => ({ id: 'child', parents: ['parent'], mimeType: folderMime, trashed: false, capabilities: { canListChildren: true } }) };
    if (options.method === 'POST') { created++; return { status: 200, json: async () => ({ id: 'child', name: 'Photomark', mimeType: folderMime, parents: ['parent'], trashed: false, appProperties: { photomarkMarker: marker } }) }; }
    return { status: 200, json: async () => ({ files: [] }) };
  };
  assert.deepEqual(await createGoogleDrivePrivateFolder({ ...args, fetchImpl }), { folderId: 'child' });
  assert.equal(created, 1);
});

test('never creates under a publicly shared parent', async () => {
  let created = false;
  const fetchImpl = async (url, options) => {
    if (options.method === 'POST') { created = true; throw new Error('unexpected'); }
    if (url.includes('/permissions?')) return { status: 200, json: async () => ({ permissions: [{ id: 'owner', type: 'user', role: 'owner' }, { id: 'public', type: 'anyone', role: 'reader' }] }) };
    return { status: 200, json: async () => ({ id: 'parent', parents: ['root'], mimeType: folderMime, trashed: false, capabilities: { canListChildren: true } }) };
  };
  await assert.rejects(createGoogleDrivePrivateFolder({ ...args, fetchImpl }), /unsafe-google-folder/);
  assert.equal(created, false);
});

test('checks the actual root before creating its child', async () => {
  let created = 0;
  const fetchImpl = async (url, options) => {
    if (options.method === 'POST') { created++; return { status: 200, json: async () => ({ id: 'child', name: 'Photomark', mimeType: folderMime, parents: ['root-id'], trashed: false, appProperties: { photomarkMarker: marker } }) }; }
    if (url.includes('/permissions?')) return { status: 200, json: async () => ({ permissions: [{ id: 'owner', type: 'user', role: 'owner' }] }) };
    if (url.includes('/files/root?')) return { status: 200, json: async () => ({ id: 'root-id', mimeType: folderMime, trashed: false, capabilities: { canListChildren: true } }) };
    if (url.includes('/files/child?')) return { status: 200, json: async () => ({ id: 'child', parents: ['root-id'], mimeType: folderMime, trashed: false, capabilities: { canListChildren: true } }) };
    return { status: 200, json: async () => ({ files: [] }) };
  };
  const { parentParentId, ...rest } = args;
  assert.deepEqual(await createGoogleDrivePrivateFolder({ ...rest, parentId: 'root-id', parentIsRoot: true, fetchImpl }), { folderId: 'child' });
  await assert.rejects(createGoogleDrivePrivateFolder({ ...rest, parentId: 'wrong-root', parentIsRoot: true, fetchImpl }), /unsafe-google-folder/);
  assert.equal(created, 1);
});

test('recovers a prior marked folder without creating another and rejects ambiguous results', async () => {
  let created = 0, duplicates = false;
  const existing = { id: 'child', name: 'Photomark', mimeType: folderMime, parents: ['parent'], trashed: false, appProperties: { photomarkMarker: marker } };
  const fetchImpl = async (url, options) => {
    if (options.method === 'POST') { created++; throw new Error('unexpected'); }
    if (url.includes('/permissions?')) return { status: 200, json: async () => ({ permissions: [{ id: 'owner', type: 'user', role: 'owner' }] }) };
    if (url.includes('/files/parent?')) return { status: 200, json: async () => ({ id: 'parent', parents: ['root'], mimeType: folderMime, trashed: false, capabilities: { canListChildren: true } }) };
    if (url.includes('/files/child?')) return { status: 200, json: async () => ({ id: 'child', parents: ['parent'], mimeType: folderMime, trashed: false, capabilities: { canListChildren: true } }) };
    return { status: 200, json: async () => ({ files: duplicates ? [existing, existing] : [existing] }) };
  };
  assert.deepEqual(await createGoogleDrivePrivateFolder({ ...args, fetchImpl }), { folderId: 'child' });
  duplicates = true;
  await assert.rejects(createGoogleDrivePrivateFolder({ ...args, fetchImpl }), /ambiguous-google-folder/);
  assert.equal(created, 0);
});
