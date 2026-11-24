import { BusinessService } from './business-service.mjs';
import { createBusinessHandler } from './business-http.mjs';
import { firestoreTransactions } from './business-firestore.mjs';

/** Composition root. Dependencies must be created by trusted server configuration. */
export function createBusinessApp({ projectId, authenticate, serverAccessToken, preAuthLimit, canCreateOrganization,
  rateLimit, fetchImpl = fetch, newId = () => crypto.randomUUID(), clock = () => Date.now(), emulatorOrigin, prepareOneDrive, prepareGoogleMail }) {
  if (typeof authenticate !== 'function' || typeof serverAccessToken !== 'function' ||
      typeof preAuthLimit !== 'function' || typeof rateLimit !== 'function') throw new Error('missing-security-dependency');
  const transaction = firestoreTransactions({ projectId, accessToken: serverAccessToken, fetchImpl, emulatorOrigin });
  return createBusinessHandler({ authenticate, preAuthLimit, rateLimit,
    serviceForIdentity: identity => new BusinessService({ verifyToken: async () => identity, transaction, newId, clock, canCreateOrganization, prepareOneDrive, prepareGoogleMail }) });
}
