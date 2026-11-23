import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateMemberFolderPermissions as validate } from './business-onedrive-access.mjs';

const entry = (id, roles) => ({ roles, grantedToV2: { user: { id } } });
const input = values => ({ permissionPage: { value: values }, ownerIdentityId: 'owner', memberIdentityId: 'member', isOwnerListing: true });

test('allows only the owner and intended member', () => {
  assert.equal(validate(input([entry('owner', ['owner']), entry('member', ['write'])])), true);
  assert.equal(validate(input([entry('owner', ['owner']), entry('other', ['read'])])), false);
  assert.equal(validate(input([entry('member', ['write'])])), false);
});

test('fails closed for links, groups, incomplete listings and missing owner context', () => {
  const owner = entry('owner', ['owner']);
  assert.equal(validate(input([owner, { roles: ['read'], link: { scope: 'anonymous' } }])), false);
  assert.equal(validate(input([owner, { roles: ['read'], grantedToV2: { group: { id: 'group' } } }])), false);
  assert.equal(validate({ ...input([owner]), permissionPage: { value: [owner], '@odata.nextLink': 'next' } }), false);
  assert.equal(validate({ ...input([owner]), isOwnerListing: false }), false);
  assert.equal(validate(input([owner, entry('member', ['owner'])])), false);
});
