import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BusinessService } from './business-service.mjs';

function fixture() {
  const org = { id: 'org', ownerId: 'owner' };
  const members = new Map(['owner', 'alice', 'bob'].map(uid => [uid, { organizationId: 'org', userId: uid, role: uid === 'owner' ? 'owner' : 'member', active: true }]));
  const records = ['alice', 'bob'].map((authorId, index) => ({ organizationId: 'org', state: 'verified', recordId: `capture-${index}-stamped`, variant: 'stamped',
    captureId: `capture-${index}`, authorId, filename: `${index}.jpg`, createdAt: 1, byteCount: 10 }));
  records.push({ ...records[0], recordId: 'capture-0-original', variant: 'original' });
  const tx = { organization: async () => org, membership: async (_, uid) => members.get(uid), verifiedCapturesPage: async () => records };
  return { service: new BusinessService({ verifyToken: async token => token, transaction: action => action(tx) }), members };
}
const identity = uid => ({ uid, emailVerified: true });

test('owner lists the organization photos and members only their own captures', async () => {
  const { service } = fixture();
  assert.deepEqual((await service.listCaptures(identity('owner'), 'org')).photos.map(photo => photo.authorId), ['alice', 'bob']);
  assert.deepEqual((await service.listCaptures(identity('alice'), 'org')).photos.map(photo => photo.authorId), ['alice']);
  assert.deepEqual((await service.listCaptures(identity('bob'), 'org')).photos.map(photo => photo.authorId), ['bob']);
});

test('revoked, unverified and foreign members cannot list photos', async () => {
  const { service, members } = fixture();
  members.get('alice').active = false;
  await assert.rejects(service.listCaptures(identity('alice'), 'org'), /forbidden/);
  await assert.rejects(service.listCaptures(identity('nobody'), 'org'), /forbidden/);
  await assert.rejects(service.listCaptures({ uid: 'bob', emailVerified: false }, 'org'), /invalid-request/);
  await assert.rejects(service.listCaptures(identity('bob'), 'org', '../bad'), /invalid-request/);
});
