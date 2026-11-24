import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BusinessService } from './business-service.mjs';
const captureId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
function fixture() {
  const org = { id: 'org', ownerId: 'owner' };
  const member = { organizationId: 'org', userId: 'alice', role: 'member', active: true };
  const photo = { organizationId: 'org', authorId: 'alice', state: 'verified', variant: 'stamped', recordId: `${captureId}-stamped`,
    captureId, remoteItemId: 'item', folderId: 'folder', driveId: 'drive', ownerProviderId: 'owner-id', sha256: 'hash' };
  const tx = { organization: async () => org, membership: async () => member, capture: async () => photo,
    oneDriveCredential: async () => ({ driveId: 'drive', providerAccountId: 'owner-id' }) };
  const service = new BusinessService({ verifyToken: async token => token, transaction: action => action(tx),
    openCapture: async () => new ReadableStream({ start(c) { c.close(); } }) });
  return { service, member, photo };
}
const user = { uid: 'alice', emailVerified: true };

test('only authorized members receive verified capture streams', async () => {
  const { service, photo } = fixture();
  assert.ok(await service.readCapture(user, 'org', captureId, true) instanceof ReadableStream);
  photo.authorId = 'bob';
  await assert.rejects(service.readCapture(user, 'org', captureId, true), /forbidden/);
});

test('revocation while loading a photo prevents the stream from being returned', async () => {
  const { service, member } = fixture();
  let cancelled = false;
  service.openCapture = async () => { member.active = false; return new ReadableStream({ cancel() { cancelled = true; } }); };
  await assert.rejects(service.readCapture(user, 'org', captureId, false), /forbidden/);
  assert.equal(cancelled, true);
});
