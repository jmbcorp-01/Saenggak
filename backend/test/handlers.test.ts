import { describe, expect, it } from 'vitest';
import { apiHandler } from '../src/handlers/api.js';
import type { Event } from '../src/handlers/http.js';
import { writeHandler } from '../src/handlers/write.js';
import { type Accounts, handler as preSignUp, makeHandler, splitProviderUser } from '../src/handlers/preSignUp.js';
import type { PreSignUpTriggerEvent } from 'aws-lambda';
import type { FeedPost } from '../src/services/ports.js';
import { editSession, humanSession, MemoryRepo, MemorySocial } from './helpers.js';

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
  social: new MemorySocial(),
  photoStore: { put: async () => {}, remove: async () => {} },
  users: { deleteUser: async () => {} },
  embedder: { embed: async () => [0.5] },
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
  const social = new MemorySocial();
  const api = apiHandler({
    repo,
    social,
    translator: { translate: async (t: string) => `번역: ${t}` },
    photoStore: { put: async () => {}, remove: async (key: string) => void stored.delete(key) },
    users: { deleteUser: async (id: string) => void deletedUsers.push(id) },
    embedder: { embed: async () => [0.5] },
  });
  return { repo, write, api, stored, deletedUsers, social };
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

    const alerts = (on: boolean) =>
      api(event(on ? 'PUT /users/{id}/alerts' : 'DELETE /users/{id}/alerts', { pathParameters: { id: U2 } }));
    expect(parse(await alerts(true))).toEqual({ status: 200, body: { alerts: true } });
    expect(parse(await api(event('GET /users/{id}', { pathParameters: { id: U2 } }))).body).toMatchObject({ alertsByMe: true });
    expect(parse(await alerts(false))).toEqual({ status: 200, body: { alerts: false } });

    await api(event('DELETE /users/{id}/follow', { pathParameters: { id: U2 } }));
    expect(repo.follows.size).toBe(0);
    expect(parse(await alerts(true))).toEqual({ status: 404, body: { error: 'not_following' } });
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
    typingMs: 1000, empathyCount: 0, empathizedByMe: false, bookmarkedByMe: false, createdAt: '2026-11-25T00:00:00Z', editedAt: null,
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

  it('translates into English when the reader gives no language', async () => {
    const { repo } = setup();
    repo.feedPosts = [item('p1', 'en'), item('p2', 'ko')];
    const api = apiHandler({ repo, translator: { translate: async (t: string) => `EN: ${t}` }, ...noStores });
    const r = parse(await api(event('GET /feed')));
    expect(r.body.items[0].translation).toBeNull();
    expect(r.body.items[1].translation).toEqual({ lang: 'en', body: 'EN: body p2' });
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

describe('reports, blocks and notifications', () => {
  it('reports a post against its author, with a known reason only', async () => {
    const { repo, write, api, social } = setup();
    repo.users.set(U2, { handle: 'two', displayName: 'Two', bio: '', locale: 'ko', timeZone: 'Asia/Seoul' });
    const id = parse(await write(event('POST /posts', { body: post(TEXT), sub: U2 }))).body.id;
    const report = (reason: string, sub = U1) =>
      api(event('POST /posts/{id}/report', { pathParameters: { id }, body: JSON.stringify({ reason, note: ' copied ' }), sub }));

    expect(parse(await report('ai_or_copied')).status).toBe(204);
    expect(social.reports).toEqual([{ reporterId: U1, userId: U2, postId: id, reason: 'ai_or_copied', note: 'copied' }]);
    expect(parse(await report('nonsense')).status).toBe(400);
    expect(parse(await report('spam', U2)).body).toEqual({ error: 'self' });
  });

  it('blocks and unblocks, and lists the blocked', async () => {
    const { api } = setup();
    expect(parse(await api(event('PUT /users/{id}/block', { pathParameters: { id: U2 } }))).body).toEqual({ blocked: true });
    expect(parse(await api(event('GET /me/blocks'))).body.items).toHaveLength(1);
    await api(event('DELETE /users/{id}/block', { pathParameters: { id: U2 } }));
    expect(parse(await api(event('GET /me/blocks'))).body.items).toHaveLength(0);
    expect(parse(await api(event('PUT /users/{id}/block', { pathParameters: { id: U1 } }))).status).toBe(400);
  });

  it('lists notifications with photo URLs and marks them seen', async () => {
    const { api, social } = setup();
    social.items = [
      { kind: 'follow', at: '2026-11-25 01:00:00+00', actorId: U2, actorHandle: 'two', actorName: 'Two', actorPhotoKey: null, postId: null, excerpt: null },
    ];
    const r = parse(await api(event('GET /notifications')));
    expect(r.body.unread).toBe(1);
    expect(r.body.items[0]).toMatchObject({ kind: 'follow', actorHandle: 'two', actorPhotoUrl: null });
    expect(r.body.items[0].actorPhotoKey).toBeUndefined();
    await api(event('POST /notifications/seen'));
    expect(parse(await api(event('GET /notifications'))).body.unread).toBe(0);
  });
});

describe('the 추천 feed, search, bookmarks and export', () => {
  const item = (id: string, authorId: string): FeedPost => ({
    id, authorId, authorHandle: 'a', authorName: 'A', photoKey: null, body: `body ${id}`, lang: 'en',
    typingMs: 1000, empathyCount: 0, empathizedByMe: false, bookmarkedByMe: false, createdAt: '2026-11-25T00:00:00Z', editedAt: null,
  });

  it('ranks the default tab, pages it by offset, and keeps one writer from filling a page', async () => {
    const { api, repo } = setup();
    repo.feedPosts = Array.from({ length: 30 }, (_, k) => item(`p${k}`, k < 4 ? 'same' : `w${k}`));
    const r = parse(await api(event('GET /feed', { queryStringParameters: { tab: 'all', cursor: '30' } })));
    expect(repo.feedCalls.at(-1)).toMatchObject({ ranked: true, offset: 30 });
    expect(r.body.next).toBe('60');
    // The third and fourth post by the same writer move to the end.
    expect(r.body.items.slice(0, 3).map((p: FeedPost) => p.id)).toEqual(['p0', 'p1', 'p4']);
    expect(r.body.items.slice(-2).map((p: FeedPost) => p.id)).toEqual(['p2', 'p3']);

    await api(event('GET /feed', { queryStringParameters: { tab: 'following' } }));
    expect(repo.feedCalls.at(-1)).toMatchObject({ following: true });
    expect(repo.feedCalls.at(-1)!.ranked).toBeUndefined();
    await api(event('GET /feed', { queryStringParameters: { author: U2 } }));
    expect(repo.feedCalls.at(-1)!.ranked).toBeUndefined();
  });

  it('finds people and posts, skipping empty searches', async () => {
    const { api, repo } = setup();
    repo.users.set(U2, { handle: 'seoha', displayName: 'Seoha', bio: '', locale: 'ko', timeZone: 'Asia/Seoul' });
    repo.feedPosts = [item('p1', U2)];
    expect(parse(await api(event('GET /search/users', { queryStringParameters: { q: 'seo' } }))).body.items).toEqual([
      { id: U2, handle: 'seoha', displayName: 'Seoha', bio: '', photoUrl: null },
    ]);
    expect(parse(await api(event('GET /search/users', { queryStringParameters: { q: '@' } }))).body.items).toEqual([]);
    expect(parse(await api(event('GET /search/posts', { queryStringParameters: { q: '바다' } }))).body.items).toHaveLength(1);
    expect(repo.searchCalls).toHaveLength(1);
    expect(parse(await api(event('GET /search/posts', { queryStringParameters: { q: 'a' } }))).body.items).toEqual([]);
    expect(repo.searchCalls).toHaveLength(1);
  });

  it('opens one post, saves it and exports the reader\'s records', async () => {
    const { api, repo } = setup();
    const id = '00000000-0000-4000-8000-000000000001';
    repo.feedPosts = [item(id, U2)];
    expect(parse(await api(event('GET /posts/{id}', { pathParameters: { id } }))).body.id).toBe(id);
    expect(parse(await api(event('GET /posts/{id}', { pathParameters: { id: U2 } }))).status).toBe(404);
    expect(parse(await api(event('PUT /posts/{id}/bookmark', { pathParameters: { id } }))).body).toEqual({ saved: true });
    expect(repo.bookmarks.has(`${U1}:${id}`)).toBe(true);
    await api(event('DELETE /posts/{id}/bookmark', { pathParameters: { id } }));
    expect(repo.bookmarks.size).toBe(0);
    expect(parse(await api(event('GET /me/export'))).status).toBe(404);
    repo.users.set(U1, { handle: 'one', displayName: 'One', bio: '', locale: 'ko', timeZone: 'Asia/Seoul' });
    expect(parse(await api(event('GET /me/export'))).body.profile.handle).toBe('one');
  });
});

describe('human checks', () => {
  const burst = { last10m: { empathy: 50 }, lastHour: { empathy: 150 }, accountAgeHours: 100, lowScorePosts: 0, hoursSinceCheck: null };

  it('stops automated-looking activity until a typed check passes', async () => {
    const { api, repo, write } = setup();
    const id = '00000000-0000-4000-8000-000000000001';
    repo.recentActivity = burst;
    expect(parse(await api(event('POST /posts/{id}/empathy', { pathParameters: { id } })))).toEqual({
      status: 428,
      body: { error: 'human_check' },
    });
    expect(parse(await write(event('POST /posts', { body: post(TEXT) }))).status).toBe(428);

    const { phrase } = parse(await api(event('GET /me/human-check', { queryStringParameters: { lang: 'en' } }))).body;
    expect(typeof phrase).toBe('string');
    // A pasted or wrong answer fails and is counted.
    const pasted = { text: phrase, session: { events: [{ t: 0, i: phrase.length, d: 0, s: 'keyboard' }] } };
    expect(parse(await api(event('POST /me/human-check', { body: JSON.stringify(pasted) }))).status).toBe(400);
    expect(parse(await api(event('POST /me/human-check', { body: post('something else entirely typed') }))).status).toBe(400);
    expect(repo.actions.filter((a) => a.kind === 'check_failed')).toHaveLength(2);

    expect(parse(await api(event('POST /me/human-check', { body: post(phrase) }))).status).toBe(204);
    expect(repo.humanChecked.has(U1)).toBe(true);
    expect(parse(await write(event('POST /posts', { body: post(TEXT) }))).status).toBe(201);
    expect(repo.actions.at(-1)).toEqual({ userId: U1, kind: 'post' });
  });

  it('counts ordinary actions without asking', async () => {
    const { api, repo } = setup();
    await api(event('PUT /users/{id}/block', { pathParameters: { id: U2 } }));
    expect(repo.actions).toEqual([{ userId: U1, kind: 'block' }]);
  });
});

describe('entry checks', () => {
  it('answers only requests that came through CloudFront', async () => {
    const { api } = setup();
    process.env.ORIGIN_SECRET = 'from-cdn';
    try {
      expect(parse(await api(event('GET /me/blocks'))).status).toBe(403);
      const through = event('GET /me/blocks', { headers: { 'x-origin-verify': 'from-cdn' } });
      expect(parse(await api(through)).status).toBe(200);
    } finally {
      delete process.env.ORIGIN_SECRET;
    }
  });

  it('refuses sign-ups from throwaway mail services', async () => {
    const signUp = (email: string) => ({ request: { userAttributes: { email } } }) as unknown as PreSignUpTriggerEvent;
    await expect(preSignUp(signUp('bot@Mailinator.com'))).rejects.toThrow('disposable_email');
    await expect(preSignUp(signUp('me@gmail.com'))).resolves.toBeTruthy();
  });

  it('joins a first Google or Apple sign-in to the email account with the same address', async () => {
    const calls: string[] = [];
    const existing = new Map([['me@gmail.com', 'sub-me']]);
    const accounts: Accounts = {
      findByEmail: async (_pool, email) => existing.get(email),
      create: async (_pool, email) => {
        calls.push(`create ${email}`);
        return 'sub-new';
      },
      link: async (_pool, username, provider, id) => void calls.push(`link ${username} ${provider} ${id}`),
    };
    const external = (userName: string, email?: string) =>
      ({
        triggerSource: 'PreSignUp_ExternalProvider',
        userPoolId: 'pool',
        userName,
        request: { userAttributes: email ? { email } : {} },
      }) as unknown as PreSignUpTriggerEvent;
    const run = makeHandler(accounts);

    await run(external('Google_123', 'Me@Gmail.com'));
    await run(external('SignInWithApple_001.abc', 'x@privaterelay.appleid.com'));
    expect(calls).toEqual([
      'link sub-me Google 123',
      'create x@privaterelay.appleid.com',
      'link sub-new SignInWithApple 001.abc',
    ]);
    await expect(run(external('Google_9'))).rejects.toThrow('email_required');
  });

  it('names the provider from the Cognito username', () => {
    expect(splitProviderUser('google_1_2')).toEqual({ provider: 'Google', id: '1_2' });
    expect(splitProviderUser('signinwithapple_001.x')).toEqual({ provider: 'SignInWithApple', id: '001.x' });
  });
});
