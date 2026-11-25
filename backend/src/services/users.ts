import { AdminDeleteUserCommand, CognitoIdentityProviderClient } from '@aws-sdk/client-cognito-identity-provider';
import type { UserDirectory } from './ports.js';

/** Cognito user pool accounts. The pool signs people in by email, so the username is the sub. */
export class CognitoUserDirectory implements UserDirectory {
  constructor(
    private readonly userPoolId = process.env.USER_POOL_ID!,
    private readonly client = new CognitoIdentityProviderClient({}),
  ) {}

  async deleteUser(userId: string): Promise<void> {
    try {
      await this.client.send(new AdminDeleteUserCommand({ UserPoolId: this.userPoolId, Username: userId }));
    } catch (e) {
      if ((e as { name?: string }).name !== 'UserNotFoundException') throw e;
    }
  }
}
