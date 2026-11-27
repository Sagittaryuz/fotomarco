import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { BusinessService } from './business-service.mjs';

function fixture() {
  const org = { id: 'org', ownerId: 'owner' };
  const member = { organizationId: 'org', userId: 'owner', role: 'owner', active: true, email: 'owner@example.com', displayName: 'Owner' };
  let credential = { version: 1, iv: 'iv', ciphertext: 'sealed', providerAccountId: 'google', ownerPermissionId: 'permission' };
  let state, now = 1000;
  const tx = { organization: async () => org, membership: async (_, uid) => uid === 'owner' ? member : null,
    googleDriveCredential: async () => credential, googleOwnerFolderState: async () => state,
    setGoogleDriveCredential: async (_, value) => { credential = value; }, setGoogleOwnerFolderState: async (_, value) => { state = value; } };
  const service = new BusinessService({ verifyToken: async value => value, transaction: fn => fn(tx), newId: randomUUID, clock: () => now });
  const user = { uid: 'owner', emailVerified: true };
  const success = async ({ pending, storage }) => ({ imagesId: pending.imagesId, parentId: 'parent', folderId: 'folder', ownerCredential: storage });
  return { service, user, success, member, state: () => state, credential: () => credential, advance: ms => { now += ms; } };
}

test('only verified owner provisions and retries without replacing stored markers', async () => {
  const f = fixture();
  let attempts = 0, first;
  f.service.prepareGoogleOwnerFolder = async args => {
    attempts++;
    if (attempts === 1) { first = args.pending; throw new Error('network failure'); }
    assert.equal(args.pending.photomarkMarker, first.photomarkMarker);
    assert.equal(args.pending.memberMarker, first.memberMarker);
    return f.success(args);
  };
  await assert.rejects(f.service.provisionGoogleOwnerFolder({ uid: 'stranger', emailVerified: true }, 'org', 'images'), /forbidden/);
  await assert.rejects(f.service.provisionGoogleOwnerFolder({ uid: 'owner', emailVerified: false }, 'org', 'images'), /invalid-request/);
  await assert.rejects(f.service.provisionGoogleOwnerFolder(f.user, 'org', 'images'), /network failure/);
  await assert.rejects(f.service.provisionGoogleOwnerFolder(f.user, 'org', 'images'), /provisioning-in-progress/);
  await assert.rejects(f.service.provisionGoogleOwnerFolder(f.user, 'org', 'other'), /storage-account-change-requires-migration/);
  f.advance(180001);
  assert.deepEqual(await f.service.provisionGoogleOwnerFolder(f.user, 'org', 'images'), { ready: true });
  assert.equal(f.state().folderId, 'folder');
  assert.deepEqual(await f.service.provisionGoogleOwnerFolder(f.user, 'org', 'images'), { ready: true });
  assert.equal(attempts, 2);
});

test('does not commit a folder after owner access changes or provider identity mismatches', async () => {
  const f = fixture();
  f.service.prepareGoogleOwnerFolder = async args => { f.member.active = false; return f.success(args); };
  await assert.rejects(f.service.provisionGoogleOwnerFolder(f.user, 'org', 'images'), /forbidden/);
  assert.equal(f.state().status, 'provisioning');
  assert.equal(f.credential().ciphertext, 'sealed');
});

test('does not commit after the provisioning lease expires', async () => {
  const f = fixture();
  f.service.prepareGoogleOwnerFolder = async args => { f.advance(180001); return f.success(args); };
  await assert.rejects(f.service.provisionGoogleOwnerFolder(f.user, 'org', 'images'), /storage-configuration-changed/);
  assert.equal(f.state().status, 'provisioning');
  assert.equal(f.credential().ciphertext, 'sealed');
});
