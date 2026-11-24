import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BusinessService } from './business-service.mjs';

function fixture(status) {
  const org = { id: 'org', ownerId: 'owner' };
  const members = new Map([
    ['owner', { organizationId: 'org', userId: 'owner', role: 'owner', active: true }],
    ['member', { organizationId: 'org', userId: 'member', role: 'member', active: true, storageStatus: status }]
  ]);
  let seats = 2;
  const tx = {
    organization: async () => org, membership: async (_, uid) => members.get(uid), occupiedSeats: async () => seats,
    beginMemberRevocation: async (_, uid, revocationId) => { Object.assign(members.get(uid), { active: false, revocationState: 'pending', revocationId }); },
    completeMemberRevocation: async (_, uid) => { members.get(uid).revocationState = 'complete'; seats--; }
  };
  const service = new BusinessService({ verifyToken: async value => value, transaction: action => action(tx), newId: () => 'revoke', clock: () => 100 });
  return { service, members, seats: () => seats };
}

test('removal keeps photos, deactivates the member and releases a seat only once', async () => {
  const { service, members, seats } = fixture('not-started');
  await assert.rejects(service.removeMember({ uid: 'member' }, 'org', 'owner'), /forbidden/);
  assert.deepEqual(await service.removeMember({ uid: 'owner' }, 'org', 'member'), { complete: true });
  assert.equal(members.get('member').active, false);
  assert.equal(seats(), 1);
  assert.deepEqual(await service.removeMember({ uid: 'owner' }, 'org', 'member'), { complete: true });
  assert.equal(seats(), 1);
});

test('provider failure keeps the removal pending and the seat reserved until access is revoked', async () => {
  const { service, members, seats } = fixture('granted');
  service.revokeMemberStorage = async () => { throw new Error('offline'); };
  assert.deepEqual(await service.removeMember({ uid: 'owner' }, 'org', 'member'), { complete: false });
  assert.equal(members.get('member').active, false);
  assert.equal(members.get('member').revocationState, 'pending');
  assert.equal(seats(), 2);
  service.revokeMemberStorage = async () => true;
  assert.deepEqual(await service.removeMember({ uid: 'owner' }, 'org', 'member'), { complete: true });
  assert.equal(seats(), 1);
});
