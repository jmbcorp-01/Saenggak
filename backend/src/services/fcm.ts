import { createSign } from 'node:crypto';
import { GetSecretValueCommand, SecretsManagerClient } from '@aws-sdk/client-secrets-manager';
import type { PushMessage } from '../push/messages.js';
import type { PushClient, PushToken } from '../push/sender.js';

/**
 * Firebase Cloud Messaging (HTTP v1), which delivers to Android, iOS (through
 * APNs) and web browsers alike. Signs in with a service account key kept in
 * Secrets Manager (FIREBASE_SECRET_ARN):
 *   { "project_id", "client_email", "private_key" }   (the JSON Firebase downloads)
 */
export interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

type Fetch = typeof fetch;
const b64url = (v: string | Buffer) => Buffer.from(v).toString('base64url');

/** A signed assertion for Google's token endpoint, valid one hour. */
export function serviceJwt(sa: ServiceAccount, now = Date.now()): string {
  const iat = Math.floor(now / 1000);
  const head = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64url(
    JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat,
      exp: iat + 3600,
    }),
  );
  const signer = createSign('RSA-SHA256');
  signer.update(`${head}.${claims}`);
  return `${head}.${claims}.${signer.sign(sa.private_key).toString('base64url')}`;
}

/** The FCM v1 message for one device. */
export function fcmMessage(token: PushToken, m: PushMessage) {
  const data: Record<string, string> = Object.fromEntries(
    Object.entries(m.data).filter(([, v]) => v !== undefined).map(([k, v]) => [k, String(v)]),
  );
  return {
    message: {
      token: token.token,
      notification: { title: m.title, body: m.body },
      data,
      android: { priority: 'HIGH', notification: { tag: m.data.kind } },
      apns: { payload: { aps: { sound: 'default', 'thread-id': m.data.kind } } },
      webpush: {
        notification: { icon: '/icons/Icon-192.png', tag: m.data.kind, renotify: true },
        fcm_options: { link: linkFor(m) },
      },
    },
  };
}

/** Where a tap opens the web app. */
export function linkFor(m: PushMessage): string {
  if (m.data.postId) return `/?post=${m.data.postId}`;
  return '/?tab=notifications';
}

export class FcmClient implements PushClient {
  private access?: { token: string; until: number };

  constructor(
    private readonly sa: ServiceAccount,
    private readonly fetchFn: Fetch = fetch,
    private readonly now = () => Date.now(),
  ) {}

  private async accessToken(): Promise<string> {
    if (this.access && this.access.until > this.now()) return this.access.token;
    const res = await this.fetchFn('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: serviceJwt(this.sa, this.now()),
      }),
    });
    const body = (await res.json()) as { access_token?: string; expires_in?: number };
    if (!res.ok || !body.access_token) throw new Error(`firebase sign-in failed: ${res.status}`);
    this.access = { token: body.access_token, until: this.now() + ((body.expires_in ?? 3600) - 300) * 1000 };
    return body.access_token;
  }

  async send(token: PushToken, m: PushMessage): Promise<'sent' | 'gone'> {
    const res = await this.fetchFn(`https://fcm.googleapis.com/v1/projects/${this.sa.project_id}/messages:send`, {
      method: 'POST',
      headers: { authorization: `Bearer ${await this.accessToken()}`, 'content-type': 'application/json' },
      body: JSON.stringify(fcmMessage(token, m)),
    });
    if (res.ok) return 'sent';
    const text = await res.text();
    // The app was removed, the token expired, or it belongs to another project.
    if (res.status === 404 || text.includes('UNREGISTERED') || (res.status === 400 && text.includes('registration token'))) {
      return 'gone';
    }
    throw new Error(`fcm ${res.status}: ${text.slice(0, 300)}`);
  }
}

/** The client, or null while the secret still holds its placeholder. */
export async function fcmFromSecret(
  secretId = process.env.FIREBASE_SECRET_ARN,
  client = new SecretsManagerClient({}),
): Promise<FcmClient | null> {
  if (!secretId) return null;
  try {
    const out = await client.send(new GetSecretValueCommand({ SecretId: secretId }));
    const sa = JSON.parse(out.SecretString ?? '{}') as Partial<ServiceAccount>;
    if (!sa.project_id || !sa.client_email || !sa.private_key?.includes('PRIVATE KEY')) return null;
    return new FcmClient(sa as ServiceAccount);
  } catch (e) {
    console.error('firebase secret unreadable', e);
    return null;
  }
}
