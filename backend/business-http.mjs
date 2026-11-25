/** HTTP boundary for the business service. All dependencies are supplied by trusted server code. */
export function createBusinessHandler({ authenticate, preAuthLimit, rateLimit, serviceForIdentity }) {
  const reply = (status, body) => new Response(JSON.stringify(body), { status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' } });
  return async request => {
    try {
      if (request.method !== 'POST') return reply(405, { error: 'method-not-allowed' });
      const match = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/invitations(?:\/([A-Za-z0-9_-]{1,128})\/accept)?$/.exec(new URL(request.url).pathname);
      const profile = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/profile\/(read|publish|initialize)$/.exec(new URL(request.url).pathname);
      const settings = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/settings\/(read|update)$/.exec(new URL(request.url).pathname);
      const members = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/members\/list$/.exec(new URL(request.url).pathname);
      const removeMember = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/members\/([A-Za-z0-9_-]{1,128})\/remove$/.exec(new URL(request.url).pathname);
      const connectOneDrive = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/storage\/onedrive\/connect$/.exec(new URL(request.url).pathname);
      const connectGoogleDrive = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/storage\/google-drive\/connect$/.exec(new URL(request.url).pathname);
      const provisionOwnerFolder = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/storage\/onedrive\/provision-owner$/.exec(new URL(request.url).pathname);
      const bindMicrosoftMember = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/storage\/onedrive\/bind-member$/.exec(new URL(request.url).pathname);
      const bindGoogleDriveMember = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/storage\/google-drive\/bind-member$/.exec(new URL(request.url).pathname);
      const provisionMemberFolder = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/storage\/onedrive\/provision-member$/.exec(new URL(request.url).pathname);
      const connectGoogleMail = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/mail\/gmail\/connect$/.exec(new URL(request.url).pathname);
      const connectMicrosoftMail = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/mail\/microsoft\/connect$/.exec(new URL(request.url).pathname);
      const reserveCapture = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/captures\/reserve$/.exec(new URL(request.url).pathname);
      const listCaptures = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/captures\/list$/.exec(new URL(request.url).pathname);
      const readCapture = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/captures\/([A-Za-z0-9_-]{1,128})\/(thumbnail|image)$/.exec(new URL(request.url).pathname);
      const startUpload = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/captures\/([A-Za-z0-9_-]{1,128})\/(original|stamped)\/start$/.exec(new URL(request.url).pathname);
      const uploadChunk = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/captures\/([A-Za-z0-9_-]{1,128})\/(original|stamped)\/chunk$/.exec(new URL(request.url).pathname);
      const verifyCapture = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/captures\/([A-Za-z0-9_-]{1,128})\/(original|stamped)\/verify$/.exec(new URL(request.url).pathname);
      const reconcileCapture = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/captures\/([A-Za-z0-9_-]{1,128})\/(original|stamped)\/reconcile$/.exec(new URL(request.url).pathname);
      const asset = /^\/v1\/organizations\/([A-Za-z0-9_-]{1,128})\/assets\/(upload|[A-Za-z0-9_-]{1,128}\/read)$/.exec(new URL(request.url).pathname);
      const createOrganization = new URL(request.url).pathname === '/v1/organizations';
      const mine = new URL(request.url).pathname === '/v1/organizations/mine';
      const bootstrapOwner = new URL(request.url).pathname === '/v1/organizations/bootstrap-owner';
      if (!match && !createOrganization && !profile && !asset && !settings && !members && !mine && !bootstrapOwner && !connectOneDrive && !connectGoogleDrive && !provisionOwnerFolder && !bindMicrosoftMember && !bindGoogleDriveMember && !provisionMemberFolder && !connectGoogleMail && !connectMicrosoftMail && !removeMember && !reserveCapture && !listCaptures && !readCapture && !startUpload && !uploadChunk && !verifyCapture && !reconcileCapture) return reply(404, { error: 'not-found' });
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
      const limit = uploadChunk ? 320 * 1024 * 10 : asset?.[2] === 'upload' ? 360448 : profile?.[2] === 'publish' ? 98304 : (connectOneDrive || connectGoogleDrive || connectGoogleMail || connectMicrosoftMail || bindMicrosoftMember || bindGoogleDriveMember || provisionMemberFolder) ? 20000 : 4096;
      if (!size || !/^\d{1,7}$/.test(size) || Number(size) < 1 || Number(size) > limit) return reply(413, { error: 'invalid-size' });
      const expectedType = uploadChunk ? /^application\/octet-stream(?:\s*;|\s*$)/i : /^application\/json(?:\s*;|\s*$)/i;
      if (!expectedType.test(request.headers.get('content-type') ?? '')) return reply(415, { error: 'invalid-content-type' });
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
      if (!uploadChunk) {
        try { payload = JSON.parse(new TextDecoder().decode(bytes)); } catch { return reply(400, { error: 'invalid-body' }); }
        if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return reply(400, { error: 'invalid-body' });
      }
      const service = serviceForIdentity(identity);
      try {
        if (bootstrapOwner) {
          if (Object.keys(payload).length) return reply(400, { error: 'invalid-body' });
          return reply(200, await service.ensureOwnerOrganization(null));
        }
        if (readCapture) {
          if (Object.keys(payload).length) return reply(400, { error: 'invalid-body' });
          const body = await service.readCapture(null, readCapture[1], readCapture[2], readCapture[3] === 'thumbnail');
          return new Response(body, { status: 200, headers: { 'content-type': 'image/jpeg', 'cache-control': 'private, no-store', 'x-content-type-options': 'nosniff' } });
        }
        if (listCaptures) {
          if (Object.keys(payload).some(key => key !== 'cursor') || (payload.cursor !== undefined && typeof payload.cursor !== 'string')) return reply(400, { error: 'invalid-body' });
          return reply(200, await service.listCaptures(null, listCaptures[1], payload.cursor ?? ''));
        }
        if (provisionMemberFolder) {
          if (Object.keys(payload).length !== 1 || typeof payload.accessToken !== 'string') return reply(400, { error: 'invalid-body' });
          return reply(200, await service.provisionMemberFolder(null, provisionMemberFolder[1], payload.accessToken));
        }
        if (bindMicrosoftMember) {
          if (Object.keys(payload).length !== 1 || typeof payload.accessToken !== 'string') return reply(400, { error: 'invalid-body' });
          return reply(200, await service.bindMicrosoftMember(null, bindMicrosoftMember[1], payload.accessToken));
        }
        if (bindGoogleDriveMember) {
          if (Object.keys(payload).length !== 1 || typeof payload.accessToken !== 'string') return reply(400, { error: 'invalid-body' });
          return reply(200, await service.bindGoogleDriveMember(null, bindGoogleDriveMember[1], payload.accessToken));
        }
        if (provisionOwnerFolder) {
          if (Object.keys(payload).length) return reply(400, { error: 'invalid-body' });
          return reply(200, await service.provisionOwnerFolder(null, provisionOwnerFolder[1]));
        }
        if (reconcileCapture) {
          if (Object.keys(payload).length) return reply(400, { error: 'invalid-body' });
          return reply(200, await service.reconcileCapture(null, reconcileCapture[1], reconcileCapture[2], reconcileCapture[3]));
        }
        if (verifyCapture) {
          if (Object.keys(payload).length) return reply(400, { error: 'invalid-body' });
          return reply(200, await service.verifyCapture(null, verifyCapture[1], verifyCapture[2], verifyCapture[3]));
        }
        if (uploadChunk) {
          const position = request.headers.get('x-upload-offset');
          if (!position || !/^\d{1,12}$/.test(position) || !Number.isSafeInteger(Number(position))) return reply(400, { error: 'invalid-offset' });
          return reply(200, await service.sendCaptureChunk(null, uploadChunk[1], uploadChunk[2], uploadChunk[3], Number(position), bytes));
        }
        if (startUpload) {
          if (Object.keys(payload).length) return reply(400, { error: 'invalid-body' });
          return reply(200, await service.startCaptureUpload(null, startUpload[1], startUpload[2], startUpload[3]));
        }
        if (reserveCapture) {
          if (Object.keys(payload).length !== 4 || typeof payload.captureId !== 'string' || typeof payload.filename !== 'string' ||
              typeof payload.byteCount !== 'number' || typeof payload.sha256 !== 'string') return reply(400, { error: 'invalid-body' });
          return reply(200, await service.reserveCapture(null, reserveCapture[1], payload.captureId, payload.filename, payload.byteCount, payload.sha256));
        }
        if (removeMember) {
          if (Object.keys(payload).length) return reply(400, { error: 'invalid-body' });
          const result = await service.removeMember(null, removeMember[1], removeMember[2]);
          return reply(result.complete ? 200 : 202, result);
        }
        if (connectGoogleMail) {
          if (Object.keys(payload).length !== 1 || typeof payload.refreshToken !== 'string') return reply(400, { error: 'invalid-body' });
          return reply(200, await service.connectGoogleMail(null, connectGoogleMail[1], payload.refreshToken));
        }
        if (connectMicrosoftMail) {
          if (Object.keys(payload).length !== 1 || typeof payload.refreshToken !== 'string') return reply(400, { error: 'invalid-body' });
          return reply(200, await service.connectMicrosoftMail(null, connectMicrosoftMail[1], payload.refreshToken));
        }
        if (connectOneDrive) {
          if (Object.keys(payload).length !== 1 || typeof payload.refreshToken !== 'string') return reply(400, { error: 'invalid-body' });
          return reply(200, await service.connectOneDrive(null, connectOneDrive[1], payload.refreshToken));
        }
        if (connectGoogleDrive) {
          if (Object.keys(payload).length !== 1 || typeof payload.refreshToken !== 'string') return reply(400, { error: 'invalid-body' });
          return reply(200, await service.connectGoogleDrive(null, connectGoogleDrive[1], payload.refreshToken));
        }
        if (mine) {
          if (Object.keys(payload).length) return reply(400, { error: 'invalid-body' });
          return reply(200, await service.myOrganizations(null));
        }
        if (members) {
          if (Object.keys(payload).length) return reply(400, { error: 'invalid-body' });
          return reply(200, await service.listMembers(null, members[1]));
        }
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
          return reply(201, await service.publishProfile(null, profile[1], payload.layoutJSON, profile[2] === 'initialize'));
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
        // Return only a fixed, non-sensitive diagnostic for the authenticated
        // owner connection flow; never forward provider responses or credentials.
        if (connectOneDrive && ['provider-token-unavailable', 'provider-graph-unavailable',
          'provider-permission-missing', 'provider-identity-mismatch', 'invalid-microsoft-client'].includes(error?.message)) {
          return reply(503, { error: error.message });
        }
        if (error?.message === 'storage-account-change-requires-migration') return reply(409, { error: 'storage-account-change-requires-migration' });
        if (error?.message === 'mailbox-mismatch') return reply(422, { error: 'mailbox-mismatch' });
        if (error?.message === 'mail-not-configured') return reply(412, { error: 'mail-not-configured' });
        if (['invalid-request', 'invalid-invitation', 'already-member', 'revocation-pending', 'capture-conflict', 'forbidden', 'forbidden-or-full', 'full', 'not-found'].includes(error?.message)) return reply(403, { error: 'operation-not-allowed' });
        return reply(503, { error: 'unavailable' });
      }
    } catch { return reply(503, { error: 'unavailable' }); }
  };
}
