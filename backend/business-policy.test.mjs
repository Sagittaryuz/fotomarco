import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mayManage, mayReadPublishedProfile, mayAccessPhoto, mayInvite, mayAcceptInvitation } from './business-policy.mjs';

const org = { id: 'team', ownerId: 'owner' };
const member = (userId, role = 'member', active = true) => ({ organizationId: 'team', userId, role, active });
const person = uid => ({ uid });

test('owner sees team photos; member sees own photos by default', () => {
  const ownPhoto = { organizationId: 'team', authorId: 'member' };
  const otherPhoto = { organizationId: 'team', authorId: 'other' };
  assert.equal(mayManage(person('owner'), org, member('owner', 'owner')), true);
  assert.equal(mayAccessPhoto(person('owner'), org, member('owner', 'owner'), ownPhoto, 'view'), true);
  assert.equal(mayAccessPhoto(person('member'), org, member('member'), ownPhoto, 'view'), true);
  assert.equal(mayAccessPhoto(person('member'), org, member('member'), otherPhoto, 'view'), false);
  assert.equal(mayAccessPhoto(person('member'), org, member('member'), otherPhoto, 'view', { view: 'all' }), true);
  assert.equal(mayAccessPhoto(person('member'), org, member('member'), ownPhoto, 'delete', { delete: 'none' }), false);
});

test('revoked, foreign, forged and invalid identities are rejected', () => {
  const photo = { organizationId: 'team', authorId: 'member' };
  assert.equal(mayReadPublishedProfile(person('member'), org, member('member', 'member', false)), false);
  assert.equal(mayManage(person('attacker'), org, member('attacker', 'owner')), false);
  assert.equal(mayAccessPhoto(person('attacker'), org, member('member'), photo, 'view'), false);
  assert.equal(mayAccessPhoto(person('member'), org, member('member'), { ...photo, organizationId: 'other' }, 'view'), false);
  assert.equal(mayAccessPhoto(person('member'), org, member('member'), photo, 'publish'), false);
  assert.equal(mayAccessPhoto(person('member'), org, member('member'), photo, 'view', { view: 'unknown' }), false);
});

test('invitations are limited and require the verified recipient before expiry', () => {
  assert.equal(mayInvite(person('owner'), org, member('owner', 'owner'), 499), true);
  assert.equal(mayInvite(person('owner'), org, member('owner', 'owner'), 500), false);
  const identity = { uid: 'member', email: 'a@example.com', emailVerified: true };
  const invite = { email: 'A@example.com', state: 'pending', expiresAt: 200 };
  assert.equal(mayAcceptInvitation(identity, invite, 199), true);
  assert.equal(mayAcceptInvitation(identity, invite, 200), false);
  assert.equal(mayAcceptInvitation({ ...identity, emailVerified: false }, invite, 100), false);
  assert.equal(mayAcceptInvitation({ ...identity, email: 'b@example.com' }, invite, 100), false);
  assert.equal(mayAcceptInvitation(identity, { ...invite, state: 'revoked' }, 100), false);
});
