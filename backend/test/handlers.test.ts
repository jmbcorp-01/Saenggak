import { describe, expect, it } from 'vitest';
import { apiHandler } from '../src/handlers/api.js';
import type { Event } from '../src/handlers/http.js';
import { writeHandler } from '../src/handlers/write.js';
import type { FeedPost } from '../src/services/ports.js';
import { humanSession, MemoryRepo } from './helpers.js';

const U1 = '11111111-1111-4111-8111-111111111111';
const U2 = '22222222-2222-4222-8222-222222222222';

const event = (routeKey: string, over: Partial<Event> & { sub?: string } = {}): Event =>
  ({
    routeKey,
    requestContext: { authorizer: { jwt: { claims: { sub: over.sub ?? U1 }, scopes: [] } } },
    queryStringParameters: {},
    pathParameters: {},
    isBase64Encoded: false,
    ...over,
  }) as unknown as Event;

const parse = (r: unknown) => {
  const res = r as { statusCode: number; body?: string };
  return { status: res.statusCode, body: res.body ? JSON.parse(res.body) : null };
};

const TEXT = 'I keep thinking about the quiet morning walks I took last spring, and how slow they felt.';
const EDITED = 'Some evenings the city sounds like the sea, and I let myself believe it for a while.';
const post = (text: string) => JSON.stringify({ text, session: humanSession(text), localDate: '2026-11-25' });

function setup() {
  const repo = new MemoryRepo();
  const write = writeHandler({
    repo,
    filter: { moderate: async (t: string) => (t.includes('BAD') ? { allowed: false, reason: 'spam' } : { allowed: true }) },
    embedder: { embed: async () => [0.1] },
  });
  const api = apiHandler({ repo, translator: { translate: async (t: string) => `번역: ${t}` } });
  return { repo, write, api };
}

describe('POST /posts', () => {
  it('returns 201 with the extras', async () => {
    const { write } = setup();
    const r = parse(await write(event('POST /posts', { body: post(TEXT) })));
    expect(r.status).toBe(201);
    expect(r.body.similar).toEqual({ people: 0, show: false });
    expect(r.body.firstPhrases).toEqual(['I keep thinking', 'keep thinking about', 'thinking about the']);
  });

  it('returns 400 for a bad body and 422 for pasted text', async () => {
    const { write } = setup();
    expect(parse(await write(event('POST /posts', { body: 'nope' }))).status).toBe(400);
    const pasted = { text: TEXT, session: { events: [{ t: 0, i: TEXT.length, d: 0, s: 'keyboard' }] }, localDate: '2026-11-25' };
    const r = parse(await write(event('POST /posts', { body: JSON.stringify(pasted) })));
    expect(r).toMatchObject({ status: 422, body: { error: 'not_human' } });
  });
});

describe('PATCH /posts/{id}', () => {
  it('edits until the first 공감, then refuses', async () => {
    const { write, api } = setup();
    const id = parse(await write(event('POST /posts', { body: post(TEXT) }))).body.id;
    const patch = (sub = U1) => write(event('PATCH /posts/{id}', { sub, pathParameters: { id }, body: post(EDITED) }));

    const edited = parse(await patch());
    expect(edited.status).toBe(200);
    expect(edited.body.firstPhrases).toContain('evenings the city');

    expect(parse(await patch(U2)).status).toBe(404);

    await api(event('POST /posts/{id}/empathy', { sub: U2, pathParameters: { id } }));
    expect(parse(await patch())).toMatchObject({ status: 409, body: { error: 'locked' } });
  });

  it('frees the old phrases for others after an edit', async () => {
    const { write } = setup();
    const id = parse(await write(event('POST /posts', { body: post(TEXT) }))).body.id;
    await write(event('PATCH /posts/{id}', { pathParameters: { id }, body: post(EDITED) }));
    const other = parse(await write(event('POST /posts', { sub: U2, body: post(TEXT) })));
    expect(other.body.firstPhrases.length).toBeGreaterThan(0);
  });

  it('stores a blocked edit as a blocked post and keeps the old text', async () => {
    const { repo, write } = setup();
    const id = parse(await write(event('POST /posts', { body: post(TEXT) }))).body.id;
    const bad = `${EDITED} BAD`;
    const r = parse(await write(event('PATCH /posts/{id}', { pathParameters: { id }, body: post(bad) })));
    expect(r).toMatchObject({ status: 422, body: { error: 'blocked', reason: 'spam' } });
    expect(repo.posts.find((p) => p.id === id)?.body).toBe(TEXT.trim());
    expect(repo.posts.filter((p) => p.status === 'blocked')).toHaveLength(1);
  });
});

describe('DELETE /posts/{id}', () => {
  it('deletes only your own post', async () => {
    const { repo, write, api } = setup();
    const id = parse(await write(event('POST /posts', { body: post(TEXT) }))).body.id;
    expect(parse(await api(event('DELETE /posts/{id}', { sub: U2, pathParameters: { id } }))).status).toBe(404);
    expect(parse(await api(event('DELETE /posts/{id}', { pathParameters: { id } }))).status).toBe(204);
    expect(repo.posts).toHaveLength(0);
    expect(repo.firsts.size).toBe(0);
  });
});

describe('profile and follow', () => {
  const profile = (handle: string) => JSON.stringify({ handle, displayName: 'Name', bio: '', locale: 'en', timeZone: 'Asia/Seoul' });

  it('saves a profile and rejects a taken or invalid handle', async () => {
    const { api } = setup();
    const r = parse(await api(event('PUT /me', { body: profile('Yunseo_01') })));
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ handle: 'yunseo_01', writingDays: 0, daysToFollow: 10, isMe: true });
    expect(parse(await api(event('PUT /me', { sub: U2, body: profile('yunseo_01') }))).status).toBe(409);
    expect(parse(await api(event('PUT /me', { sub: U2, body: profile('a!') }))).status).toBe(400);
    expect(parse(await api(event('GET /me', { sub: U2 }))).status).toBe(404);
  });

  it('follows only when both people have permission', async () => {
    const { repo, api } = setup();
    await api(event('PUT /me', { body: profile('one') }));
    await api(event('PUT /me', { sub: U2, body: profile('two') }));
    const follow = () => api(event('PUT /users/{id}/follow', { pathParameters: { id: U2 } }));

    expect(parse(await follow())).toMatchObject({ status: 403, body: { error: 'not_allowed' } });
    repo.unlocked.set(U1, true);
    expect(parse(await follow()).status).toBe(403);
    repo.unlocked.set(U2, true);
    expect(parse(await follow())).toEqual({ status: 200, body: { following: true } });

    const seen = parse(await api(event('GET /users/{id}', { pathParameters: { id: U2 } })));
    expect(seen.body).toMatchObject({ followers: 1, followedByMe: true, isMe: false });

    await api(event('DELETE /users/{id}/follow', { pathParameters: { id: U2 } }));
    expect(repo.follows.size).toBe(0);
  });
});

describe('GET /feed', () => {
  const item = (id: string, lang: string): FeedPost => ({
    id, authorId: 'a', authorHandle: 'a', authorName: 'A', photoKey: null, body: `body ${id}`, lang,
    typingMs: 1000, empathyCount: 0, empathizedByMe: false, createdAt: '2026-11-25T00:00:00Z', editedAt: null,
  });

  it('translates other-language posts once and caches them', async () => {
    const { repo } = setup();
    repo.feedPosts = [item('p1', 'en'), item('p2', 'ko')];
    let calls = 0;
    const api = apiHandler({ repo, translator: { translate: async (t: string) => (calls++, `번역: ${t}`) } });
    const run = async () => parse(await api(event('GET /feed', { queryStringParameters: { lang: 'ko' } })));
    const r = await run();
    expect(r.body.items[0].translation).toEqual({ lang: 'ko', body: '번역: body p1' });
    expect(r.body.items[1].translation).toBeNull();
    await run();
    expect(calls).toBe(1);
  });

  it('shows the original when translation fails', async () => {
    const { repo } = setup();
    repo.feedPosts = [item('p1', 'en')];
    const api = apiHandler({ repo, translator: { translate: async () => { throw new Error('down'); } } });
    const r = parse(await api(event('GET /feed', { queryStringParameters: { lang: 'ko' } })));
    expect(r.body.items[0].translation).toBeNull();
  });

  it('rejects a bad author filter', async () => {
    const { api } = setup();
    expect(parse(await api(event('GET /feed', { queryStringParameters: { author: 'x' } }))).status).toBe(400);
  });
});

describe('POST /posts/{id}/empathy', () => {
  it('toggles, and refuses own or missing posts', async () => {
    const { write, api } = setup();
    const id = parse(await write(event('POST /posts', { sub: U2, body: post(TEXT) }))).body.id;
    const toggle = (sub = U1, pid = id) => api(event('POST /posts/{id}/empathy', { sub, pathParameters: { id: pid } }));
    expect(parse(await toggle()).body).toEqual({ empathized: true, count: 1 });
    expect(parse(await toggle()).body).toEqual({ empathized: false, count: 0 });
    expect(parse(await toggle(U2)).status).toBe(404);
    expect(parse(await toggle(U1, 'bad')).status).toBe(400);
  });
});
