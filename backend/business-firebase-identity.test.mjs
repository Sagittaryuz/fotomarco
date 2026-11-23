import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair, SignJWT } from 'jose';
import { createFirebaseVerifier } from './business-firebase-identity.mjs';

test('only signed Firebase tokens for the configured project are accepted', async () => {
  const { publicKey, privateKey } = await generateKeyPair('RS256');
  const other = await generateKeyPair('RS256');
  const now = 1_800_000_000;
  const verify = createFirebaseVerifier({ projectId: 'demo-project', now: () => now * 1000, resolveKey: async () => publicKey });
  const token = ({ aud = 'demo-project', exp = now + 60, key = privateKey, authTime = now - 1, verified = true } = {}) =>
    new SignJWT({ auth_time: authTime, email: 'member@example.com', email_verified: verified })
      .setProtectedHeader({ alg: 'RS256', kid: 'key1' }).setIssuer('https://securetoken.google.com/demo-project')
      .setAudience(aud).setSubject('member-uid').setIssuedAt(now - 1).setExpirationTime(exp).sign(key);
  assert.deepEqual(await verify(await token()), { uid: 'member-uid', email: 'member@example.com', emailVerified: true });
  assert.equal((await verify(await token({ verified: false }))).emailVerified, false);
  await assert.rejects(verify(await token({ aud: 'other-project' })));
  await assert.rejects(verify(await token({ exp: now - 1 })));
  await assert.rejects(verify(await token({ authTime: now + 1 })));
  await assert.rejects(verify(await token({ key: other.privateKey })));
});
