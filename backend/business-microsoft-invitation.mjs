/** Send only after the caller has verified the mailbox belongs to the organization. */
export function microsoftInvitationSender({ invitationOrigin, fetchImpl = fetch }) {
  let origin;
  try { origin = new URL(invitationOrigin); } catch { throw new Error('invalid-invitation-origin'); }
  if (origin.protocol !== 'https:' || !origin.hostname || origin.username || origin.password || origin.port ||
      origin.pathname !== '/' || origin.search || origin.hash) throw new Error('invalid-invitation-origin');
  const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
  const email = value => typeof value === 'string' && value.length <= 254 &&
    /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(value) && !/[\r\n]/.test(value);
  return async ({ accessToken, expectedAccountId, recipientEmail, organizationName, organizationId, invitationId }) => {
    if (typeof accessToken !== 'string' || !accessToken || accessToken.length > 16384 ||
        typeof expectedAccountId !== 'string' || !expectedAccountId || expectedAccountId.length > 256 ||
        !email(recipientEmail) || typeof organizationName !== 'string' || !organizationName.trim() ||
        organizationName.length > 160 || /[\x00-\x1f\x7f]/.test(organizationName) ||
        !uuid(organizationId) || !uuid(invitationId)) throw new Error('invalid-mail-request');
    const headers = { authorization: `Bearer ${accessToken}` };
    const profile = await fetchImpl('https://graph.microsoft.com/v1.0/me?$select=id', { headers, redirect: 'manual' });
    if (profile.status !== 200) throw new Error('mail-unavailable');
    const account = await profile.json();
    if (account.id !== expectedAccountId) throw new Error('mailbox-mismatch');
    const link = new URL('/convite', origin);
    link.searchParams.set('organization', organizationId.toLowerCase());
    link.searchParams.set('invitation', invitationId.toLowerCase());
    const content = `${organizationName.trim()} convidou você para uma organização no Photomark.\n\nAbra o convite e entre com o e-mail que o recebeu:\n${link.href}\n\nSe não esperava este convite, ignore esta mensagem.`;
    const response = await fetchImpl('https://graph.microsoft.com/v1.0/me/sendMail', {
      method: 'POST', redirect: 'manual', headers: { ...headers, 'content-type': 'application/json' },
      body: JSON.stringify({ message: { subject: 'Convite para o Photomark', body: { contentType: 'Text', content },
        toRecipients: [{ emailAddress: { address: recipientEmail } }] } })
    });
    // Graph 202 means accepted for processing, not delivered to the recipient.
    if (response.status !== 202) throw new Error('mail-delivery-unconfirmed');
    return { accepted: true };
  };
}
