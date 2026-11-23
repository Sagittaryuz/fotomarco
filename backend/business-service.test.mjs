import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BusinessService } from './business-service.mjs';

function fixture() {
  const organization = { id: 'org', ownerId: 'owner' };
  const records = new Map([['owner', { organizationId: 'org', userId: 'owner', role: 'owner', active: true }]]);
  const invites = new Map();
  const tx = {
    organization: async id => id === 'org' ? organization : null,
    membership: async (_, id) => records.get(id),
    occupiedSeats: async () => [...records.values()].filter(x => x.active).length,
    createInvitation: async value => { invites.set(value.id, value); },
    invitation: async (_, id) => invites.get(id),
    addMember: async value => { records.set(value.userId, value); },
    markInvitationAccepted: async (_, id, userId) => { invites.set(id, { ...invites.get(id), state: 'accepted', userId }); },
  };
  const service = new BusinessService({ verifyToken: async token => token, transaction: fn => fn(tx), newId: () => 'invite', clock: () => 100 });
  return { service, records, invites };
}

test('a verified invited user can join only as member, and cannot reuse invitation', async () => {
  const { service, records } = fixture();
  await service.invite({ uid: 'owner' }, 'org', ' PERSON@example.com ');
  const recipient = { uid: 'member', email: 'person@example.com', emailVerified: true };
  assert.deepEqual(await service.accept(recipient, 'org', 'invite'), { organizationId: 'org' });
  assert.equal(records.get('member').role, 'member');
  await assert.rejects(service.accept(recipient, 'org', 'invite'), /invalid-invitation/);
});

test('a nonmember cannot invite; unverified or mismatched recipients cannot accept', async () => {
  const { service } = fixture();
  await assert.rejects(service.invite({ uid: 'stranger' }, 'org', 'a@example.com'), /forbidden-or-full/);
  await service.invite({ uid: 'owner' }, 'org', 'a@example.com');
  await assert.rejects(service.accept({ uid: 'x', email: 'a@example.com', emailVerified: false }, 'org', 'invite'), /invalid-invitation/);
  await assert.rejects(service.accept({ uid: 'x', email: 'b@example.com', emailVerified: true }, 'org', 'invite'), /invalid-invitation/);
  await assert.rejects(service.accept({ uid: 'x', email: 'a@example.com', emailVerified: true }, 'other', 'invite'), /invalid-invitation/);
});
