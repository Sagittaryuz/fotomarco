import { test } from 'node:test';
import assert from 'node:assert/strict';
import { googleBusinessMailCredential } from './business-google-mail-oauth.mjs';

test('accepts only a verified Google identity with the send-only Gmail scope', async () => {
  const create = (scope, verified) => googleBusinessMailCredential({ clientId: '123-abc.apps.googleusercontent.com', fetchImpl: async url => {
    if (url.endsWith('/token')) return { status: 200, json: async () => ({ access_token: 'access', scope }) };
    return { status: 200, json: async () => ({ sub: 'google-user', email: 'Owner@example.com', email_verified: verified }) };
  } });
  const success = await create('openid email https://www.googleapis.com/auth/gmail.send', true)('refresh');
  assert.equal(success.email, 'owner@example.com');
  assert.equal(success.refreshToken, 'refresh');
  await assert.rejects(create('openid email', true)('refresh'), /provider-permission-missing/);
  await assert.rejects(create('openid email https://www.googleapis.com/auth/gmail.send', false)('refresh'), /provider-identity-mismatch/);
});
