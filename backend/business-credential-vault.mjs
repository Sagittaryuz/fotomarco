/** Encrypts provider credentials before database storage. The AES key must be
 * held separately as a Worker secret; no plaintext or token is logged. */
const encoder = new TextEncoder();
const decoder = new TextDecoder('utf-8', { fatal: true });
const id = value => {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) throw new Error('invalid-vault-context');
  return value;
};
const decode = text => {
  if (typeof text !== 'string' || !/^[A-Za-z0-9+/]*={0,2}$/.test(text) || text.length % 4 !== 0) throw new Error('invalid-vault-data');
  try { return Uint8Array.from(atob(text), c => c.charCodeAt(0)); }
  catch { throw new Error('invalid-vault-data'); }
};
const encode = bytes => btoa(Array.from(bytes, n => String.fromCharCode(n)).join(''));

export async function createCredentialVault(keyBase64) {
  const keyBytes = decode(keyBase64);
  if (keyBytes.length !== 32) throw new Error('invalid-vault-key');
  const key = await crypto.subtle.importKey('raw', keyBytes, 'AES-GCM', false, ['encrypt', 'decrypt']);
  keyBytes.fill(0);
  const context = (org, owner, purpose) => {
    if (!['onedrive', 'gmail', 'microsoft-mail'].includes(purpose)) throw new Error('invalid-vault-context');
    return encoder.encode(`photomark:business-credential:v1:${purpose}:${id(org)}:${id(owner)}`);
  };
  return {
    async seal(org, owner, credential, purpose = 'onedrive') {
      const aad = context(org, owner, purpose);
      if (!credential || typeof credential !== 'object' || Array.isArray(credential) ||
          typeof credential.refreshToken !== 'string' || !credential.refreshToken || credential.refreshToken.length > 16384 ||
          typeof credential.providerAccountId !== 'string' || !credential.providerAccountId || credential.providerAccountId.length > 256 ||
          Object.keys(credential).sort().join(',') !== 'providerAccountId,refreshToken') throw new Error('invalid-credential');
      const plaintext = encoder.encode(JSON.stringify(credential));
      const iv = crypto.getRandomValues(new Uint8Array(12));
      try {
        const encrypted = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: aad, tagLength: 128 }, key, plaintext));
        return { version: 1, iv: encode(iv), ciphertext: encode(encrypted) };
      } finally { plaintext.fill(0); }
    },
    async open(org, owner, record, purpose = 'onedrive') {
      const aad = context(org, owner, purpose);
      if (!record || record.version !== 1 || typeof record.ciphertext !== 'string' || record.ciphertext.length > 24000) throw new Error('invalid-vault-data');
      const iv = decode(record.iv);
      const ciphertext = decode(record.ciphertext);
      if (iv.length !== 12 || ciphertext.length < 16) throw new Error('invalid-vault-data');
      let plaintext;
      try {
        plaintext = new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv, additionalData: aad, tagLength: 128 }, key, ciphertext));
        const value = JSON.parse(decoder.decode(plaintext));
        if (!value || typeof value.refreshToken !== 'string' || !value.refreshToken ||
            typeof value.providerAccountId !== 'string' || !value.providerAccountId ||
            Object.keys(value).sort().join(',') !== 'providerAccountId,refreshToken') throw new Error('invalid-vault-data');
        return value;
      } catch { throw new Error('invalid-vault-data'); }
      finally { plaintext?.fill(0); }
    }
  };
}
