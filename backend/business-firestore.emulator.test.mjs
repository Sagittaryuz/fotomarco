import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { firestoreTransactions } from './business-firestore.mjs';
import { BusinessService } from './business-service.mjs';

test('Firestore emulator commits a real invitation and member transaction', { skip: !process.env.FIRESTORE_EMULATOR_HOST }, async () => {
  const origin = `http://${process.env.FIRESTORE_EMULATOR_HOST}`;
  const projectId = 'demo-photomark-business';
  const root = `${origin}/v1/projects/${projectId}/databases/(default)/documents`;
  const org = `org-${randomUUID()}`;
  const write = async (path, fields) => {
    const res = await fetch(`${root}/${path}`, { method: 'PATCH', headers: { authorization: 'Bearer owner', 'content-type': 'application/json' }, body: JSON.stringify({ fields }) });
    assert.equal(res.ok, true, `seed failed: ${res.status}`);
  };
  const s = stringValue => ({ stringValue });
  await write(`organizations/${org}`, { id: s(org), ownerId: s('owner') });
  await write(`organizations/${org}/members/owner`, { organizationId: s(org), userId: s('owner'), role: s('owner'), active: { booleanValue: true } });
  await write(`organizations/${org}/state/seats`, { count: { integerValue: '1' } });
  const transaction = firestoreTransactions({ projectId, accessToken: async () => 'owner', emulatorOrigin: origin });
  const service = new BusinessService({ transaction, verifyToken: async token => token, newId: () => 'test-invite', clock: () => 100 });
  await service.invite({ uid: 'owner' }, org, 'member@example.com');
  await service.accept({ uid: 'member', email: 'member@example.com', emailVerified: true }, org, 'test-invite');
  const res = await fetch(`${root}/organizations/${org}/state/seats`, { headers: { authorization: 'Bearer owner' } });
  assert.equal((await res.json()).fields.count.integerValue, '2');
  await assert.rejects(service.accept({ uid: 'member', email: 'member@example.com', emailVerified: true }, org, 'test-invite'), /invalid-invitation/);
});
