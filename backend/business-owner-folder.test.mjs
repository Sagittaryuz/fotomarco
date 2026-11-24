import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BusinessService } from './business-service.mjs';

const marker = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const owner = { uid: 'owner', email: 'owner@example.com', emailVerified: true };
function fixture() {
  const org = { id: 'org', ownerId: 'owner' };
  const member = { organizationId: 'org', userId: 'owner', role: 'owner', active: true, storageStatus: 'not-started', email: owner.email };
  const storage = { version: 1, iv: 'iv', ciphertext: 'cipher', providerAccountId: 'graph-owner', driveId: 'drive' };
  const tx = { organization: async () => org, membership: async (_, uid) => uid === 'owner' ? member : null,
    oneDriveCredential: async () => storage, setOneDriveCredential: async () => {},
    setOwnerFolderProvisioning: async (_, __, value, name, email) => Object.assign(member, { storageStatus: 'provisioning', oneDriveCreationMarker: value, oneDriveProvisionName: name, oneDriveProvisionEmail: email }),
    setOwnerFolderReady: async (_, __, value) => Object.assign(member, { storageStatus: 'granted', oneDriveFolderId: value.folderId,
      oneDriveParentId: value.parentId, oneDriveMemberIdentityId: value.memberIdentityId }) };
  const service = new BusinessService({ verifyToken: async token => token, transaction: action => action(tx), newId: () => marker, clock: () => 1 });
  service.prepareOwnerFolder = async () => ({ folderId: 'folder', parentId: 'parent', memberIdentityId: 'graph-owner', driveId: 'drive', ownerCredential: storage });
  return { service, org, member, storage };
}

test('owner folder provisioning is private, persistent and idempotent', async () => {
  const { service, member } = fixture();
  let calls = 0;
  const prepare = service.prepareOwnerFolder;
  service.prepareOwnerFolder = async context => { calls++; assert.equal(context.marker, marker); return prepare(context); };
  assert.deepEqual(await service.provisionOwnerFolder(owner, 'org'), { ready: true });
  assert.equal(member.oneDriveCreationMarker, marker);
  assert.equal(member.oneDriveFolderId, 'folder');
  assert.deepEqual(await service.provisionOwnerFolder(owner, 'org'), { ready: true });
  assert.equal(calls, 1);
});

test('untrusted members cannot create or claim the owner folder', async () => {
  const { service, member } = fixture();
  await assert.rejects(service.provisionOwnerFolder({ ...owner, uid: 'other' }, 'org'), /forbidden/);
  await assert.rejects(service.provisionOwnerFolder({ ...owner, emailVerified: false }, 'org'), /invalid-request/);
  assert.equal(member.storageStatus, 'not-started');
});

test('failed creation retains marker for retry and rechecks membership before granting', async () => {
  const { service, member } = fixture();
  service.prepareOwnerFolder = async () => { throw new Error('network'); };
  await assert.rejects(service.provisionOwnerFolder(owner, 'org'), /network/);
  assert.equal(member.storageStatus, 'provisioning');
  assert.equal(member.oneDriveCreationMarker, marker);
  member.displayName = 'Novo nome';
  service.prepareOwnerFolder = async ({ storage, marker: saved, name }) => {
    assert.equal(saved, marker);
    assert.equal(name, 'owner');
    member.active = false;
    return { folderId: 'folder', parentId: 'parent', memberIdentityId: 'graph-owner', driveId: 'drive', ownerCredential: storage };
  };
  await assert.rejects(service.provisionOwnerFolder(owner, 'org'), /forbidden/);
  assert.equal(member.storageStatus, 'provisioning');
});
