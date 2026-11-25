import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createCredentialVault } from './business-credential-vault.mjs';

test('provider credentials remain confidential and bound to organization and owner', async () => {
  const key = Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString('base64');
  const vault = await createCredentialVault(key);
  const credential = { providerAccountId: 'microsoft-user', refreshToken: 'test-secret-token' };
  const first = await vault.seal('org', 'owner', credential);
  const second = await vault.seal('org', 'owner', credential);
  assert.notEqual(first.iv, second.iv);
  assert.equal(JSON.stringify(first).includes(credential.refreshToken), false);
  assert.deepEqual(await vault.open('org', 'owner', first), credential);
  await assert.rejects(vault.open('other', 'owner', first), /invalid-vault-data/);
  await assert.rejects(vault.open('org', 'other', first), /invalid-vault-data/);
  await assert.rejects(vault.open('org', 'owner', first, 'gmail'), /invalid-vault-data/);
  const mail = await vault.seal('org', 'owner', credential, 'microsoft-mail');
  assert.deepEqual(await vault.open('org', 'owner', mail, 'microsoft-mail'), credential);
  await assert.rejects(vault.open('org', 'owner', mail, 'onedrive'), /invalid-vault-data/);
  await assert.rejects(vault.open('org', 'owner', mail, 'gmail'), /invalid-vault-data/);
  await assert.rejects(vault.open('other', 'owner', mail, 'microsoft-mail'), /invalid-vault-data/);
  const googleDrive = await vault.seal('org', 'owner', credential, 'google-drive');
  assert.deepEqual(await vault.open('org', 'owner', googleDrive, 'google-drive'), credential);
  await assert.rejects(vault.open('org', 'owner', googleDrive, 'gmail'), /invalid-vault-data/);
  const bytes = Buffer.from(first.ciphertext, 'base64'); bytes[0] ^= 1;
  await assert.rejects(vault.open('org', 'owner', { ...first, ciphertext: bytes.toString('base64') }), /invalid-vault-data/);
  await assert.rejects(vault.seal('org', 'owner', { ...credential, extra: 'unexpected' }), /invalid-credential/);
  await assert.rejects(createCredentialVault('dG9vc2hvcnQ='), /invalid-vault-key/);
});
