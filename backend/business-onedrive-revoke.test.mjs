import { test } from 'node:test';
import assert from 'node:assert/strict';
import { revokeOneDriveMemberFolder } from './business-onedrive-revoke.mjs';

function fake({ inherited = false, keepAfterDelete = false } = {}) {
  let shared = true, deletes = 0;
  const fetch = async (url, options) => {
    const path = new URL(url).pathname;
    if (options.method === 'DELETE') {
      deletes++;
      assert.equal(options.headers['if-match'], '"version"');
      if (!keepAfterDelete) shared = false;
      return { status: 204 };
    }
    const response = data => ({ status: 200, ok: true, json: async () => data });
    if (path.endsWith('/drive')) return response({ id: 'drive', owner: { user: { id: 'owner' } } });
    if (path.endsWith('/permissions')) return response({ value: [
      { id: 'owner-permission', roles: ['owner'], grantedToV2: { user: { id: 'owner' } } },
      ...(shared ? [{ id: 'member-permission', roles: ['write'], grantedToV2: { user: { id: 'member' } }, ...(inherited ? { inheritedFrom: { id: 'parent' } } : {}) }] : [])
    ] });
    return response({ id: 'folder', folder: {}, eTag: '"version"', parentReference: { id: 'parent', driveId: 'drive' } });
  };
  return { fetch, deletes: () => deletes };
}
const config = { ownerToken: 'token', expectedOwnerId: 'owner', expectedDriveId: 'drive',
  expectedParentId: 'parent', folderId: 'folder', memberIdentityId: 'member' };

test('removes only the explicit member permission and verifies absence', async () => {
  const graph = fake();
  assert.deepEqual(await revokeOneDriveMemberFolder({ ...config, fetchImpl: graph.fetch }), { revoked: true });
  assert.equal(graph.deletes(), 1);
  assert.deepEqual(await revokeOneDriveMemberFolder({ ...config, fetchImpl: graph.fetch }), { revoked: true });
  assert.equal(graph.deletes(), 1);
});

test('does not delete inherited permissions or claim success while access remains', async () => {
  const inherited = fake({ inherited: true });
  await assert.rejects(revokeOneDriveMemberFolder({ ...config, fetchImpl: inherited.fetch }), /unsafe-member-permission/);
  assert.equal(inherited.deletes(), 0);
  const stubborn = fake({ keepAfterDelete: true });
  await assert.rejects(revokeOneDriveMemberFolder({ ...config, fetchImpl: stubborn.fetch }), /unsafe-folder-permissions/);
});
