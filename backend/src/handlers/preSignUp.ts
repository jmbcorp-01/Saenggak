import type { PreSignUpTriggerEvent } from 'aws-lambda';

/**
 * Throwaway mail services that bots use to make accounts in bulk. Sign-ups
 * from these are refused before Cognito sends a code.
 */
export const DISPOSABLE_DOMAINS = new Set([
  '10minutemail.com', '20minutemail.com', 'anonaddy.me', 'burnermail.io', 'byom.de', 'dispostable.com',
  'dropmail.me', 'emailondeck.com', 'fakeinbox.com', 'getairmail.com', 'getnada.com', 'guerrillamail.com',
  'guerrillamail.net', 'guerrillamailblock.com', 'harakirimail.com', 'inboxkitten.com', 'maildrop.cc',
  'mailinator.com', 'mailnesia.com', 'mailpoof.com', 'mintemail.com', 'mohmal.com', 'moakt.com',
  'mytemp.email', 'nada.email', 'sharklasers.com', 'spamgourmet.com', 'temp-mail.io', 'temp-mail.org',
  'tempail.com', 'tempmail.dev', 'tempmail.plus', 'tempmailo.com', 'tempr.email', 'throwawaymail.com',
  'trashmail.com', 'yopmail.com', 'yopmail.net',
]);

export function isDisposable(email: string): boolean {
  const domain = email.trim().toLowerCase().split('@').at(-1) ?? '';
  return DISPOSABLE_DOMAINS.has(domain);
}

export async function handler(event: PreSignUpTriggerEvent): Promise<PreSignUpTriggerEvent> {
  const email = event.request.userAttributes.email ?? '';
  // Cognito shows the message to the app as a sign-up error.
  if (isDisposable(email)) throw new Error('disposable_email');
  return event;
}
