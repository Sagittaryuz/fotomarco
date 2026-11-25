import { test } from 'node:test';
import assert from 'node:assert/strict';
import { microsoftInvitationSender } from './business-microsoft-invitation.mjs';

const sample = { accessToken: 'private-token', expectedAccountId: 'account', recipientEmail: 'member@example.com',
  organizationName: 'Equipe Construção', organizationId: '11111111-1111-4111-8111-111111111111',
  invitationId: '22222222-2222-4222-8222-222222222222' };

test('checks account and submits invitation without exposing credentials in the message', async () => {
  const calls = [];
  const send = microsoftInvitationSender({ invitationOrigin: 'https://business.example', fetchImpl: async (url, options) => {
    calls.push({ url, options });
    return url.includes('/me?') ? { status: 200, json: async () => ({ id: 'account' }) } : { status: 202 };
  } });
  assert.deepEqual(await send(sample), { accepted: true });
  const body = JSON.parse(calls[1].options.body);
  assert.equal(body.message.toRecipients[0].emailAddress.address, sample.recipientEmail);
  assert.match(body.message.body.content, /https:\/\/business\.example\/convite\?/);
  assert.ok(!calls[1].options.body.includes(sample.accessToken));
});

test('rejects a different sender identity and unsafe recipient without sending', async () => {
  let requests = 0;
  const send = microsoftInvitationSender({ invitationOrigin: 'https://business.example', fetchImpl: async () => {
    requests++; return { status: 200, json: async () => ({ id: 'other' }) };
  } });
  await assert.rejects(send(sample), /mailbox-mismatch/);
  await assert.rejects(send({ ...sample, recipientEmail: 'a@example.com\r\nBcc: b@example.com' }), /invalid-mail-request/);
  assert.equal(requests, 1);
});
