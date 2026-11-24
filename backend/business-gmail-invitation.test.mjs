import { test } from 'node:test';
import assert from 'node:assert/strict';
import { gmailInvitationSender } from './business-gmail-invitation.mjs';

const sample = { accessToken: 'private-token', senderEmail: 'owner@example.com', recipientEmail: 'member@example.com',
  organizationName: 'Equipe Construção', organizationId: '11111111-1111-4111-8111-111111111111',
  invitationId: '22222222-2222-4222-8222-222222222222' };

test('checks the sender mailbox and sends the intended invitation without exposing the token', async () => {
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({ url, options });
    if (url.endsWith('/profile')) return { status: 200, json: async () => ({ emailAddress: 'owner@example.com' }) };
    return { status: 200, json: async () => ({ id: 'message-id' }) };
  };
  const send = gmailInvitationSender({ invitationOrigin: 'https://business.example', fetchImpl });
  assert.deepEqual(await send(sample), { delivered: true });
  assert.equal(calls.length, 2);
  const raw = JSON.parse(calls[1].options.body).raw;
  const mime = Buffer.from(raw, 'base64url').toString('utf8');
  assert.match(mime, /To: member@example.com/);
  assert.match(mime, /Equipe Construção/);
  assert.match(mime, /https:\/\/business\.example\/convite\?/);
  assert.equal(mime.includes(sample.accessToken), false);
});

test('refuses mismatched senders and header injection before sending', async () => {
  let sent = false;
  const send = gmailInvitationSender({ invitationOrigin: 'https://business.example', fetchImpl: async (url) => {
    if (url.endsWith('/profile')) return { status: 200, json: async () => ({ emailAddress: 'other@example.com' }) };
    sent = true;
    throw new Error('unexpected');
  } });
  await assert.rejects(send(sample), /mailbox-mismatch/);
  await assert.rejects(send({ ...sample, recipientEmail: 'a@example.com\r\nBcc: x@example.com' }), /invalid-mail-request/);
  assert.equal(sent, false);
});
