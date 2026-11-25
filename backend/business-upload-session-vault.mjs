import { graphUploadSessionURL } from './business-onedrive-upload.mjs';
import { googleDriveUploadSessionURL } from './business-google-drive-upload.mjs';

/** An upload URL is a bearer credential. Bind it to a single user and capture. */
export async function createUploadSessionVault(keyBase64, { now = () => Date.now(), provider = 'onedrive' } = {}) {
  if (!['onedrive', 'google-drive'].includes(provider)) throw new Error('invalid-vault-context');
  const validateURL = provider === 'google-drive' ? googleDriveUploadSessionURL : graphUploadSessionURL;
  if (typeof keyBase64 !== 'string' || !/^[A-Za-z0-9+/]{43}=$/.test(keyBase64)) throw new Error('invalid-vault-key');
  let bytes;
  try { bytes = Uint8Array.from(atob(keyBase64), c => c.charCodeAt(0)); } catch { throw new Error('invalid-vault-key'); }
  if (bytes.length !== 32) throw new Error('invalid-vault-key');
  const key = await crypto.subtle.importKey('raw', bytes, 'AES-GCM', false, ['encrypt', 'decrypt']);
  bytes.fill(0);
  const context = (org, user, capture) => {
    if (![org, user, capture].every(value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value))) throw new Error('invalid-vault-context');
    const purpose = provider === 'onedrive' ? '' : ':google-drive';
    return new TextEncoder().encode(`photomark:upload-session:v1${purpose}:${org}:${user}:${capture}`);
  };
  const encode = value => btoa(Array.from(value, n => String.fromCharCode(n)).join(''));
  const decode = value => {
    if (typeof value !== 'string' || value.length > 16000 || value.length % 4 || !/^[A-Za-z0-9+/]*={0,2}$/.test(value)) throw new Error('invalid-vault-data');
    try { return Uint8Array.from(atob(value), c => c.charCodeAt(0)); } catch { throw new Error('invalid-vault-data'); }
  };
  return {
    async seal(org, user, capture, session) {
      const additionalData = context(org, user, capture);
      if (!session || Object.keys(session).sort().join(',') !== 'expiresAt,uploadUrl' ||
          !Number.isSafeInteger(session.expiresAt) || session.expiresAt <= now() || session.expiresAt > now() + 7 * 86400000) throw new Error('invalid-upload-session');
      const uploadUrl = validateURL(session.uploadUrl);
      const plaintext = new TextEncoder().encode(JSON.stringify({ uploadUrl, expiresAt: session.expiresAt }));
      const iv = crypto.getRandomValues(new Uint8Array(12));
      try {
        const encrypted = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData, tagLength: 128 }, key, plaintext));
        return { version: 1, iv: encode(iv), ciphertext: encode(encrypted) };
      } finally { plaintext.fill(0); }
    },
    async open(org, user, capture, record) {
      const additionalData = context(org, user, capture);
      if (!record || record.version !== 1) throw new Error('invalid-vault-data');
      const iv = decode(record.iv), encrypted = decode(record.ciphertext);
      if (iv.length !== 12 || encrypted.length < 16) throw new Error('invalid-vault-data');
      let plaintext;
      try {
        plaintext = new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv, additionalData, tagLength: 128 }, key, encrypted));
        const value = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(plaintext));
        if (!value || Object.keys(value).sort().join(',') !== 'expiresAt,uploadUrl' ||
            !Number.isSafeInteger(value.expiresAt) || value.expiresAt <= now()) throw new Error('invalid-vault-data');
        return { uploadUrl: validateURL(value.uploadUrl), expiresAt: value.expiresAt };
      } catch { throw new Error('invalid-vault-data'); }
      finally { plaintext?.fill(0); }
    }
  };
}
