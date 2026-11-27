/** Compare provider destinations without returning the account or drive identifier. */
export async function storageFingerprint(provider, canonicalId, userId) {
  if (!['oneDrive', 'googleDrive'].includes(provider) || !validIdentifier(canonicalId) || !validIdentifier(userId)) {
    throw new Error('invalid-storage-identity');
  }
  // Scope the pseudonym to one app user to avoid a cross-user tracking ID.
  const encoder = new TextEncoder();
  const payload = ['photomark-storage-v1', userId, provider, canonicalId]
    .map(value => `${encoder.encode(value).length}:${value}`).join('');
  const bytes = encoder.encode(payload);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
}

function validIdentifier(value) {
  return typeof value === 'string' && value.length > 0 && new TextEncoder().encode(value).length <= 512 && !/[\x00-\x1f\x7f]/.test(value);
}

/** An unknown destination must remain pending, never be assumed distinct. */
export function compareStorageFingerprints(first, second) {
  if (!/^[0-9a-f]{64}$/.test(first ?? '') || !/^[0-9a-f]{64}$/.test(second ?? '')) return 'unknown';
  return first === second ? 'same' : 'different';
}
