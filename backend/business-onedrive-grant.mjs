import { verifyOneDriveMemberFolder } from './business-onedrive-verify.mjs';

/** Caller must load membership from trusted storage and derive both member fields from
 * the same verified Microsoft identity. This function never accepts client-supplied tokens. */
export async function grantOneDriveMemberFolder({ memberVerifiedEmail, verifyRecipientIdentity, ...configuration }) {
  if (typeof memberVerifiedEmail !== 'string' || memberVerifiedEmail.length > 254 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(memberVerifiedEmail)) throw new Error('invalid-member-identity');
  // Identity resolution must be provider-verified server side before any sharing,
  // not inferred from an email address supplied by the client.
  if (typeof verifyRecipientIdentity !== 'function' ||
      await verifyRecipientIdentity(memberVerifiedEmail, configuration.memberIdentityId) !== true) throw new Error('unverified-recipient');
  try {
    return await verifyOneDriveMemberFolder(configuration);
  } catch (error) {
    if (error?.message !== 'unsafe-folder-permissions') throw error;
  }
  // A folder containing any other recipient, public link or incomplete ACL fails here.
  await verifyOneDriveMemberFolder({ ...configuration, requireMember: false });
  const fetchImpl = configuration.fetchImpl ?? fetch;
  const url = `https://graph.microsoft.com/v1.0/me/drive/items/${encodeURIComponent(configuration.folderId)}/invite`;
  const response = await fetchImpl(url, { method: 'POST', redirect: 'manual',
    headers: { authorization: `Bearer ${configuration.ownerToken}`, 'content-type': 'application/json' },
    body: JSON.stringify({ recipients: [{ email: memberVerifiedEmail }], requireSignIn: true,
      sendInvitation: false, roles: ['write'] }) });
  // Multi-status/partial success is ambiguous; never mark the folder ready from it.
  if (response.status !== 200) throw new Error('storage-grant-unconfirmed');
  return verifyOneDriveMemberFolder(configuration);
}
