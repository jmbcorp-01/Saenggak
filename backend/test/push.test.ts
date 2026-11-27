import { generateKeyPairSync, createVerify } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import type { Event } from '../src/handlers/http.js';
import { pushHandler } from '../src/handlers/push.js';
import { compose, type PushBatch } from '../src/push/messages.js';
import { sendPushes, type PushClient, type PushStore, type PushToken } from '../src/push/sender.js';
import { FcmClient, fcmMessage, linkFor, serviceJwt } from '../src/services/fcm.js';
import type { PushRepository, PushSettings } from '../src/services/pushRepository.js';

const ME = '11111111-1111-4111-8111-111111111111';
const POST = '33333333-3333-4333-8333-333333333333';
const TOKEN = 'fcm-token-abcdefghijklmnopqrstuvwxyz:APA91b_example-123';

const event = (routeKey: string, body?: unknown): Event =>
  ({
    routeKey,
    requestContext: { authorizer: { jwt: { claims: { sub: ME }, scopes: [] } } },
    headers: {},
    isBase64Encoded: false,
    body: body === undefined ? undefined : JSON.stringify(body),
  }) as unknown as Event;
const parse = (r: unknown) => {
  const res = r as { statusCode: number; body?: string };
  return { status: res.statusCode, body: res.body ? JSON.parse(res.body) : undefined };
};

const batch = (over: Partial<PushBatch> = {}): PushBatch => ({
  userId: ME,
  lang: 'ko',
  kind: 'empathy',
  count: 1,
  actorId: 'actor',
  actorName: '하루',
  postId: POST,
  excerpt: '오늘은 비가 와서 창문을 오래 보았다',
  ...over,
});

describe('push messages', () => {
  it('names the latest person and counts the rest', () => {
    expect(compose(batch()).title).toBe('하루님이 공감했어요');
    expect(compose(batch({ count: 4 })).title).toBe('하루님 외 3명이 공감했어요');
    expect(compose(batch()).body).toBe('오늘은 비가 와서 창문을 오래 보았다');
    expect(compose(batch()).data).toEqual({ kind: 'empathy', postId: POST });
    expect(compose(batch({ lang: 'en', count: 2 })).title).toBe('하루 and 1 other related');
  });

  it('opens the follower for one follow, and the list for many', () => {
    expect(compose(batch({ kind: 'follow', postId: null })).data).toEqual({ kind: 'follow', userId: 'actor' });
    expect(compose(batch({ kind: 'follow', postId: null, count: 3 })).data).toEqual({ kind: 'follow' });
    expect(compose(batch({ kind: 'follow', count: 3 })).title).toBe('하루님 외 2명이 팔로우했어요');
  });

  it('shows one new post itself, and several as a count', () => {
    const one = compose(batch({ kind: 'post' }));
    expect(one.title).toBe('하루님의 새 생각');
    expect(one.data).toEqual({ kind: 'post', postId: POST });
    const many = compose(batch({ kind: 'post', count: 3 }));
    expect(many.title).toBe('새 생각 3개');
    expect(many.data).toEqual({ kind: 'post' });
  });

  it('keeps long words and names short', () => {
    const m = compose(batch({ excerpt: '가'.repeat(100), actorName: '나'.repeat(40) }));
    expect([...m.body]).toHaveLength(60);
    expect(m.body.endsWith('…')).toBe(true);
    expect(m.title.startsWith('나'.repeat(19) + '…')).toBe(true);
  });
});

class FakeStore implements PushStore {
  removed: string[] = [];
  constructor(
    private readonly batches: PushBatch[],
    private readonly devices: Record<string, PushToken[]>,
  ) {}
  async takeBatches() {
    return this.batches;
  }
  async tokens(ids: string[]) {
    return new Map(ids.map((id) => [id, this.devices[id] ?? []]));
  }
  async removeTokens(t: string[]) {
    this.removed.push(...t);
  }
}

describe('sendPushes', () => {
  it('sends each batch to every device and forgets tokens that are gone', async () => {
    const store = new FakeStore([batch(), batch({ kind: 'follow', postId: null })], {
      [ME]: [
        { token: 'a', platform: 'ios' },
        { token: 'b', platform: 'android' },
      ],
    });
    const sent: string[] = [];
    const client: PushClient = {
      async send(t, m) {
        sent.push(`${t.token}:${m.data.kind}`);
        return t.token === 'b' ? 'gone' : 'sent';
      },
    };
    const report = await sendPushes(store, client);
    expect(sent.sort()).toEqual(['a:empathy', 'a:follow', 'b:empathy', 'b:follow']);
    expect(report).toEqual({ batches: 2, sent: 2, failed: 0, removed: 1 });
    expect(store.removed).toEqual(['b']);
  });

  it('counts a failure without stopping the rest', async () => {
    const store = new FakeStore([batch()], { [ME]: [{ token: 'a', platform: 'web' }, { token: 'c', platform: 'web' }] });
    const client: PushClient = {
      async send(t) {
        if (t.token === 'a') throw new Error('down');
        return 'sent';
      },
    };
    expect(await sendPushes(store, client)).toEqual({ batches: 1, sent: 1, failed: 1, removed: 0 });
  });

  it('still takes the batches without Firebase, so old events are not sent later', async () => {
    let taken = false;
    const store = new FakeStore([batch()], {});
    store.takeBatches = async () => ((taken = true), [batch()]);
    expect(await sendPushes(store, null)).toEqual({ batches: 1, sent: 0, failed: 0, removed: 0 });
    expect(taken).toBe(true);
  });
});

describe('Firebase Cloud Messaging', () => {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const sa = {
    project_id: 'saenggak-test',
    client_email: 'push@saenggak-test.iam.gserviceaccount.com',
    private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
  };

  it('signs the service account assertion with its key', () => {
    const jwt = serviceJwt(sa, 1_700_000_000_000);
    const [head, claims, sig] = jwt.split('.');
    const verify = createVerify('RSA-SHA256');
    verify.update(`${head}.${claims}`);
    expect(verify.verify(publicKey, Buffer.from(sig!, 'base64url'))).toBe(true);
    const c = JSON.parse(Buffer.from(claims!, 'base64url').toString());
    expect(c).toMatchObject({ iss: sa.client_email, aud: 'https://oauth2.googleapis.com/token', iat: 1_700_000_000 });
    expect(c.exp - c.iat).toBe(3600);
  });

  it('builds a message every platform understands', () => {
    const m = fcmMessage({ token: 't', platform: 'web' }, compose(batch()));
    expect(m.message.token).toBe('t');
    expect(m.message.notification.title).toBe('하루님이 공감했어요');
    expect(m.message.data).toEqual({ kind: 'empathy', postId: POST });
    expect(m.message.webpush.fcm_options.link).toBe(`/?post=${POST}`);
    expect(linkFor(compose(batch({ kind: 'follow', count: 2 })))).toBe('/?tab=notifications');
  });

  it('signs in once, reuses the access token, and reports a token that is gone', async () => {
    const calls: string[] = [];
    const fetchFn = (async (url: string, init?: RequestInit) => {
      calls.push(String(url));
      if (String(url).includes('oauth2')) return new Response(JSON.stringify({ access_token: 'ya29', expires_in: 3600 }));
      expect((init?.headers as Record<string, string>).authorization).toBe('Bearer ya29');
      const body = JSON.parse(String(init?.body));
      if (body.message.token === 'dead') {
        return new Response(JSON.stringify({ error: { status: 'NOT_FOUND', details: [{ errorCode: 'UNREGISTERED' }] } }), {
          status: 404,
        });
      }
      return new Response('{}');
    }) as typeof fetch;
    const fcm = new FcmClient(sa, fetchFn);
    const m = compose(batch());
    expect(await fcm.send({ token: 'live', platform: 'ios' }, m)).toBe('sent');
    expect(await fcm.send({ token: 'dead', platform: 'ios' }, m)).toBe('gone');
    expect(calls.filter((c) => c.includes('oauth2'))).toHaveLength(1);
    expect(calls[1]).toBe('https://fcm.googleapis.com/v1/projects/saenggak-test/messages:send');
  });

  it('throws on other errors so they are logged', async () => {
    const fetchFn = (async (url: string) =>
      String(url).includes('oauth2')
        ? new Response(JSON.stringify({ access_token: 'x' }))
        : new Response('quota', { status: 429 })) as typeof fetch;
    await expect(new FcmClient(sa, fetchFn).send({ token: 't', platform: 'android' }, compose(batch()))).rejects.toThrow(
      'fcm 429',
    );
  });
});

class FakeRepo implements PushRepository {
  tokens = new Map<string, string>();
  settings: PushSettings = { empathy: true, follow: true, posts: true };
  profile = true;
  async saveToken(_u: string, t: string, p: string) {
    if (!this.profile) return false;
    this.tokens.set(t, p);
    return true;
  }
  async removeToken(_u: string, t: string) {
    this.tokens.delete(t);
  }
  async pushSettings() {
    return this.profile ? this.settings : null;
  }
  async setPushSettings(_u: string, s: PushSettings) {
    this.settings = s;
    return this.profile;
  }
}

describe('push routes', () => {
  it('registers and removes a device', async () => {
    const push = new FakeRepo();
    const h = pushHandler({ push });
    expect(parse(await h(event('PUT /me/push', { token: TOKEN, platform: 'ios' }))).status).toBe(204);
    expect(push.tokens.get(TOKEN)).toBe('ios');
    expect(parse(await h(event('POST /me/push/remove', { token: TOKEN }))).status).toBe(204);
    expect(push.tokens.size).toBe(0);
  });

  it('turns down a bad token or platform, and a person without a profile', async () => {
    const push = new FakeRepo();
    const h = pushHandler({ push });
    expect(parse(await h(event('PUT /me/push', { token: 'short', platform: 'ios' }))).status).toBe(400);
    expect(parse(await h(event('PUT /me/push', { token: TOKEN, platform: 'windows' }))).status).toBe(400);
    expect(parse(await h(event('PUT /me/push', { token: `${TOKEN} x`, platform: 'web' }))).status).toBe(400);
    push.profile = false;
    expect(parse(await h(event('PUT /me/push', { token: TOKEN, platform: 'web' }))).status).toBe(409);
  });

  it('reads and saves which kinds to send', async () => {
    const push = new FakeRepo();
    const h = pushHandler({ push });
    expect(parse(await h(event('GET /me/push-settings'))).body).toEqual({ empathy: true, follow: true, posts: true });
    const off = { empathy: false, follow: true, posts: false };
    expect(parse(await h(event('PUT /me/push-settings', off)))).toEqual({ status: 200, body: off });
    expect(push.settings).toEqual(off);
    expect(parse(await h(event('PUT /me/push-settings', { empathy: false }))).status).toBe(400);
  });
});

describe('web Firebase settings for the deploy', async () => {
  const { mkdtempSync, writeFileSync } = await import('node:fs');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');
  const { firebaseWebConfig } = await import('../infra/stack.js');
  const file = (c: Record<string, string>) => {
    const f = join(mkdtempSync(join(tmpdir(), 'fb-')), 'production.json');
    writeFileSync(f, JSON.stringify(c));
    return f;
  };

  it('is left out until every web key is filled in', () => {
    expect(firebaseWebConfig(file({ FIREBASE_PROJECT_ID: 'p' }))).toBeUndefined();
    expect(firebaseWebConfig('/nonexistent/production.json')).toBeUndefined();
    expect(
      firebaseWebConfig(
        file({
          FIREBASE_PROJECT_ID: 'saenggak',
          FIREBASE_SENDER_ID: '123',
          FIREBASE_WEB_API_KEY: 'AIza',
          FIREBASE_WEB_APP_ID: '1:123:web:abc',
          FIREBASE_VAPID_KEY: 'BKey',
        }),
      ),
    ).toEqual({ apiKey: 'AIza', appId: '1:123:web:abc', messagingSenderId: '123', projectId: 'saenggak', vapidKey: 'BKey' });
  });
});
