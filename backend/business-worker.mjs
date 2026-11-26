import { createBusinessApp } from './business-app.mjs';
import { createFirebaseVerifier } from './business-firebase-identity.mjs';
import { googleServiceAccountToken } from './business-google-credential.mjs';
import { createCredentialVault } from './business-credential-vault.mjs';
import { microsoftBusinessCredential } from './business-microsoft-oauth.mjs';
import { microsoftBusinessMailCredential } from './business-microsoft-mail-oauth.mjs';
import { googleBusinessDriveCredential } from './business-google-drive-oauth.mjs';
import { invitationLanding } from './business-invitation-landing.mjs';
import { googleBusinessMailCredential } from './business-google-mail-oauth.mjs';
import { gmailInvitationSender } from './business-gmail-invitation.mjs';
import { microsoftInvitationSender } from './business-microsoft-invitation.mjs';
import { revokeOneDriveMemberFolder } from './business-onedrive-revoke.mjs';
import { verifyOneDriveMemberFolder } from './business-onedrive-verify.mjs';
import { businessUploadOffset, createBusinessUploadSession, findVerifiedBusinessUpload, sendBusinessUploadChunk, verifyBusinessUploadedItem } from './business-onedrive-upload.mjs';
import { createUploadSessionVault } from './business-upload-session-vault.mjs';
import { ensurePrivateMemberFolder } from './business-onedrive-folders.mjs';
import { verifiedMicrosoftMember } from './business-microsoft-member.mjs';
import { verifiedGoogleDriveMember } from './business-google-drive-member.mjs';
import { checkGoogleDriveRootAccess } from './business-google-drive-access.mjs';
import { prepareGoogleDriveMemberHierarchy } from './business-google-drive-hierarchy.mjs';
import { grantOneDriveMemberFolder } from './business-onedrive-grant.mjs';
import { openBusinessPhoto } from './business-onedrive-download.mjs';

/** Isolated Worker: never log credentials, tokens, emails, request bodies or provider responses. */
export function createBusinessWorker(env, overrides = {}) {
  const projectId = env.PHOTOMARK_FIREBASE_PROJECT_ID;
  const ownerEmail = env.BUSINESS_OWNER_EMAIL?.trim().toLowerCase();
  if (!ownerEmail || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(ownerEmail) ||
      !env.BUSINESS_IP_LIMIT || !env.BUSINESS_UID_LIMIT) throw new Error('missing-worker-configuration');
  const authenticate = overrides.authenticate ?? createFirebaseVerifier({ projectId });
  const serverAccessToken = overrides.serverAccessToken ?? googleServiceAccountToken({
    clientEmail: env.BUSINESS_SERVER_EMAIL, privateKey: env.BUSINESS_SERVER_PRIVATE_KEY,
  });
  const preAuthLimit = async request => {
    const ip = request.headers.get('cf-connecting-ip');
    if (!ip || !/^[0-9a-f:.]{2,45}$/i.test(ip)) return false;
    return (await env.BUSINESS_IP_LIMIT.limit({ key: ip })).success === true;
  };
  const rateLimit = async uid => (await env.BUSINESS_UID_LIMIT.limit({ key: uid })).success === true;
  const prepareOneDrive = overrides.prepareOneDrive ?? (async ({ organizationId, ownerId, refreshToken }) => {
    const exchange = microsoftBusinessCredential({ clientId: env.BUSINESS_MICROSOFT_CLIENT_ID,
      ...(overrides.fetchImpl ? { fetchImpl: overrides.fetchImpl } : {}) });
    const verified = await exchange(refreshToken);
    const vault = await createCredentialVault(env.BUSINESS_CREDENTIAL_KEY);
    const sealed = await vault.seal(organizationId, ownerId,
      { refreshToken: verified.refreshToken, providerAccountId: verified.providerAccountId });
    return { ...sealed, providerAccountId: verified.providerAccountId, driveId: verified.driveId };
  });
  const prepareGoogleDrive = overrides.prepareGoogleDrive ?? (async ({ organizationId, ownerId, refreshToken }) => {
    const exchange = googleBusinessDriveCredential({ clientId: env.BUSINESS_GOOGLE_CLIENT_ID,
      ...(overrides.fetchImpl ? { fetchImpl: overrides.fetchImpl } : {}) });
    const verified = await exchange(refreshToken);
    const vault = await createCredentialVault(env.BUSINESS_CREDENTIAL_KEY);
    const sealed = await vault.seal(organizationId, ownerId,
      { refreshToken: verified.refreshToken, providerAccountId: verified.providerAccountId }, 'google-drive');
    return { ...sealed, providerAccountId: verified.providerAccountId, ownerPermissionId: verified.ownerPermissionId };
  });
  const prepareGoogleOwnerFolder = overrides.prepareGoogleOwnerFolder ?? (async ({ organizationId, org, storage, pending }) => {
    const fetchImpl = overrides.fetchImpl ?? fetch;
    const vault = await createCredentialVault(env.BUSINESS_CREDENTIAL_KEY);
    const saved = await vault.open(organizationId, org.ownerId, storage, 'google-drive');
    if (saved.providerAccountId !== storage.providerAccountId) throw new Error('provider-identity-mismatch');
    const verified = await googleBusinessDriveCredential({ clientId: env.BUSINESS_GOOGLE_CLIENT_ID, fetchImpl })(saved.refreshToken);
    if (verified.providerAccountId !== storage.providerAccountId || verified.ownerPermissionId !== storage.ownerPermissionId) throw new Error('provider-identity-mismatch');
    const root = await checkGoogleDriveRootAccess({ accessToken: verified.accessToken, ownerPermissionId: verified.ownerPermissionId, fetchImpl });
    const result = await prepareGoogleDriveMemberHierarchy({ accessToken: verified.accessToken, rootId: root.folderId,
      imagesId: pending.imagesId, ownerPermissionId: verified.ownerPermissionId, memberName: pending.memberName,
      memberEmail: pending.memberEmail, markers: { photomark: pending.photomarkMarker, member: pending.memberMarker }, fetchImpl });
    const sealed = await vault.seal(organizationId, org.ownerId,
      { refreshToken: verified.refreshToken, providerAccountId: verified.providerAccountId }, 'google-drive');
    return { ...result, ownerCredential: { ...sealed, providerAccountId: verified.providerAccountId, ownerPermissionId: verified.ownerPermissionId } };
  });
  const prepareGoogleMail = overrides.prepareGoogleMail ?? (async ({ organizationId, ownerId, refreshToken }) => {
    const exchange = googleBusinessMailCredential({ clientId: env.BUSINESS_GOOGLE_CLIENT_ID,
      ...(overrides.fetchImpl ? { fetchImpl: overrides.fetchImpl } : {}) });
    const verified = await exchange(refreshToken);
    const vault = await createCredentialVault(env.BUSINESS_CREDENTIAL_KEY);
    const sealed = await vault.seal(organizationId, ownerId,
      { refreshToken: verified.refreshToken, providerAccountId: verified.providerAccountId }, 'gmail');
    return { ...sealed, providerAccountId: verified.providerAccountId, email: verified.email };
  });
  const prepareMicrosoftMail = overrides.prepareMicrosoftMail ?? (async ({ organizationId, ownerId, refreshToken }) => {
    const exchange = microsoftBusinessMailCredential({ clientId: env.BUSINESS_MICROSOFT_CLIENT_ID,
      ...(overrides.fetchImpl ? { fetchImpl: overrides.fetchImpl } : {}) });
    const verified = await exchange(refreshToken);
    const vault = await createCredentialVault(env.BUSINESS_CREDENTIAL_KEY);
    const sealed = await vault.seal(organizationId, ownerId,
      { refreshToken: verified.refreshToken, providerAccountId: verified.providerAccountId }, 'microsoft-mail');
    return { ...sealed, providerAccountId: verified.providerAccountId, email: verified.email };
  });
  const prepareOwnerFolder = overrides.prepareOwnerFolder ?? (async ({ organizationId, org, storage, marker, name, email }) => {
    const vault = await createCredentialVault(env.BUSINESS_CREDENTIAL_KEY);
    const saved = await vault.open(organizationId, org.ownerId, storage);
    if (saved.providerAccountId !== storage.providerAccountId) throw new Error('provider-identity-mismatch');
    const exchange = microsoftBusinessCredential({ clientId: env.BUSINESS_MICROSOFT_CLIENT_ID,
      ...(overrides.fetchImpl ? { fetchImpl: overrides.fetchImpl } : {}) });
    const verified = await exchange(saved.refreshToken);
    if (verified.providerAccountId !== storage.providerAccountId || verified.driveId !== storage.driveId) throw new Error('provider-identity-mismatch');
    const folder = await ensurePrivateMemberFolder({ ownerToken: verified.accessToken, expectedOwnerId: verified.providerAccountId,
      expectedDriveId: verified.driveId, memberIdentityId: verified.providerAccountId, memberName: name, memberEmail: email,
      creationMarker: marker, ...(overrides.fetchImpl ? { fetchImpl: overrides.fetchImpl } : {}) });
    await verifyOneDriveMemberFolder({ ownerToken: verified.accessToken, expectedOwnerId: verified.providerAccountId,
      expectedDriveId: verified.driveId, expectedParentId: folder.parentId, folderId: folder.folderId,
      memberIdentityId: verified.providerAccountId, ...(overrides.fetchImpl ? { fetchImpl: overrides.fetchImpl } : {}) });
    const sealed = await vault.seal(organizationId, org.ownerId,
      { refreshToken: verified.refreshToken, providerAccountId: verified.providerAccountId });
    return { ...folder, memberIdentityId: verified.providerAccountId,
      ownerCredential: { ...sealed, providerAccountId: verified.providerAccountId, driveId: verified.driveId } };
  });
  const prepareMemberFolder = overrides.prepareMemberFolder ?? (async ({ organizationId, org, member, storage, marker, name, email, provider }) => {
    const fetcher = overrides.fetchImpl ?? fetch;
    const boundedFetch = (url, options = {}) => fetcher(url, { ...options, signal: AbortSignal.timeout(30000) });
    const vault = await createCredentialVault(env.BUSINESS_CREDENTIAL_KEY);
    const saved = await vault.open(organizationId, org.ownerId, storage);
    if (saved.providerAccountId !== storage.providerAccountId) throw new Error('provider-identity-mismatch');
    const exchange = microsoftBusinessCredential({ clientId: env.BUSINESS_MICROSOFT_CLIENT_ID, fetchImpl: boundedFetch });
    const verified = await exchange(saved.refreshToken);
    if (verified.providerAccountId !== storage.providerAccountId || verified.driveId !== storage.driveId) throw new Error('provider-identity-mismatch');
    const result = await ensurePrivateMemberFolder({ ownerToken: verified.accessToken, expectedOwnerId: verified.providerAccountId,
      expectedDriveId: verified.driveId, memberIdentityId: provider.providerAccountId, memberName: name, memberEmail: email,
      creationMarker: marker, ...(member.oneDriveFolderId ? { knownMemberFolderId: member.oneDriveFolderId } : {}), fetchImpl: boundedFetch });
    const sealed = await vault.seal(organizationId, org.ownerId,
      { refreshToken: verified.refreshToken, providerAccountId: verified.providerAccountId });
    return { ...result, memberIdentityId: provider.providerAccountId, ownerAccessToken: verified.accessToken,
      ownerCredential: { ...sealed, providerAccountId: verified.providerAccountId, driveId: verified.driveId } };
  });
  const grantMemberFolder = overrides.grantMemberFolder ?? (async ({ storage, provider, folder }) => {
    const fetcher = overrides.fetchImpl ?? fetch;
    const boundedFetch = (url, options = {}) => fetcher(url, { ...options, signal: AbortSignal.timeout(10000) });
    await grantOneDriveMemberFolder({ ownerToken: folder.ownerAccessToken, expectedOwnerId: storage.providerAccountId,
      expectedDriveId: storage.driveId, expectedParentId: folder.parentId, folderId: folder.folderId,
      memberIdentityId: provider.providerAccountId, memberVerifiedEmail: provider.email,
      verifyRecipientIdentity: async (email, id) => email === provider.email && id === provider.providerAccountId,
      fetchImpl: boundedFetch });
    return true;
  });
  const prepareMailDelivery = overrides.prepareMailDelivery ?? (async ({ organizationId, organization, mail, provider }) => {
    const vault = await createCredentialVault(env.BUSINESS_CREDENTIAL_KEY);
    if (provider === 'microsoft') {
      const saved = await vault.open(organizationId, organization.ownerId, mail, 'microsoft-mail');
      if (saved.providerAccountId !== mail.providerAccountId) throw new Error('provider-identity-mismatch');
      const exchange = microsoftBusinessMailCredential({ clientId: env.BUSINESS_MICROSOFT_CLIENT_ID,
        ...(overrides.fetchImpl ? { fetchImpl: overrides.fetchImpl } : {}) });
      const verified = await exchange(saved.refreshToken);
      if (verified.providerAccountId !== mail.providerAccountId || verified.email !== organization.contactEmail) throw new Error('mailbox-mismatch');
      const sealed = await vault.seal(organizationId, organization.ownerId,
        { refreshToken: verified.refreshToken, providerAccountId: verified.providerAccountId }, 'microsoft-mail');
      const sender = microsoftInvitationSender({ invitationOrigin: env.BUSINESS_PUBLIC_ORIGIN,
        ...(overrides.fetchImpl ? { fetchImpl: overrides.fetchImpl } : {}) });
      return { record: { ...sealed, providerAccountId: verified.providerAccountId, email: verified.email },
        send: ({ recipientEmail, organizationName, organizationId: org, invitationId }) => sender({
          accessToken: verified.accessToken, expectedAccountId: verified.providerAccountId, recipientEmail, organizationName, organizationId: org, invitationId
        }) };
    }
    if (provider !== 'gmail') throw new Error('mail-not-configured');
    const saved = await vault.open(organizationId, organization.ownerId, mail, 'gmail');
    if (saved.providerAccountId !== mail.providerAccountId) throw new Error('provider-identity-mismatch');
    const exchange = googleBusinessMailCredential({ clientId: env.BUSINESS_GOOGLE_CLIENT_ID,
      ...(overrides.fetchImpl ? { fetchImpl: overrides.fetchImpl } : {}) });
    const verified = await exchange(saved.refreshToken);
    if (verified.providerAccountId !== mail.providerAccountId || verified.email !== organization.contactEmail) throw new Error('mailbox-mismatch');
    const sealed = await vault.seal(organizationId, organization.ownerId,
      { refreshToken: verified.refreshToken, providerAccountId: verified.providerAccountId }, 'gmail');
    const sender = gmailInvitationSender({ invitationOrigin: env.BUSINESS_PUBLIC_ORIGIN,
      ...(overrides.fetchImpl ? { fetchImpl: overrides.fetchImpl } : {}) });
    return { record: { ...sealed, providerAccountId: verified.providerAccountId, email: verified.email },
      send: ({ recipientEmail, organizationName, organizationId: org, invitationId }) => sender({
        accessToken: verified.accessToken, senderEmail: verified.email, recipientEmail, organizationName, organizationId: org, invitationId
      }) };
  });
  const revokeMemberStorage = overrides.revokeMemberStorage ?? (async ({ organizationId, organization, member, transaction }) => {
    if (!['granted', 'provisioning'].includes(member.storageStatus) || !member.oneDriveFolderId || !member.oneDriveParentId || !member.oneDriveMemberIdentityId) return false;
    const saved = await transaction(tx => tx.oneDriveCredential(organizationId));
    if (!saved) return false;
    const vault = await createCredentialVault(env.BUSINESS_CREDENTIAL_KEY);
    const credential = await vault.open(organizationId, organization.ownerId, saved);
    if (credential.providerAccountId !== saved.providerAccountId) throw new Error('provider-identity-mismatch');
    const exchange = microsoftBusinessCredential({ clientId: env.BUSINESS_MICROSOFT_CLIENT_ID,
      ...(overrides.fetchImpl ? { fetchImpl: overrides.fetchImpl } : {}) });
    const verified = await exchange(credential.refreshToken);
    if (verified.providerAccountId !== saved.providerAccountId || verified.driveId !== saved.driveId) throw new Error('provider-identity-mismatch');
    const sealed = await vault.seal(organizationId, organization.ownerId,
      { refreshToken: verified.refreshToken, providerAccountId: verified.providerAccountId });
    await transaction(async tx => {
      const currentOrg = await tx.organization(organizationId);
      const currentMember = await tx.membership(organizationId, member.userId);
      const currentCredential = await tx.oneDriveCredential(organizationId);
      if (currentOrg?.ownerId !== organization.ownerId || currentMember?.revocationState !== 'pending' ||
          currentMember.revocationId !== member.revocationId || currentMember.storageStatus !== member.storageStatus ||
          currentMember.oneDriveFolderId !== member.oneDriveFolderId || currentMember.oneDriveParentId !== member.oneDriveParentId ||
          currentMember.oneDriveMemberIdentityId !== member.oneDriveMemberIdentityId ||
          currentCredential?.ciphertext !== saved.ciphertext || currentCredential?.iv !== saved.iv) throw new Error('revocation-conflict');
      await tx.setOneDriveCredential(organizationId, { ...sealed, providerAccountId: verified.providerAccountId, driveId: verified.driveId });
    });
    const result = await revokeOneDriveMemberFolder({ ownerToken: verified.accessToken, expectedOwnerId: verified.providerAccountId,
      expectedDriveId: verified.driveId, expectedParentId: member.oneDriveParentId, folderId: member.oneDriveFolderId,
      memberIdentityId: member.oneDriveMemberIdentityId, ...(overrides.fetchImpl ? { fetchImpl: overrides.fetchImpl } : {}) });
    return result.revoked === true;
  });
  const prepareUpload = overrides.prepareUpload ?? (async ({ organizationId, identity, org, capture, storage }) => {
    const vault = await createCredentialVault(env.BUSINESS_CREDENTIAL_KEY);
    const saved = await vault.open(organizationId, org.ownerId, storage);
    if (saved.providerAccountId !== storage.providerAccountId) throw new Error('provider-identity-mismatch');
    const exchange = microsoftBusinessCredential({ clientId: env.BUSINESS_MICROSOFT_CLIENT_ID,
      ...(overrides.fetchImpl ? { fetchImpl: overrides.fetchImpl } : {}) });
    const verified = await exchange(saved.refreshToken);
    if (verified.providerAccountId !== storage.providerAccountId || verified.driveId !== storage.driveId) throw new Error('provider-identity-mismatch');
    await verifyOneDriveMemberFolder({ ownerToken: verified.accessToken, expectedOwnerId: verified.providerAccountId,
      expectedDriveId: verified.driveId, expectedParentId: capture.parentId, folderId: capture.folderId,
      memberIdentityId: capture.memberProviderId, ...(overrides.fetchImpl ? { fetchImpl: overrides.fetchImpl } : {}) });
    const session = await createBusinessUploadSession({ ownerToken: verified.accessToken, folderId: capture.folderId,
      captureId: capture.captureId, filename: capture.filename, ...(overrides.fetchImpl ? { fetchImpl: overrides.fetchImpl } : {}) });
    const sessionVault = await createUploadSessionVault(env.BUSINESS_CREDENTIAL_KEY);
    const encryptedSession = await sessionVault.seal(organizationId, identity.uid, capture.recordId, session);
    const credential = await vault.seal(organizationId, org.ownerId,
      { refreshToken: verified.refreshToken, providerAccountId: verified.providerAccountId });
    return { session: encryptedSession, expiresAt: session.expiresAt,
      ownerCredential: { ...credential, providerAccountId: verified.providerAccountId, driveId: verified.driveId } };
  });
  const openCapture = overrides.openCapture ?? (async ({ organizationId, org, capture, storage, thumbnail }) => {
    const fetcher = overrides.fetchImpl ?? fetch;
    const boundedFetch = (url, options = {}) => fetcher(url, { ...options, signal: AbortSignal.timeout(30000) });
    const vault = await createCredentialVault(env.BUSINESS_CREDENTIAL_KEY);
    const saved = await vault.open(organizationId, org.ownerId, storage);
    if (saved.providerAccountId !== storage.providerAccountId) throw new Error('provider-identity-mismatch');
    const exchange = microsoftBusinessCredential({ clientId: env.BUSINESS_MICROSOFT_CLIENT_ID, fetchImpl: boundedFetch });
    const verified = await exchange(saved.refreshToken);
    if (verified.providerAccountId !== storage.providerAccountId || verified.driveId !== storage.driveId) throw new Error('provider-identity-mismatch');
    await verifyOneDriveMemberFolder({ ownerToken: verified.accessToken, expectedOwnerId: verified.providerAccountId,
      expectedDriveId: verified.driveId, expectedParentId: capture.parentId, folderId: capture.folderId,
      memberIdentityId: capture.memberProviderId, requireMember: false, fetchImpl: boundedFetch });
    return openBusinessPhoto({ ownerToken: verified.accessToken, itemId: capture.remoteItemId, folderId: capture.folderId,
      driveId: capture.driveId, filename: capture.filename, thumbnail, fetchImpl: boundedFetch });
  });
  const processUploadChunk = overrides.processUploadChunk ?? (async ({ organizationId, identity, capture, offset, bytes }) => {
    const vault = await createUploadSessionVault(env.BUSINESS_CREDENTIAL_KEY);
    const session = await vault.open(organizationId, identity.uid, capture.recordId,
      { version: capture.sessionVersion, iv: capture.sessionIv, ciphertext: capture.sessionCiphertext });
    const fetcher = overrides.fetchImpl ?? fetch;
    const boundedFetch = (url, options = {}) => fetcher(url, { ...options, signal: AbortSignal.timeout(60000) });
    const providerOffset = await businessUploadOffset({ uploadUrl: session.uploadUrl, total: capture.byteCount, fetchImpl: boundedFetch });
    if (providerOffset === offset + bytes.length && providerOffset < capture.byteCount) return { state: 'pending', nextOffset: providerOffset };
    if (providerOffset !== offset) throw new Error('upload-result-uncertain');
    return sendBusinessUploadChunk({ uploadUrl: session.uploadUrl, bytes, offset, total: capture.byteCount,
      folderId: capture.folderId, driveId: capture.driveId, filename: capture.filename, fetchImpl: boundedFetch });
  });
  const verifyUpload = overrides.verifyUpload ?? (async ({ organizationId, org, capture, storage }) => {
    const vault = await createCredentialVault(env.BUSINESS_CREDENTIAL_KEY);
    const saved = await vault.open(organizationId, org.ownerId, storage);
    if (saved.providerAccountId !== storage.providerAccountId) throw new Error('provider-identity-mismatch');
    const fetcher = overrides.fetchImpl ?? fetch;
    const boundedFetch = (url, options = {}) => fetcher(url, { ...options, signal: AbortSignal.timeout(300000) });
    const exchange = microsoftBusinessCredential({ clientId: env.BUSINESS_MICROSOFT_CLIENT_ID, fetchImpl: boundedFetch });
    const verified = await exchange(saved.refreshToken);
    if (verified.providerAccountId !== storage.providerAccountId || verified.driveId !== storage.driveId) throw new Error('provider-identity-mismatch');
    await verifyOneDriveMemberFolder({ ownerToken: verified.accessToken, expectedOwnerId: verified.providerAccountId,
      expectedDriveId: verified.driveId, expectedParentId: capture.parentId, folderId: capture.folderId,
      memberIdentityId: capture.memberProviderId, fetchImpl: boundedFetch });
    await verifyBusinessUploadedItem({ ownerToken: verified.accessToken, driveId: capture.driveId, folderId: capture.folderId,
      itemId: capture.remoteItemId, filename: capture.filename, expectedSize: capture.byteCount, expectedSha256: capture.sha256, fetchImpl: boundedFetch });
    const credential = await vault.seal(organizationId, org.ownerId,
      { refreshToken: verified.refreshToken, providerAccountId: verified.providerAccountId });
    return { verified: true, ownerCredential: { ...credential, providerAccountId: verified.providerAccountId, driveId: verified.driveId } };
  });
  const reconcileUpload = overrides.reconcileUpload ?? (async ({ organizationId, identity, org, capture, storage }) => {
    const vault = await createCredentialVault(env.BUSINESS_CREDENTIAL_KEY);
    const saved = await vault.open(organizationId, org.ownerId, storage);
    if (saved.providerAccountId !== storage.providerAccountId) throw new Error('provider-identity-mismatch');
    const fetcher = overrides.fetchImpl ?? fetch;
    const boundedFetch = (url, options = {}) => fetcher(url, { ...options, signal: AbortSignal.timeout(300000) });
    const exchange = microsoftBusinessCredential({ clientId: env.BUSINESS_MICROSOFT_CLIENT_ID, fetchImpl: boundedFetch });
    const verified = await exchange(saved.refreshToken);
    if (verified.providerAccountId !== storage.providerAccountId || verified.driveId !== storage.driveId) throw new Error('provider-identity-mismatch');
    await verifyOneDriveMemberFolder({ ownerToken: verified.accessToken, expectedOwnerId: verified.providerAccountId,
      expectedDriveId: verified.driveId, expectedParentId: capture.parentId, folderId: capture.folderId,
      memberIdentityId: capture.memberProviderId, fetchImpl: boundedFetch });
    const found = await findVerifiedBusinessUpload({ ownerToken: verified.accessToken, driveId: capture.driveId, folderId: capture.folderId,
      captureId: capture.captureId, filename: capture.filename, expectedSize: capture.byteCount, expectedSha256: capture.sha256, fetchImpl: boundedFetch });
    const credential = await vault.seal(organizationId, org.ownerId,
      { refreshToken: verified.refreshToken, providerAccountId: verified.providerAccountId });
    const ownerCredential = { ...credential, providerAccountId: verified.providerAccountId, driveId: verified.driveId };
    if (found?.verified) return { state: 'verified', itemId: found.itemId, ownerCredential };
    if (Date.now() >= capture.sessionExpiresAt + 120000) return { state: 'restart', ownerCredential };
    if (Date.now() >= capture.sessionExpiresAt) throw new Error('upload-result-uncertain');
    const sessionVault = await createUploadSessionVault(env.BUSINESS_CREDENTIAL_KEY);
    const session = await sessionVault.open(organizationId, identity.uid, capture.recordId,
      { version: capture.sessionVersion, iv: capture.sessionIv, ciphertext: capture.sessionCiphertext });
    const nextOffset = await businessUploadOffset({ uploadUrl: session.uploadUrl, total: capture.byteCount, fetchImpl: boundedFetch });
    return { state: 'uploading', nextOffset, ownerCredential };
  });
  const api = createBusinessApp({ projectId, authenticate, serverAccessToken, preAuthLimit, rateLimit,
    prepareOneDrive, prepareGoogleDrive, prepareGoogleOwnerFolder, prepareOwnerFolder, prepareMemberFolder, grantMemberFolder, openCapture,
    verifyMicrosoftMember: overrides.verifyMicrosoftMember ?? (token => verifiedMicrosoftMember(token, { fetchImpl: overrides.fetchImpl ?? fetch })),
    verifyGoogleDriveMember: overrides.verifyGoogleDriveMember ?? (token => verifiedGoogleDriveMember(token, { fetchImpl: overrides.fetchImpl ?? fetch })),
    prepareGoogleMail, prepareMicrosoftMail, prepareMailDelivery, revokeMemberStorage, prepareUpload, processUploadChunk, verifyUpload, reconcileUpload,
    canCreateOrganization: async identity => identity.emailVerified === true &&
      typeof identity.email === 'string' && identity.email.trim().toLowerCase() === ownerEmail,
    ...(overrides.fetchImpl ? { fetchImpl: overrides.fetchImpl } : {}),
    ...(overrides.emulatorOrigin ? { emulatorOrigin: overrides.emulatorOrigin } : {}),
  });
  return async request => {
    if (new URL(request.url).pathname === '/convite') {
      try { if (!await preAuthLimit(request)) return new Response('Indisponível.', { status: 429 }); }
      catch { return new Response('Indisponível.', { status: 503 }); }
      return invitationLanding(request);
    }
    return api(request);
  };
}

const workers = new WeakMap();
export default {
  async fetch(request, env) {
    try {
      let handler = workers.get(env);
      if (!handler) { handler = createBusinessWorker(env); workers.set(env, handler); }
      return await handler(request);
    } catch {
      return new Response('{"error":"unavailable"}', { status: 503,
        headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });
    }
  },
};
