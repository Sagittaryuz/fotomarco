import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ensurePrivateMemberFolder } from './business-onedrive-folders.mjs';

function fakeDrive({ sharedRoot = false } = {}) {
  const folders = new Map();
  let created = 0;
  const fetch = async (url, request) => {
    assert.equal(request.redirect, 'manual');
    assert.equal(request.headers.authorization, 'Bearer owner-token');
    const path = new URL(url).pathname.replace('/v1.0/me/drive', '');
    const response = (status, data) => ({ status, json: async () => data });
    if (!path) return response(200, { id: 'drive', owner: { user: { id: 'owner' } } });
    if (path === '/root') return response(200, { id: 'root', folder: {} });
    if (path.endsWith('/permissions')) {
      const permissions = [{ roles: ['owner'], grantedToV2: { user: { id: 'owner' } } }];
      if (sharedRoot && path === '/items/root/permissions') permissions.push({ roles: ['read'], link: { scope: 'anonymous' } });
      return response(200, { value: permissions });
    }
    const byName = /^\/items\/([^/]+):\/(.+)$/.exec(path);
    if (byName) return response(folders.has(`${byName[1]}:${decodeURIComponent(byName[2])}`) ? 200 : 404,
      folders.get(`${byName[1]}:${decodeURIComponent(byName[2])}`));
    const children = /^\/items\/([^/]+)\/children$/.exec(path);
    if (children && request.method === 'POST') {
      const body = JSON.parse(request.body);
      assert.equal(body['@microsoft.graph.conflictBehavior'], 'fail');
      const folder = { id: `folder-${++created}`, name: body.name, folder: {}, ...(body.description ? { description: body.description } : {}), parentReference: { id: children[1], driveId: 'drive' } };
      folders.set(`${children[1]}:${body.name}`, folder);
      return response(201, folder);
    }
    throw new Error('unexpected request');
  };
  return { fetch, count: () => created };
}

const config = { ownerToken: 'owner-token', expectedOwnerId: 'owner', expectedDriveId: 'drive',
  memberIdentityId: 'member', memberName: 'Maria Silva', memberEmail: 'MARIA@example.com' };

test('creates and reuses the requested private folder hierarchy without renaming', async () => {
  const drive = fakeDrive();
  const first = await ensurePrivateMemberFolder({ ...config, fetchImpl: drive.fetch });
  assert.deepEqual(first, { driveId: 'drive', parentId: 'folder-2', folderId: 'folder-3' });
  assert.deepEqual(await ensurePrivateMemberFolder({ ...config, knownMemberFolderId: first.folderId, fetchImpl: drive.fetch }), first);
  await assert.rejects(ensurePrivateMemberFolder({ ...config, fetchImpl: drive.fetch }), /folder-name-in-use/);
  assert.equal(drive.count(), 3);
});

test('refuses to create folders under a shared parent or for an unsafe name', async () => {
  const drive = fakeDrive({ sharedRoot: true });
  await assert.rejects(ensurePrivateMemberFolder({ ...config, fetchImpl: drive.fetch }), /unsafe-parent-permissions/);
  assert.equal(drive.count(), 0);
  await assert.rejects(ensurePrivateMemberFolder({ ...config, memberName: '../X', fetchImpl: drive.fetch }), /invalid-member-name/);
});

test('recovers an interrupted folder creation only with the original persisted marker', async () => {
  const drive = fakeDrive();
  const marker = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const first = await ensurePrivateMemberFolder({ ...config, creationMarker: marker, fetchImpl: drive.fetch });
  assert.deepEqual(await ensurePrivateMemberFolder({ ...config, creationMarker: marker, fetchImpl: drive.fetch }), first);
  await assert.rejects(ensurePrivateMemberFolder({ ...config, creationMarker: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', fetchImpl: drive.fetch }), /folder-name-in-use/);
  await assert.rejects(ensurePrivateMemberFolder({ ...config, creationMarker: 'untrusted-marker', fetchImpl: drive.fetch }), /invalid-storage-configuration/);
  assert.equal(drive.count(), 3);
});
