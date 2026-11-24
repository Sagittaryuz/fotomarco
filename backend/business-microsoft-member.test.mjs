import { test } from 'node:test';
import assert from 'node:assert/strict';
import { verifiedMicrosoftMember } from './business-microsoft-member.mjs';

test('uses the provider response to identify the member, without retaining the token', async () => {
  const result = await verifiedMicrosoftMember('access-token', { fetchImpl: async (url, request) => {
    assert.equal(url, 'https://graph.microsoft.com/v1.0/me?$select=id,mail,userPrincipalName');
    assert.equal(request.headers.authorization, 'Bearer access-token');
    assert.equal(request.redirect, 'manual');
    return { status: 200, json: async () => ({ id: 'verified-id', mail: 'Member@Example.com', userPrincipalName: 'other@example.com' }) };
  } });
  assert.deepEqual(result, { providerAccountId: 'verified-id', email: 'member@example.com' });
});

test('refuses invalid tokens and provider identities without a usable email', async () => {
  await assert.rejects(verifiedMicrosoftMember('bad\ntoken'), /invalid-provider-credential/);
  await assert.rejects(verifiedMicrosoftMember('token', { fetchImpl: async () => ({ status: 401 }) }), /provider-unavailable/);
  await assert.rejects(verifiedMicrosoftMember('token', { fetchImpl: async () => ({ status: 200, json: async () => ({ id: 'id', mail: null }) }) }), /provider-identity-mismatch/);
});
