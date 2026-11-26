import { test } from 'node:test';
import assert from 'node:assert/strict';
import { prepareGoogleDriveMemberHierarchy } from './business-google-drive-hierarchy.mjs';

const markers = { images: '11111111-1111-4111-8111-111111111111', photomark: '22222222-2222-4222-8222-222222222222', member: '33333333-3333-4333-8333-333333333333' };
const args = { accessToken: 'synthetic', rootId: 'root-id', ownerPermissionId: 'owner', memberName: 'Marcos Pires', memberEmail: 'OWNER@example.com', markers };
const mimeType = 'application/vnd.google-apps.folder';

function drive({ publicRoot = false } = {}) {
  const files = new Map([['root-id', { id: 'root-id', mimeType, trashed: false, capabilities: { canListChildren: true } }]]);
  let creates = 0;
  const fetchImpl = async (raw, options = {}) => {
    const url = new URL(raw);
    if (options.method === 'POST') {
      const body = JSON.parse(options.body);
      const id = `folder-${++creates}`;
      const file = { ...body, id, trashed: false, capabilities: { canListChildren: true } };
      files.set(id, file);
      return { status: 200, json: async () => file };
    }
    if (url.pathname.endsWith('/permissions')) {
      const permissions = [{ id: 'owner', type: 'user', role: 'owner' }];
      if (publicRoot && url.pathname.includes('/root-id/')) permissions.push({ id: 'public', type: 'anyone', role: 'reader' });
      return { status: 200, json: async () => ({ permissions }) };
    }
    if (url.pathname.endsWith('/files')) {
      const query = url.searchParams.get('q');
      const parent = /'([^']+)' in parents/.exec(query)?.[1];
      const marker = /value='([^']+)'/.exec(query)?.[1];
      return { status: 200, json: async () => ({ files: [...files.values()].filter(f => f.parents?.[0] === parent && f.appProperties?.photomarkMarker === marker) }) };
    }
    const id = url.pathname.endsWith('/root') ? 'root-id' : url.pathname.split('/').pop();
    return { status: files.has(id) ? 200 : 404, json: async () => files.get(id) };
  };
  return { fetchImpl, files, count: () => creates };
}

test('creates the private hierarchy once and resumes it using persisted markers', async () => {
  const mock = drive();
  const result = await prepareGoogleDriveMemberHierarchy({ ...args, fetchImpl: mock.fetchImpl });
  assert.deepEqual(result, { imagesId: 'folder-1', parentId: 'folder-2', folderId: 'folder-3' });
  assert.equal(mock.files.get(result.folderId).name, 'Marcos Pires (owner@example.com)');
  assert.equal(mock.files.get(result.folderId).writersCanShare, false);
  assert.deepEqual(await prepareGoogleDriveMemberHierarchy({ ...args, fetchImpl: mock.fetchImpl }), result);
  assert.equal(mock.count(), 3);
});

test('does not create folders with unsafe permissions or invalid markers', async () => {
  const mock = drive({ publicRoot: true });
  await assert.rejects(prepareGoogleDriveMemberHierarchy({ ...args, fetchImpl: mock.fetchImpl }), /unsafe-google-folder/);
  assert.equal(mock.count(), 0);
  await assert.rejects(prepareGoogleDriveMemberHierarchy({ ...args, markers: { ...markers, member: markers.images }, fetchImpl: mock.fetchImpl }), /invalid-storage-configuration/);
  assert.equal(mock.count(), 0);
  await assert.rejects(prepareGoogleDriveMemberHierarchy({ ...args, memberName: 'a'.repeat(100), memberEmail: `${'b'.repeat(100)}@x.com`, fetchImpl: mock.fetchImpl }), /invalid-member-name/);
  assert.equal(mock.count(), 0);
});
