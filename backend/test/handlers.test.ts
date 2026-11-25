import { describe, expect, it } from 'vitest';
import { apiHandler } from '../src/handlers/api.js';
import type { Event } from '../src/handlers/http.js';
import { writeHandler } from '../src/handlers/write.js';
import type { FeedPost } from '../src/services/ports.js';
import { editSession, humanSession, MemoryRepo } from './helpers.js';

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
const post = (text: string) => JSON.stringify({ text, session: humanSession(text) });
const edit = (from: string, to: string) => JSON.stringify({ text: to, session: editSession(from, to) });

/** A JPEG header followed by a marker the fake checker reads. */
const jpeg = (marker: string) => Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.from(marker)]).toString('base64');

/** Photo and account stores for tests that do not touch them. */
const noStores = {
  photoStore: { put: async () => {}, remove: async () => {} },
  users: { deleteUser: async () => {} },
};

function setup() {
  const repo = new MemoryRepo();
  const stored = new Set<string>();
  const write = writeHandler({
    photoChecker: {
      check: async (b: Uint8Array) => {
        const marker = Buffer.from(b.subarray(4)).toString();
        return marker === 'face' ? { ok: true } : { ok: false, problem: marker as 'no_face' };
      },
    },
    photoStore: {
      put: async (key: string) => void stored.add(key),
      remove: async (key: string) => void stored.delete(key),
    },
    repo,
    filter: {
      moderate: async (t: string) => (t.includes('BAD') ? { allowed: false, reason: 'spam' } : { allowed: true }),
      moderateProfile: async ({ bio }: { bio: string }) => !bio.includes('BAD'),
    },
    embedder: { embed: async () => [0.1] },
  });
  const deletedUsers: string[] = [];
  const api = apiHandler({
    repo,
    translator: { translate: async (t: string) => `번역: ${t}` },
    photoStore: { put: async () => {}, remove: async (key: string) => void stored.delete(key) },
    users: { deleteUser: async (id: string) => void deletedUsers.push(id) },
  });
  return { repo, write, api, stored, deletedUsers };
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
    const pasted = { text: TEXT, session: { events: [{ t: 0, i: TEXT.length, d: 0, s: 'keyboard' }] } };
    const r = parse(await write(event('POST /posts', { body: JSON.stringify(pasted) })));
    expect(r).toMatchObject({ status: 422, body: { error: 'not_human' } });
  });
});

describe('errors', () => {
  it('maps limits and outages to plain answers', async () => {
    const { repo, write } = setup();
    repo.writes.set(U1, 1000);
    expect(parse(await write(event('POST /posts', { body: post(TEXT) })))).toEqual({
      status: 429,
      body: { error: 'rate_limited' },
    });
    repo.requireProfile = true;
    expect(parse(await write(event('POST /posts', { body: post(TEXT) }))).body).toEqual({ error: 'profile_required' });
  });

  it('answers 500 without details when something throws', async () => {
    const repo = new MemoryRepo();
    repo.feed = async () => {
      throw new Error('db password is hunter2');
    };
    const api = apiHandler({ repo, translator: { translate: async (t: string) => t }, ...noStores });
    const quiet = console.error;
    console.error = () => {};
    try {
      expect(parse(await api(event('GET /feed')))).toEqual({ status: 500, body: { error: 'internal' } });
    } finally {
      console.error = quiet;
    }
  });
});

describe('PATCH /posts/{id}', () => {
  it('edits until the first 공감, then refuses', async () => {
    const { write, api } = setup();
    const id = parse(await write(event('POST /posts', { body: post(TEXT) }))).body.id;
    const patch = (sub = U1) => write(event('PATCH /posts/{id}', { sub, pathParameters: { id }, body: edit(TEXT, EDITED) }));

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
    await write(event('PATCH /posts/{id}', { pathParameters: { id }, body: edit(TEXT, EDITED) }));
    const other = parse(await write(event('POST /posts', { sub: U2, body: post(TEXT) })));
    expect(other.body.firstPhrases.length).toBeGreaterThan(0);
  });

  it('stores a blocked edit as a blocked post and keeps the old text', async () => {
    const { repo, write } = setup();
    const id = parse(await write(event('POST /posts', { body: post(TEXT) }))).body.id;
    const bad = `${EDITED} BAD`;
    const r = parse(await write(event('PATCH /posts/{id}', { pathParameters: { id }, body: edit(TEXT, bad) })));
    expect(r).toMatchObject({ status: 422, body: { error: 'blocked', reason: 'spam' } });
    expect(repo.posts.find((p) => p.id === id)?.body).toBe(TEXT.trim());
    expect(repo.posts.filter((p) => p.status === 'blocked')).toHaveLength(1);
  });
});

describe('editing in place', () => {
  it('checks only the change, and adds the edit time to the typing time', async () => {
    const { repo, write } = setup();
    const id = parse(await write(event('POST /posts', { body: post(TEXT) }))).body.id;
    const before = repo.posts[0]!.typingMs;
    const changed = `${TEXT} Still.`;
    const typed = humanSession(' Still.');
    const r = parse(await write(event('PATCH /posts/{id}', {
      pathParameters: { id },
      body: JSON.stringify({ text: changed, session: typed }),
    })));
    expect(r.status).toBe(200);
    expect(repo.posts[0]!.typingMs).toBeGreaterThan(before);

    // A session that does not match the change is refused.
    const wrong = parse(await write(event('PATCH /posts/{id}', { pathParameters: { id }, body: post(EDITED) })));
    expect(wrong).toMatchObject({ status: 422, body: { error: 'not_human', issues: ['text_mismatch'] } });
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
    const { api, write } = setup();
    const r = parse(await write(event('PUT /me', { body: profile('Yunseo_01') })));
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ handle: 'yunseo_01', writingDays: 0, daysToFollow: 10, isMe: true });
    expect(parse(await write(event('PUT /me', { sub: U2, body: profile('yunseo_01') }))).status).toBe(409);
    expect(parse(await write(event('PUT /me', { sub: U2, body: profile('a!') }))).status).toBe(400);
    expect(parse(await api(event('GET /me', { sub: U2 }))).status).toBe(404);
  });

  it('blocks an abusive bio', async () => {
    const { write } = setup();
    const body = JSON.stringify({ handle: 'abc', displayName: 'Name', bio: 'BAD', locale: 'en', timeZone: 'Asia/Seoul' });
    expect(parse(await write(event('PUT /me', { body })))).toEqual({ status: 422, body: { error: 'profile_blocked' } });
  });

  it('follows only when both people have permission', async () => {
    const { repo, api, write } = setup();
    await write(event('PUT /me', { body: profile('one') }));
    await write(event('PUT /me', { sub: U2, body: profile('two') }));
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

describe('PUT /me/photo', () => {
  const profile = JSON.stringify({ handle: 'abc', displayName: 'Name', bio: '', locale: 'ko', timeZone: 'Asia/Seoul' });

  it('saves a checked face photo and replaces the old one', async () => {
    process.env.PHOTO_BASE_URL = 'https://cdn.example';
    const { write, stored } = setup();
    await write(event('PUT /me', { body: profile }));
    const first = parse(await write(event('PUT /me/photo', { body: JSON.stringify({ jpeg: jpeg('face') }) })));
    expect(first.status).toBe(200);
    expect(first.body.photoUrl).toMatch(/^https:\/\/cdn\.example\/photos\/.+\.jpg$/);
    await write(event('PUT /me/photo', { body: JSON.stringify({ jpeg: jpeg('face') }) }));
    expect(stored.size).toBe(1);
    delete process.env.PHOTO_BASE_URL;
  });

  it('says why a photo was refused', async () => {
    const { write, stored } = setup();
    await write(event('PUT /me', { body: profile }));
    const r = parse(await write(event('PUT /me/photo', { body: JSON.stringify({ jpeg: jpeg('many_faces') }) })));
    expect(r).toEqual({ status: 422, body: { error: 'photo_refused', problem: 'many_faces' } });
    expect(stored.size).toBe(0);
  });

  it('rejects files that are not JPEG, and writers without a profile', async () => {
    const { write } = setup();
    const png = Buffer.from('\x89PNG....').toString('base64');
    expect(parse(await write(event('PUT /me/photo', { body: JSON.stringify({ jpeg: png }) }))).status).toBe(400);
    expect(parse(await write(event('PUT /me/photo', { body: JSON.stringify({ jpeg: jpeg('face') }) }))).status).toBe(409);
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
    const api = apiHandler({ repo, translator: { translate: async (t: string) => (calls++, `번역: ${t}`) }, ...noStores });
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
    const api = apiHandler({ repo, translator: { translate: async () => { throw new Error('down'); } }, ...noStores });
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

describe('suspended people', () => {
  it('cannot write, and GET /me says whether the reader is an admin', async () => {
    const { repo, write, api } = setup();
    repo.users.set(U1, { handle: 'one', displayName: 'One', bio: '', locale: 'ko', timeZone: 'Asia/Seoul' });
    repo.suspended.add(U1);
    const r = parse(await write(event('POST /posts', { body: post(TEXT) })));
    expect(r).toEqual({ status: 403, body: { error: 'suspended' } });
    expect(parse(await api(event('GET /me'))).body.isAdmin).toBe(false);
    expect(parse(await api(event('GET /users/{id}', { pathParameters: { id: U1 }, sub: U2 }))).body.isAdmin).toBeUndefined();
  });
});

describe('DELETE /me', () => {
  it('erases the profile, the photo file and the sign-in account', async () => {
    const { repo, write, api, stored, deletedUsers } = setup();
    repo.users.set(U1, { handle: 'one', displayName: 'One', bio: '', locale: 'ko', timeZone: 'Asia/Seoul' });
    expect(parse(await write(event('PUT /me/photo', { body: JSON.stringify({ jpeg: jpeg('face') }) }))).status).toBe(200);
    expect(stored.size).toBe(1);

    expect(parse(await api(event('DELETE /me'))).status).toBe(204);
    expect(repo.users.has(U1)).toBe(false);
    expect(stored.size).toBe(0);
    expect(deletedUsers).toEqual([U1]);
    // Asking again still succeeds, so a half-finished deletion can be completed.
    expect(parse(await api(event('DELETE /me'))).status).toBe(204);
  });
});
