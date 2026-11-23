/** HTTP boundary for the business service. All dependencies are supplied by trusted server code. */
export function createBusinessHandler({ authenticate, preAuthLimit, rateLimit, serviceForIdentity }) {
  const reply = (status, body) => new Response(JSON.stringify(body), { status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' } });
  return async request => {
    try {
      if (request.method !== 'POST') return reply(405, { error: 'method-not-allowed' });
      const match = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/invitations(?:\/([A-Za-z0-9_-]{1,128})\/accept)?$/.exec(new URL(request.url).pathname);
      const profile = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/profile\/(read|publish)$/.exec(new URL(request.url).pathname);
      const settings = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/settings\/(read|update)$/.exec(new URL(request.url).pathname);
      const asset = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/assets\/(upload|[A-Za-z0-9_-]{1,128}\/read)$/.exec(new URL(request.url).pathname);
      const createOrganization = new URL(request.url).pathname === '/v1/organizations';
      if (!match && !createOrganization && !profile && !asset && !settings) return reply(404, { error: 'not-found' });
      const auth = /^Bearer ([A-Za-z0-9_.-]{1,16384})$/.exec(request.headers.get('authorization') ?? '');
      if (!auth) return reply(401, { error: 'unauthorized' });
      if (typeof preAuthLimit !== 'function') return reply(503, { error: 'unavailable' });
      let preAllowed;
      try { preAllowed = await preAuthLimit(request); } catch { return reply(503, { error: 'unavailable' }); }
      if (preAllowed !== true) return reply(429, { error: 'rate-limited' });
      let identity;
      try { identity = await authenticate(auth[1]); } catch { return reply(401, { error: 'unauthorized' }); }
      if (!identity?.uid) return reply(401, { error: 'unauthorized' });
      if (typeof rateLimit !== 'function') return reply(503, { error: 'unavailable' });
      let allowed;
      try { allowed = await rateLimit(identity.uid); } catch { return reply(503, { error: 'unavailable' }); }
      if (allowed !== true) return reply(429, { error: 'rate-limited' });
      const size = request.headers.get('content-length');
      const limit = asset?.[2] === 'upload' ? 360448 : profile?.[2] === 'publish' ? 98304 : 4096;
      if (!size || !/^\d{1,6}$/.test(size) || Number(size) > limit) return reply(413, { error: 'invalid-size' });
      if (!/^application\/json(?:\s*;|\s*$)/i.test(request.headers.get('content-type') ?? '')) return reply(415, { error: 'invalid-content-type' });
      if (!request.body) return reply(400, { error: 'invalid-body' });
      const reader = request.body.getReader();
      const chunks = [];
      let length = 0;
      for (;;) {
        const part = await reader.read();
        if (part.done) break;
        length += part.value.byteLength;
        if (length > limit) { await reader.cancel(); return reply(413, { error: 'invalid-size' }); }
        chunks.push(part.value);
      }
      if (length !== Number(size)) return reply(400, { error: 'invalid-body' });
      const bytes = new Uint8Array(length);
      let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
      let payload;
      try { payload = JSON.parse(new TextDecoder().decode(bytes)); } catch { return reply(400, { error: 'invalid-body' }); }
      if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return reply(400, { error: 'invalid-body' });
      const service = serviceForIdentity(identity);
      try {
        if (createOrganization) {
          if (Object.keys(payload).length !== 2 || typeof payload.name !== 'string' || typeof payload.contactEmail !== 'string') return reply(400, { error: 'invalid-body' });
          return reply(201, await service.createOrganization(null, payload.name, payload.contactEmail));
        }
        if (profile) {
          if (profile[2] === 'read') {
            if (Object.keys(payload).length) return reply(400, { error: 'invalid-body' });
            return reply(200, await service.readProfile(null, profile[1]));
          }
          if (Object.keys(payload).length !== 1 || typeof payload.layoutJSON !== 'string') return reply(400, { error: 'invalid-body' });
          return reply(201, await service.publishProfile(null, profile[1], payload.layoutJSON));
        }
        if (settings) {
          if (settings[2] === 'read') {
            if (Object.keys(payload).length) return reply(400, { error: 'invalid-body' });
            return reply(200, await service.readOrganization(null, settings[1]));
          }
          if (Object.keys(payload).length !== 3 || typeof payload.name !== 'string' || typeof payload.contactEmail !== 'string' || typeof payload.photoAssetId !== 'string') return reply(400, { error: 'invalid-body' });
          return reply(200, await service.updateOrganization(null, settings[1], payload.name, payload.contactEmail, payload.photoAssetId));
        }
        if (asset) {
          if (asset[2] === 'upload') {
            if (Object.keys(payload).length !== 2 || typeof payload.mimeType !== 'string' || typeof payload.base64 !== 'string') return reply(400, { error: 'invalid-body' });
            return reply(201, await service.uploadAsset(null, asset[1], payload.mimeType, payload.base64));
          }
          if (Object.keys(payload).length) return reply(400, { error: 'invalid-body' });
          return reply(200, await service.readAsset(null, asset[1], asset[2].slice(0, -5)));
        }
        if (match[2]) {
          if (Object.keys(payload).length) return reply(400, { error: 'invalid-body' });
          return reply(200, await service.accept(null, match[1], match[2]));
        }
        if (Object.keys(payload).length !== 1 || typeof payload.email !== 'string') return reply(400, { error: 'invalid-body' });
        return reply(201, await service.invite(null, match[1], payload.email));
      } catch (error) {
        if (['invalid-request', 'invalid-invitation', 'already-member', 'forbidden', 'forbidden-or-full', 'full', 'not-found'].includes(error?.message)) return reply(403, { error: 'operation-not-allowed' });
        return reply(503, { error: 'unavailable' });
      }
    } catch { return reply(503, { error: 'unavailable' }); }
  };
}
