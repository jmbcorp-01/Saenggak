import { GetSecretValueCommand, PutSecretValueCommand, SecretsManagerClient } from '@aws-sdk/client-secrets-manager';
import type { Publisher } from './growthPorts.js';

/**
 * Saenggak's own Threads and Instagram accounts, through Meta's official
 * publishing APIs. The tokens live in one Secrets Manager secret as JSON:
 *   { "threadsUserId", "threadsToken", "instagramUserId", "instagramToken" }
 * A channel without both values is simply not used. Long-lived tokens last 60
 * days; the agent refreshes them each week and saves them back.
 */
export interface SocialTokens {
  threadsUserId?: string;
  threadsToken?: string;
  instagramUserId?: string;
  instagramToken?: string;
}

export const THREADS_API = 'https://graph.threads.net/v1.0';
export const INSTAGRAM_API = 'https://graph.instagram.com/v23.0';

type Fetch = typeof fetch;

async function call(fetchFn: Fetch, url: string, params: Record<string, string>, method: 'GET' | 'POST' = 'POST') {
  const body = new URLSearchParams(params);
  const res = await fetchFn(method === 'GET' ? `${url}?${body}` : url, {
    method,
    ...(method === 'POST' ? { body, headers: { 'content-type': 'application/x-www-form-urlencoded' } } : {}),
    signal: AbortSignal.timeout(20_000),
  });
  const json = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  if (!res.ok) {
    const err = json.error as { message?: string } | undefined;
    throw new Error(`${res.status} ${err?.message ?? 'request failed'}`);
  }
  return json;
}

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

export class ThreadsPublisher implements Publisher {
  channel = 'threads';
  constructor(
    private readonly userId: string,
    private readonly token: string,
    private readonly fetchFn: Fetch = fetch,
  ) {}

  async publish(post: { text: string; imageUrl: string | null }): Promise<string> {
    const container = await call(this.fetchFn, `${THREADS_API}/${this.userId}/threads`, {
      media_type: post.imageUrl ? 'IMAGE' : 'TEXT',
      text: post.text,
      ...(post.imageUrl ? { image_url: post.imageUrl } : {}),
      access_token: this.token,
    });
    // Meta asks for a short pause between making a container and publishing it.
    await wait(post.imageUrl ? 15_000 : 2_000);
    const done = await call(this.fetchFn, `${THREADS_API}/${this.userId}/threads_publish`, {
      creation_id: String(container.id),
      access_token: this.token,
    });
    return String(done.id);
  }
}

export class InstagramPublisher implements Publisher {
  channel = 'instagram';
  constructor(
    private readonly userId: string,
    private readonly token: string,
    private readonly fetchFn: Fetch = fetch,
  ) {}

  async publish(post: { text: string; imageUrl: string | null }): Promise<string> {
    if (!post.imageUrl) throw new Error('instagram needs an image');
    const container = await call(this.fetchFn, `${INSTAGRAM_API}/${this.userId}/media`, {
      image_url: post.imageUrl,
      caption: post.text,
      access_token: this.token,
    });
    // The image is fetched and processed first; publishing too early fails.
    for (let attempt = 0; ; attempt++) {
      try {
        const done = await call(this.fetchFn, `${INSTAGRAM_API}/${this.userId}/media_publish`, {
          creation_id: String(container.id),
          access_token: this.token,
        });
        return String(done.id);
      } catch (e) {
        if (attempt >= 3) throw e;
        await wait(5_000);
      }
    }
  }
}

export const usable = (v: string | undefined): v is string => typeof v === 'string' && v.length > 8 && !v.startsWith('REPLACE');

export function publishersFrom(tokens: SocialTokens, fetchFn: Fetch = fetch): Publisher[] {
  const list: Publisher[] = [];
  if (usable(tokens.threadsUserId) && usable(tokens.threadsToken)) {
    list.push(new ThreadsPublisher(tokens.threadsUserId, tokens.threadsToken, fetchFn));
  }
  if (usable(tokens.instagramUserId) && usable(tokens.instagramToken)) {
    list.push(new InstagramPublisher(tokens.instagramUserId, tokens.instagramToken, fetchFn));
  }
  return list;
}

/** Swaps each long-lived token for a fresh one; a token that fails to refresh is kept. */
export async function refreshTokens(tokens: SocialTokens, fetchFn: Fetch = fetch): Promise<SocialTokens> {
  const next = { ...tokens };
  if (usable(tokens.threadsToken)) {
    try {
      const r = await call(fetchFn, 'https://graph.threads.net/refresh_access_token', {
        grant_type: 'th_refresh_token',
        access_token: tokens.threadsToken,
      }, 'GET');
      if (typeof r.access_token === 'string') next.threadsToken = r.access_token;
    } catch (e) {
      console.error('threads token refresh failed', e);
    }
  }
  if (usable(tokens.instagramToken)) {
    try {
      const r = await call(fetchFn, 'https://graph.instagram.com/refresh_access_token', {
        grant_type: 'ig_refresh_token',
        access_token: tokens.instagramToken,
      }, 'GET');
      if (typeof r.access_token === 'string') next.instagramToken = r.access_token;
    } catch (e) {
      console.error('instagram token refresh failed', e);
    }
  }
  return next;
}

export class TokenSecret {
  constructor(
    private readonly secretId = process.env.SOCIAL_TOKENS_SECRET_ARN,
    private readonly client = new SecretsManagerClient({}),
  ) {}

  async read(): Promise<SocialTokens> {
    if (!this.secretId) return {};
    try {
      const out = await this.client.send(new GetSecretValueCommand({ SecretId: this.secretId }));
      const parsed: unknown = JSON.parse(out.SecretString ?? '{}');
      return parsed && typeof parsed === 'object' ? (parsed as SocialTokens) : {};
    } catch (e) {
      console.error('social tokens unreadable', e);
      return {};
    }
  }

  async write(tokens: SocialTokens): Promise<void> {
    if (!this.secretId) return;
    await this.client.send(new PutSecretValueCommand({ SecretId: this.secretId, SecretString: JSON.stringify(tokens) }));
  }
}
