import { describe, expect, it } from 'vitest';
import { createPostHandler } from '../src/handlers/createPost.js';
import { empathyHandler } from '../src/handlers/empathy.js';
import { feedHandler } from '../src/handlers/feed.js';
import type { Event } from '../src/handlers/http.js';
import type { FeedPost } from '../src/services/ports.js';
import { humanSession, MemoryRepo } from './helpers.js';

const event = (over: Partial<Event> & { sub?: string } = {}): Event =>
  ({
    requestContext: { authorizer: { jwt: { claims: { sub: over.sub ?? 'u1' }, scopes: [] } } },
    queryStringParameters: {},
    pathParameters: {},
    isBase64Encoded: false,
    ...over,
  }) as unknown as Event;

const parse = (r: unknown) => {
  const res = r as { statusCode: number; body: string };
  return { status: res.statusCode, body: JSON.parse(res.body) };
};

const TEXT = 'I keep thinking about the quiet morning walks I took last spring, and how slow they felt.';

describe('POST /posts', () => {
  const deps = () => ({
    repo: new MemoryRepo(),
    filter: { moderate: async () => ({ allowed: true as const }) },
    embedder: { embed: async () => [0.1] },
  });

  it('returns 201 with the extras', async () => {
    const r = parse(
      await createPostHandler(deps())(
        event({ body: JSON.stringify({ text: TEXT, session: humanSession(TEXT), localDate: '2026-11-25' }) }),
      ),
    );
    expect(r.status).toBe(201);
    expect(r.body.similar).toEqual({ people: 0, show: false });
    expect(r.body.firstPhrases).toEqual(['I keep thinking', 'keep thinking about', 'thinking about the']);
  });

  it('returns 400 for a bad body and 422 for pasted text', async () => {
    expect(parse(await createPostHandler(deps())(event({ body: 'nope' }))).status).toBe(400);
    const pasted = { text: TEXT, session: { events: [{ t: 0, i: TEXT.length, d: 0, s: 'keyboard' }] }, localDate: '2026-11-25' };
    const r = parse(await createPostHandler(deps())(event({ body: JSON.stringify(pasted) })));
    expect(r).toMatchObject({ status: 422, body: { error: 'not_human' } });
  });
});

describe('GET /feed', () => {
  const post = (id: string, lang: string): FeedPost => ({
    id, authorId: 'a', authorHandle: 'a', authorName: 'A', photoKey: null, body: `body ${id}`, lang,
    typingMs: 1000, empathyCount: 0, empathizedByMe: false, createdAt: '2026-11-25T00:00:00Z', editedAt: null,
  });

  it('translates other-language posts once and caches them', async () => {
    const repo = new MemoryRepo();
    repo.feedPosts = [post('p1', 'en'), post('p2', 'ko')];
    let calls = 0;
    const translator = { translate: async (t: string) => (calls++, `번역: ${t}`) };
    const run = async () => parse(await feedHandler({ repo, translator })(event({ queryStringParameters: { lang: 'ko' } })));
    const r = await run();
    expect(r.body.items[0].translation).toEqual({ lang: 'ko', body: '번역: body p1' });
    expect(r.body.items[1].translation).toBeNull();
    await run();
    expect(calls).toBe(1);
  });

  it('shows the original when translation fails', async () => {
    const repo = new MemoryRepo();
    repo.feedPosts = [post('p1', 'en')];
    const translator = { translate: async () => { throw new Error('down'); } };
    const r = parse(await feedHandler({ repo, translator })(event({ queryStringParameters: { lang: 'ko' } })));
    expect(r.body.items[0].translation).toBeNull();
  });
});

describe('POST /posts/{id}/empathy', () => {
  it('toggles, and refuses own or missing posts', async () => {
    const repo = new MemoryRepo();
    const id = await repo.insertPost({
      authorId: 'author', body: 'x', lang: 'en', typingMs: 1, localDate: '2026-11-25',
      status: 'published', session: { events: [], rejectedPastes: 0, activeMs: 0 }, issues: [],
    });
    const h = empathyHandler(repo);
    expect(parse(await h(event({ pathParameters: { id } }))).body).toEqual({ empathized: true, count: 1 });
    expect(parse(await h(event({ pathParameters: { id } }))).body).toEqual({ empathized: false, count: 0 });
    expect(parse(await h(event({ pathParameters: { id }, sub: 'author' }))).status).toBe(404);
    expect(parse(await h(event({ pathParameters: { id: 'bad' } }))).status).toBe(400);
  });
});
