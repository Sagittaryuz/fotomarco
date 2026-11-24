import { test } from 'node:test';
import assert from 'node:assert/strict';
import { firestoreTransactions } from './business-firestore.mjs';

const encoded = value => Object.fromEntries(Object.entries(value).map(([k, v]) => [k,
  typeof v === 'string' ? { stringValue: v } : typeof v === 'boolean' ? { booleanValue: v } : { integerValue: String(v) }]));

test('transaction reads trusted state and atomically writes member, counter and invitation', async () => {
  const calls = [];
  const mock = async (url, options) => {
    const body = JSON.parse(options.body); calls.push({ url, body });
    assert.equal(options.headers.authorization, 'Bearer server-token');
    if (url.endsWith(':beginTransaction')) return { ok: true, json: async () => ({ transaction: 'tx' }) };
    if (url.endsWith(':batchGet')) {
      const name = body.documents[0];
      const doc = name.endsWith('/state/seats') ? { count: 5 } : null;
      return { ok: true, json: async () => [doc ? { found: { name, fields: encoded(doc) } } : { missing: name }] };
    }
    return { ok: true, json: async () => ({}) };
  };
  const transact = firestoreTransactions({ projectId: 'project-123', accessToken: async () => 'server-token', fetchImpl: mock });
  await transact(async tx => {
    assert.equal(await tx.occupiedSeats('org'), 5);
    await tx.addMember({ organizationId: 'org', userId: 'user', role: 'member', active: true });
    await tx.markInvitationAccepted('org', 'invite', 'user');
  });
  const commit = calls.find(x => x.url.endsWith(':commit')).body;
  assert.equal(commit.transaction, 'tx');
  assert.equal(commit.writes.length, 4);
  assert.match(commit.writes[1].update.name, /\/users\/user\/organizations\/org$/);
  assert.equal(commit.writes[2].update.fields.count.integerValue, '6');
  assert.deepEqual(commit.writes[3].updateMask.fieldPaths, ['state', 'acceptedBy']);
});

test('invalid paths and interrupted actions roll back without committing', async () => {
  const calls = [];
  const mock = async url => { calls.push(url); return { ok: true, json: async () => ({ transaction: 'tx' }) }; };
  const transact = firestoreTransactions({ projectId: 'project-123', accessToken: async () => 'secret', fetchImpl: mock });
  await assert.rejects(transact(tx => tx.organization('../escape')), /invalid-document-id/);
  assert.equal(calls.some(x => x.endsWith(':commit')), false);
  assert.equal(calls.some(x => x.endsWith(':rollback')), true);
});
