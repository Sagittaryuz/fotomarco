import { test } from 'node:test';
import assert from 'node:assert/strict';
import { matchesDelegatedDriveOwner, readDelegatedUser } from './business-onedrive-identity.mjs';

const base = { user: { id: 'owner' }, drive: { id: 'drive' }, expectedOwnerId: 'owner', expectedDriveId: 'drive' };

test('accepts a missing optional drive owner only with matching delegated user and drive', () => {
  assert.equal(matchesDelegatedDriveOwner(base), true);
  assert.equal(matchesDelegatedDriveOwner({ ...base, user: { id: 'other' } }), false);
  assert.equal(matchesDelegatedDriveOwner({ ...base, drive: { id: 'other' } }), false);
  assert.equal(matchesDelegatedDriveOwner({ ...base, drive: { id: 'drive', owner: { user: { id: 'other' } } } }), false);
  assert.equal(matchesDelegatedDriveOwner({ ...base, drive: { id: 'drive', owner: { application: { id: 'owner' } } } }), false);
  assert.equal(matchesDelegatedDriveOwner({ ...base, drive: { id: 'drive', owner: { user: { id: 'owner' } } } }), true);
});

test('reads the delegated identity without following redirects or exposing provider errors', async () => {
  let seen;
  const user = await readDelegatedUser('private-token', async (url, options) => {
    seen = { url, options }; return { status: 200, json: async () => ({ id: 'owner' }) };
  });
  assert.equal(user.id, 'owner');
  assert.equal(seen.url, 'https://graph.microsoft.com/v1.0/me?$select=id');
  assert.equal(seen.options.headers.authorization, 'Bearer private-token');
  assert.equal(seen.options.redirect, 'manual');
  await assert.rejects(readDelegatedUser('private-token', async () => { throw new Error('private'); }), /storage-unavailable/);
});
