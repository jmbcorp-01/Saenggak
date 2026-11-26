import { randomBytes } from 'node:crypto';
import {
  AdminCreateUserCommand,
  AdminLinkProviderForUserCommand,
  AdminSetUserPasswordCommand,
  CognitoIdentityProviderClient,
  ListUsersCommand,
} from '@aws-sdk/client-cognito-identity-provider';
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

/** The few Cognito calls that joining a Google or Apple sign-in needs. */
export interface Accounts {
  /** The username of the email-and-password account with this address, if any. */
  findByEmail(userPoolId: string, email: string): Promise<string | undefined>;
  /** Makes an email account for this address (no mail is sent) and returns its username. */
  create(userPoolId: string, email: string): Promise<string>;
  link(userPoolId: string, username: string, provider: string, providerUserId: string): Promise<void>;
}

export class CognitoAccounts implements Accounts {
  constructor(private readonly client = new CognitoIdentityProviderClient({})) {}

  async findByEmail(userPoolId: string, email: string) {
    const out = await this.client.send(
      new ListUsersCommand({ UserPoolId: userPoolId, Filter: `email = "${email.replace(/"/g, '')}"`, Limit: 10 }),
    );
    return out.Users?.find((u) => u.UserStatus !== 'EXTERNAL_PROVIDER')?.Username;
  }

  async create(userPoolId: string, email: string) {
    const out = await this.client.send(
      new AdminCreateUserCommand({
        UserPoolId: userPoolId,
        Username: email,
        MessageAction: 'SUPPRESS',
        UserAttributes: [
          { Name: 'email', Value: email },
          { Name: 'email_verified', Value: 'true' },
        ],
      }),
    );
    const username = out.User?.Username ?? email;
    // A long random password nobody knows, so the account is ready to use.
    // The person can set their own later with 비밀번호 찾기.
    await this.client.send(
      new AdminSetUserPasswordCommand({
        UserPoolId: userPoolId,
        Username: username,
        Password: `${randomBytes(24).toString('base64url')}aA1`,
        Permanent: true,
      }),
    );
    return username;
  }

  async link(userPoolId: string, username: string, provider: string, providerUserId: string) {
    await this.client.send(
      new AdminLinkProviderForUserCommand({
        UserPoolId: userPoolId,
        DestinationUser: { ProviderName: 'Cognito', ProviderAttributeValue: username },
        SourceUser: { ProviderName: provider, ProviderAttributeName: 'Cognito_Subject', ProviderAttributeValue: providerUserId },
      }),
    );
  }
}

/** Cognito names a Google or Apple person `Google_123` or `SignInWithApple_001.abc`. */
export function splitProviderUser(userName: string): { provider: string; id: string } {
  const at = userName.indexOf('_');
  if (at < 1) throw new Error('bad_provider_user');
  const prefix = userName.slice(0, at);
  // The prefix is lower case in the username but the provider's name is not.
  const provider = prefix.toLowerCase() === 'google' ? 'Google' : prefix.toLowerCase() === 'signinwithapple' ? 'SignInWithApple' : prefix;
  return { provider, id: userName.slice(at + 1) };
}

export function makeHandler(accounts: Accounts = new CognitoAccounts()) {
  return async (event: PreSignUpTriggerEvent): Promise<PreSignUpTriggerEvent> => {
    const email = (event.request.userAttributes.email ?? '').trim().toLowerCase();
    if (event.triggerSource === 'PreSignUp_ExternalProvider') {
      // Everyone has one account, the email one: a first Google or Apple
      // sign-in joins it (making it if needed), so the same person keeps the
      // same profile whichever way they sign in.
      if (!email) throw new Error('email_required');
      const { provider, id } = splitProviderUser(event.userName);
      const username = (await accounts.findByEmail(event.userPoolId, email)) ?? (await accounts.create(event.userPoolId, email));
      await accounts.link(event.userPoolId, username, provider, id);
      return event;
    }
    // Cognito shows the message to the app as a sign-up error.
    if (event.triggerSource !== 'PreSignUp_AdminCreateUser' && isDisposable(email)) throw new Error('disposable_email');
    return event;
  };
}

export const handler = makeHandler();
