import { describe, expect, it } from 'vitest';
import { draftQuestions, fallbackCaption, pickCandidates, publishDue } from '../src/growth/agent.js';
import { addDays, isCode, koreaDay, newInviteCode, newLinkCode, nextEveningSlot, platformOf } from '../src/growth/codes.js';
import { instagramCaption, invitePage, langFrom, postPage, sitemap, threadsText } from '../src/growth/pages.js';
import { adminHandler } from '../src/handlers/admin.js';
import { growthHandler } from '../src/handlers/growth.js';
import type { Event } from '../src/handlers/http.js';
import { publicHandler } from '../src/handlers/public.js';
import type {
  Copywriter,
  DueItem,
  GrowthAdmin,
  GrowthRepository,
  PromoCandidate,
  PromoDecision,
  PromoStore,
  Publisher,
} from '../src/services/growthPorts.js';
import { publishersFrom, refreshTokens } from '../src/services/meta.js';
import type { AdminRepository } from '../src/services/ports.js';

const ME = '11111111-1111-4111-8111-111111111111';
const POST = '33333333-3333-4333-8333-333333333333';
const ITEM = '44444444-4444-4444-8444-444444444444';
const SITE = 'https://saenggak.app';

const event = (routeKey: string, over: Omit<Partial<Event>, 'body'> & { body?: unknown; groups?: string } = {}): Event =>
  ({
    routeKey,
    requestContext: { authorizer: { jwt: { claims: { sub: ME, 'cognito:groups': over.groups ?? '[admins]' }, scopes: [] } } },
    queryStringParameters: {},
    pathParameters: {},
    headers: {},
    isBase64Encoded: false,
    ...over,
    body: over.body === undefined ? undefined : JSON.stringify(over.body),
  }) as unknown as Event;

const parse = (r: unknown) => {
  const res = r as { statusCode: number; body?: string; headers?: Record<string, string> };
  let body: unknown = null;
  try {
    body = res.body ? JSON.parse(res.body) : null;
  } catch {
    body = res.body;
  }
  return { status: res.statusCode, body: body as Record<string, unknown> & string, headers: res.headers ?? {} };
};

describe('codes', () => {
  it('makes invite and link codes that read clearly', () => {
    for (let i = 0; i < 50; i++) {
      const c = newInviteCode();
      expect(c).toMatch(/^[A-HJ-NP-Z2-9]{8}$/);
      expect(isCode(c)).toBe(true);
    }
    expect(newLinkCode('p')).toMatch(/^p-[a-hj-np-z2-9]{6}$/);
    expect(isCode('<script>')).toBe(false);
    expect(isCode('ab')).toBe(false);
  });

  it('tells the device from its user agent', () => {
    expect(platformOf('Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)')).toBe('ios');
    expect(platformOf('Mozilla/5.0 (Linux; Android 15; Pixel 9)')).toBe('android');
    expect(platformOf('Mozilla/5.0 (Macintosh)')).toBe('web');
    expect(platformOf(undefined)).toBe('web');
  });

  it('schedules for the next 21:00 in Korea', () => {
    expect(nextEveningSlot(new Date('2026-11-27T03:00:00Z')).toISOString()).toBe('2026-11-27T12:00:00.000Z');
    expect(nextEveningSlot(new Date('2026-11-27T12:00:00Z')).toISOString()).toBe('2026-11-28T12:00:00.000Z');
    expect(koreaDay(new Date('2026-11-27T16:00:00Z'))).toBe('2026-11-28');
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01');
  });
});

describe('public pages', () => {
  const post = { id: POST, body: '<b>밤</b>에 쓴 생각', lang: 'ko', authorName: '민지', typingMs: 125_000, empathyCount: 4, createdAt: '2026-11-27 10:00:00+00' };

  it('escapes what people wrote and keeps the code for sign-up', () => {
    const html = postPage({ site: SITE, post, code: 'web-post', stores: { android: 'https://play.google.com/x' } });
    expect(html).toContain('&lt;b&gt;밤&lt;/b&gt;에 쓴 생각');
    expect(html).not.toContain('<b>밤</b>');
    expect(html).toContain('민지님의 생각');
    expect(html).toContain(`${SITE}/?c=web-post`);
    expect(html).toContain('직접 타이핑 2분');
    expect(html).toContain('<b>web-post</b>');
  });

  it('leaves the name out for anonymous writers', () => {
    const html = postPage({ site: SITE, post: { ...post, authorName: null }, code: 'web-post', stores: {} });
    expect(html).toContain('어느 생각러의 생각');
    expect(html).not.toContain('민지');
  });

  it('speaks the reader’s language on the invite page', () => {
    expect(langFrom('ko-KR,ko;q=0.9')).toBe('ko');
    expect(langFrom('en-US')).toBe('en');
    expect(invitePage({ lang: 'en', site: SITE, code: 'ABCDEFGH', stores: {} })).toContain('Start on the web');
  });

  it('lists posts in the sitemap', () => {
    expect(sitemap(SITE, [{ id: POST, at: '2026-11-27 10:00:00' }])).toContain(`<loc>${SITE}/p/${POST}</loc><lastmod>2026-11-27</lastmod>`);
  });

  it('keeps Threads posts within 500 characters, dropping the caption first', () => {
    const short = threadsText({ body: '짧은 생각', lang: 'ko', authorName: null, caption: '함께 써요 #생각', link: `${SITE}/i/p-abc` });
    expect(short).toContain('— 어느 생각러의 생각');
    expect(short).toContain('#생각');
    const long = threadsText({ body: '가'.repeat(200), lang: 'ko', authorName: 'A', caption: 'x'.repeat(400), link: 'L' });
    expect([...long].length).toBeLessThanOrEqual(500);
    expect(long).not.toContain('xxx');
    expect(instagramCaption({ lang: 'en', authorName: 'Sam', caption: 'Write yours' })).toContain('A thought by Sam');
  });
});

/** A promo store kept in memory. */
class MemoryPromo implements PromoStore {
  candidatesList: PromoCandidate[] = [];
  items: { c: PromoCandidate; caption: string; code: string }[] = [];
  dueList: DueItem[] = [];
  marked: { id: string; posted: Record<string, string>; error: string | null }[] = [];
  withdrawnCards: string[] = [];
  questionDays: string[] = [];
  drafts: { day: string; textKo: string; textEn: string }[] = [];
  async candidates(limit: number) {
    return this.candidatesList.slice(0, limit);
  }
  async addItem(c: PromoCandidate, caption: string, code: string) {
    this.items.push({ c, caption, code });
  }
  async due() {
    return this.dueList;
  }
  async markPosted(id: string, posted: Record<string, string>, error: string | null) {
    this.marked.push({ id, posted, error });
  }
  async withdrawUnshareable() {
    return this.withdrawnCards;
  }
  async daysWithoutQuestion() {
    return this.questionDays;
  }
  async recentQuestions() {
    return ['어제의 질문'];
  }
  async addQuestionDrafts(d: { day: string; textKo: string; textEn: string }[]) {
    this.drafts.push(...d);
  }
}

const copy = (over: Partial<Copywriter> = {}): Copywriter => ({
  caption: async () => '오늘도 한 줄 #생각',
  questions: async (n) => Array.from({ length: n }, (_, i) => ({ ko: `질문 ${i}`, en: `Question ${i}` })),
  ...over,
});

describe('promo agent', () => {
  const cards = (removed: string[] = []) => ({ remove: async (k: string) => void removed.push(k) });

  it('picks candidates with a drafted caption and a link code each', async () => {
    const store = new MemoryPromo();
    store.candidatesList = [
      { postId: 'a', body: '생각 하나', lang: 'ko', score: 9 },
      { postId: 'b', body: 'one thought', lang: 'en', score: 5 },
    ];
    expect(await pickCandidates({ store, copywriter: copy(), cards: cards() })).toBe(2);
    expect(store.items.map((i) => i.caption)).toEqual(['오늘도 한 줄 #생각', '오늘도 한 줄 #생각']);
    expect(store.items[0]!.code).toMatch(/^p-/);
  });

  it('still queues a post with a plain caption when drafting fails', async () => {
    const store = new MemoryPromo();
    store.candidatesList = [{ postId: 'b', body: 'one thought', lang: 'en', score: 5 }];
    await pickCandidates({ store, copywriter: copy({ caption: async () => Promise.reject(new Error('down')) }), cards: cards() });
    expect(store.items[0]!.caption).toBe(fallbackCaption('en'));
  });

  it('deletes the cards of withdrawn items', async () => {
    const store = new MemoryPromo();
    store.withdrawnCards = ['photos/promo/x.png'];
    const removed: string[] = [];
    await publishDue({ store, cards: cards(removed), publishers: [], site: SITE });
    expect(removed).toEqual(['photos/promo/x.png']);
  });

  const due = (over: Partial<DueItem> = {}): DueItem => ({
    id: ITEM,
    caption: '함께 써요',
    cardKey: 'photos/promo/c.png',
    body: '오늘의 생각',
    lang: 'ko',
    authorName: '민지',
    linkCode: 'p-abcdef',
    posted: {},
    ...over,
  });

  it('posts due items to every connected channel, with the card on Instagram', async () => {
    const store = new MemoryPromo();
    store.dueList = [due()];
    const sent: { channel: string; text: string; imageUrl: string | null }[] = [];
    const pub = (channel: string): Publisher => ({ channel, publish: async (p) => (sent.push({ channel, ...p }), `${channel}-1`) });
    const report = await publishDue({ store, cards: cards(), publishers: [pub('threads'), pub('instagram')], site: SITE });
    expect(report).toEqual({ posted: 1, failed: 0, waiting: 0 });
    expect(store.marked).toEqual([{ id: ITEM, posted: { threads: 'threads-1', instagram: 'instagram-1' }, error: null }]);
    expect(sent[0]!.text).toContain(`${SITE}/i/p-abcdef`);
    expect(sent[0]!.text).toContain('오늘의 생각');
    expect(sent[1]!.imageUrl).toBe(`${SITE}/photos/promo/c.png`);
  });

  it('does not post twice to a channel, and records a failure for a retry', async () => {
    const store = new MemoryPromo();
    store.dueList = [due({ posted: { threads: 't-0' } })];
    let threadsCalls = 0;
    const threads: Publisher = { channel: 'threads', publish: async () => (threadsCalls++, 'again') };
    const ig: Publisher = { channel: 'instagram', publish: async () => Promise.reject(new Error('400 bad image')) };
    const report = await publishDue({ store, cards: cards(), publishers: [threads, ig], site: SITE });
    expect(threadsCalls).toBe(0);
    expect(report.failed).toBe(1);
    expect(store.marked[0]!.posted).toEqual({ threads: 't-0' });
    expect(store.marked[0]!.error).toContain('instagram: 400 bad image');
  });

  it('leaves approved items for an admin when no channel is connected', async () => {
    const store = new MemoryPromo();
    store.dueList = [due()];
    expect(await publishDue({ store, cards: cards(), publishers: [], site: SITE })).toEqual({ posted: 0, failed: 0, waiting: 1 });
    expect(store.marked).toEqual([]);
  });

  it('drafts questions for the days without one', async () => {
    const store = new MemoryPromo();
    store.questionDays = ['2026-11-29', '2026-12-01'];
    expect(await draftQuestions({ store, copywriter: copy() }, new Date('2026-11-27T00:00:00Z'))).toBe(2);
    expect(store.drafts).toEqual([
      { day: '2026-11-29', textKo: '질문 0', textEn: 'Question 0' },
      { day: '2026-12-01', textKo: '질문 1', textEn: 'Question 1' },
    ]);
  });
});

describe('Meta accounts', () => {
  it('uses only channels with real ids and tokens', () => {
    expect(publishersFrom({ threadsUserId: 'REPLACE', threadsToken: 'REPLACE' })).toEqual([]);
    const list = publishersFrom({ threadsUserId: '1234567890', threadsToken: 'THQWJ-long-token', instagramUserId: 'REPLACE' });
    expect(list.map((p) => p.channel)).toEqual(['threads']);
  });

  it('publishes to Threads in two steps', async () => {
    const calls: string[] = [];
    const fake = (async (url: string) => {
      calls.push(String(url));
      return new Response(JSON.stringify({ id: calls.length === 1 ? 'container' : 'post-9' }), { status: 200 });
    }) as unknown as typeof fetch;
    const [threads] = publishersFrom({ threadsUserId: '1234567890', threadsToken: 'THQWJ-long-token' }, fake);
    const id = await threads!.publish({ text: 'hello', imageUrl: null });
    expect(id).toBe('post-9');
    expect(calls).toEqual([
      'https://graph.threads.net/v1.0/1234567890/threads',
      'https://graph.threads.net/v1.0/1234567890/threads_publish',
    ]);
  });

  it('keeps a token that fails to refresh', async () => {
    const fake = (async () => new Response('{"error":{"message":"expired"}}', { status: 400 })) as unknown as typeof fetch;
    const t = { threadsUserId: '1234567890', threadsToken: 'THQWJ-long-token' };
    expect(await refreshTokens(t, fake)).toEqual(t);
  });
});

function growthRepo(over: Partial<GrowthRepository> = {}): GrowthRepository & { log: string[] } {
  const log: string[] = [];
  return {
    log,
    sharing: async () => ({ shareOk: false, anonymous: false }),
    setSharing: async (_u, s) => (log.push(`sharing ${s.shareOk} ${s.anonymous}`), true),
    setPostExcluded: async (_u, p, x) => (log.push(`exclude ${p} ${x}`), p === POST),
    inviteCode: async () => 'ABCDEFGH',
    resolveCode: async (c) => (c === 'ABCDEFGH' ? { code: c, channel: 'invite', referrerId: 'r' } : null),
    recordClick: async (c, p) => void log.push(`click ${c} ${p}`),
    recordSource: async (_u, c) => (c === 'ABCDEFGH' ? 'ok' : c === 'mine-code' ? 'self' : 'unknown_code'),
    todayQuestion: async () => ({ id: 'q', day: '2026-11-27', textKo: '오늘 웃은 일은?', textEn: 'What made you smile today?', status: 'approved' }),
    publicPost: async (id) =>
      id === POST ? { id, body: '생각', lang: 'ko', authorName: null, typingMs: 60_000, empathyCount: 1, createdAt: '2026-11-27' } : null,
    publicPostIds: async () => [{ id: POST, at: '2026-11-27' }],
    ...over,
  };
}

describe('growth routes', () => {
  it('turns sharing on and off, anonymous only when asked', async () => {
    const repo = growthRepo();
    const h = growthHandler({ growth: repo, site: SITE });
    expect(parse(await h(event('PUT /me/sharing', { body: { shareOk: true } }))).body).toEqual({ shareOk: true, anonymous: false });
    expect(parse(await h(event('PUT /me/sharing', { body: { shareOk: 'yes' } }))).status).toBe(400);
    expect(repo.log).toEqual(['sharing true false']);
  });

  it('excludes one post', async () => {
    const h = growthHandler({ growth: growthRepo(), site: SITE });
    const ok = parse(await h(event('PUT /posts/{id}/sharing', { pathParameters: { id: POST }, body: { excluded: true } })));
    expect(ok).toMatchObject({ status: 200, body: { excluded: true } });
    const other = parse(await h(event('PUT /posts/{id}/sharing', { pathParameters: { id: ITEM }, body: { excluded: true } })));
    expect(other.status).toBe(404);
  });

  it('gives the reader’s invite link', async () => {
    const h = growthHandler({ growth: growthRepo(), site: SITE });
    expect(parse(await h(event('GET /me/invite'))).body).toEqual({ code: 'ABCDEFGH', url: `${SITE}/i/ABCDEFGH` });
  });

  it('records where a new person came from, quietly ignoring what cannot count', async () => {
    const h = growthHandler({ growth: growthRepo(), site: SITE });
    expect(parse(await h(event('POST /me/source', { body: { code: 'ABCDEFGH' } }))).status).toBe(204);
    expect(parse(await h(event('POST /me/source', { body: { code: 'nope-x' } }))).status).toBe(404);
    expect(parse(await h(event('POST /me/source', { body: { code: 'mine-code' } }))).body).toEqual({ recorded: false, reason: 'self' });
    expect(parse(await h(event('POST /me/source', { body: { code: '<x>' } }))).status).toBe(400);
  });

  it('gives today’s question', async () => {
    const h = growthHandler({ growth: growthRepo(), site: SITE });
    expect(parse(await h(event('GET /questions/today'))).body).toEqual({
      question: { ko: '오늘 웃은 일은?', en: 'What made you smile today?' },
    });
  });
});

describe('public routes', () => {
  const h = (repo = growthRepo()) => publicHandler({ growth: repo, site: SITE, stores: {} });
  const pub = (routeKey: string, over: Record<string, unknown> = {}) =>
    ({ routeKey, headers: { 'accept-language': 'ko', 'user-agent': 'iPhone' }, pathParameters: {}, ...over }) as never;

  it('counts a click and shows the invite page', async () => {
    const repo = growthRepo();
    const r = parse(await h(repo)(pub('GET /public/i/{code}', { pathParameters: { code: 'ABCDEFGH' } })));
    expect(r.status).toBe(200);
    expect(r.headers['cache-control']).toBe('no-store');
    expect(String(r.body)).toContain('?c=ABCDEFGH');
    expect(repo.log).toEqual(['click ABCDEFGH ios']);
  });

  it('answers 404 for an unknown code without counting it', async () => {
    const repo = growthRepo();
    expect(parse(await h(repo)(pub('GET /public/i/{code}', { pathParameters: { code: 'zzzzzz' } }))).status).toBe(404);
    expect(repo.log).toEqual([]);
  });

  it('shows a shareable post and hides others', async () => {
    const ok = parse(await h()(pub('GET /public/p/{id}', { pathParameters: { id: POST } })));
    expect(ok.status).toBe(200);
    expect(ok.headers['cache-control']).toBe('public, max-age=60');
    expect(parse(await h()(pub('GET /public/p/{id}', { pathParameters: { id: ITEM } }))).status).toBe(404);
    expect(parse(await h()(pub('GET /public/p/{id}', { pathParameters: { id: 'x' } }))).status).toBe(404);
  });

  it('refuses requests that did not come through CloudFront', async () => {
    process.env.ORIGIN_SECRET = 's3cret';
    try {
      expect(parse(await h()(pub('GET /public/sitemap-posts.xml'))).status).toBe(403);
      const ok = await h()(pub('GET /public/sitemap-posts.xml', { headers: { 'x-origin-verify': 's3cret' } }));
      expect(parse(ok).status).toBe(200);
    } finally {
      delete process.env.ORIGIN_SECRET;
    }
  });
});

describe('admin growth routes', () => {
  function setup() {
    const log: string[] = [];
    const stored: { key: string; type?: string }[] = [];
    const growth: GrowthAdmin = {
      dashboard: async (days) => (log.push(`dashboard ${days}`), { days: [], retention: {} as never, sources: [] }),
      audit: async () => [],
      promoItems: async (st) => (log.push(`promo ${st.join(',')}`), []),
      decidePromo: async (id: string, _a: string, d: PromoDecision) => (log.push(`decide ${d.approve} ${d.cardKey ?? '-'} ${d.caption ?? '-'}`), id === ITEM),
      markPromo: async (id, _a, s) => (log.push(`mark ${s}`), id === ITEM),
      linkStats: async () => [],
      createLinkCode: async (_a, code) => (code === 'taken' ? 'taken' : 'ok'),
      questions: async (from) => (log.push(`questions ${from}`), []),
      saveQuestion: async (_a, q) => ({ id: 'q', day: q.day, textKo: q.textKo, textEn: q.textEn, status: q.approve ? 'approved' : 'draft' }),
    };
    const handler = adminHandler({
      admin: {} as AdminRepository,
      photoStore: { put: async (key, _b, type) => void stored.push({ key, type }), remove: async () => {} },
      growth,
      pickNow: async () => 3,
      channels: async () => ['threads'],
    });
    return { handler, log, stored };
  }
  const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]).toString('base64');

  it('is for admins only', async () => {
    const { handler } = setup();
    expect(parse(await handler(event('GET /admin/dashboard', { groups: '[]' }))).status).toBe(403);
  });

  it('keeps the dashboard window between a week and 90 days', async () => {
    const { handler, log } = setup();
    await handler(event('GET /admin/dashboard', { queryStringParameters: { days: '400' } }));
    await handler(event('GET /admin/dashboard', { queryStringParameters: { days: 'x' } }));
    expect(log).toEqual(['dashboard 90', 'dashboard 30']);
  });

  it('lists the promo queue by tab with the connected channels', async () => {
    const { handler, log } = setup();
    const r = parse(await handler(event('GET /admin/promo', { queryStringParameters: { tab: 'scheduled' } })));
    expect(r.body).toEqual({ items: [], channels: ['threads'] });
    expect(log).toEqual(['promo approved,failed,takedown']);
    expect(parse(await handler(event('GET /admin/promo', { queryStringParameters: { tab: 'all' } }))).status).toBe(400);
  });

  it('stores the card as PNG when an item is approved', async () => {
    const { handler, log, stored } = setup();
    const r = await handler(event('POST /admin/promo/{id}/decision', { pathParameters: { id: ITEM }, body: { approve: true, png, caption: ' 새 캡션 ' } }));
    expect(parse(r).status).toBe(204);
    expect(stored[0]!.key).toMatch(new RegExp(`^photos/promo/${ITEM}-[0-9a-f]{8}\\.png$`));
    expect(stored[0]!.type).toBe('image/png');
    expect(log[0]).toBe(`decide true ${stored[0]!.key} 새 캡션`);
  });

  it('refuses a card that is not a PNG', async () => {
    const { handler, stored } = setup();
    const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0]).toString('base64');
    const r = await handler(event('POST /admin/promo/{id}/decision', { pathParameters: { id: ITEM }, body: { approve: true, png: jpeg } }));
    expect(parse(r)).toMatchObject({ status: 400, body: { error: 'bad_image' } });
    expect(stored).toEqual([]);
  });

  it('runs the pick on request and marks hand-made posts', async () => {
    const { handler, log } = setup();
    expect(parse(await handler(event('POST /admin/promo/run'))).body).toEqual({ added: 3 });
    expect(parse(await handler(event('POST /admin/promo/{id}/mark', { pathParameters: { id: ITEM }, body: { status: 'posted' } }))).status).toBe(204);
    expect(parse(await handler(event('POST /admin/promo/{id}/mark', { pathParameters: { id: ITEM }, body: { status: 'pending' } }))).status).toBe(400);
    expect(log).toEqual(['mark posted']);
  });

  it('makes link codes for a channel', async () => {
    const { handler } = setup();
    expect(parse(await handler(event('POST /admin/links', { body: { code: 'Disquiet-Launch', channel: 'community', label: '디스콰이엇' } }))).body).toEqual({
      code: 'disquiet-launch',
    });
    expect(parse(await handler(event('POST /admin/links', { body: { code: 'taken', channel: 'community' } }))).status).toBe(409);
    expect(parse(await handler(event('POST /admin/links', { body: { code: 'ok-code', channel: 'billboard' } }))).status).toBe(400);
  });

  it('saves and approves a question for a day', async () => {
    const { handler } = setup();
    const r = parse(
      await handler(event('PUT /admin/questions/{day}', { pathParameters: { day: '2026-12-01' }, body: { textKo: '첫눈', textEn: 'First snow', approve: true } })),
    );
    expect(r.body).toMatchObject({ day: '2026-12-01', status: 'approved' });
    const bad = await handler(event('PUT /admin/questions/{day}', { pathParameters: { day: '2026-13-45' }, body: { textKo: 'a', textEn: 'b', approve: true } }));
    expect(parse(bad).status).toBe(400);
  });
});
