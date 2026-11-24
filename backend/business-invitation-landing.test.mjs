import { test } from 'node:test';
import assert from 'node:assert/strict';
import { invitationLanding } from './business-invitation-landing.mjs';

test('safe invitation page opens the matching app deep link without leaking referrers', async () => {
  const org = '11111111-1111-4111-8111-111111111111';
  const invitation = '22222222-2222-4222-8222-222222222222';
  const response = invitationLanding(new Request(`https://business.example/convite?organization=${org}&invitation=${invitation}`));
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('referrer-policy'), 'no-referrer');
  assert.match(await response.text(), new RegExp(`momentra://business/invite\\?organization=${org}&amp;invitation=${invitation}`));
  assert.equal(invitationLanding(new Request(`https://business.example/convite?organization=${org}&invitation=${invitation}&other=x`)).status, 400);
  assert.equal(invitationLanding(new Request('https://business.example/convite?organization=<script>&invitation=x')).status, 400);
});
