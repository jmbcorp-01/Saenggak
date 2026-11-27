import { describe, expect, it } from 'vitest';
import { adminHandler, isAdmin } from '../src/handlers/admin.js';
import type { Event } from '../src/handlers/http.js';
import type { AdminRepository, ReviewDecision } from '../src/services/ports.js';
import type { GrowthAdmin } from '../src/services/growthPorts.js';

const ADMIN = '11111111-1111-4111-8111-111111111111';
const USER = '22222222-2222-4222-8222-222222222222';
const POST = '33333333-3333-4333-8333-333333333333';

const event = (routeKey: string, over: Partial<Event> & { groups?: unknown } = {}): Event =>
  ({
    routeKey,
    requestContext: {
      authorizer: { jwt: { claims: { sub: ADMIN, 'cognito:groups': over.groups ?? '[admins]' }, scopes: [] } },
    },
    queryStringParameters: {},
    pathParameters: {},
    isBase64Encoded: false,
    ...over,
  }) as unknown as Event;

const parse = (r: unknown) => {
  const res = r as { statusCode: number; body?: string };
  return { status: res.statusCode, body: res.body ? JSON.parse(res.body) : null };
};

function setup() {
  const log: string[] = [];
  const removed: string[] = [];
  const admin: AdminRepository = {
    stats: async () => ({ users: 2, usersToday: 1, posts: 5, postsToday: 1, pendingReview: 1, suspended: 0, openReports: 0 }),
    reviewQueue: async () => [],
    reviewPost: async (id: string, by: string, d: ReviewDecision) => (log.push(`${d} ${id} by ${by}`), id === POST),
    removePost: async (id: string, _by: string, note: string) => (log.push(`remove ${id} ${note}`), id === POST),
    searchUsers: async (q: string) => (log.push(`search ${q}`), []),
    setSuspended: async (id: string, _by: string, on: boolean, reason: string) => (
      log.push(`${on ? 'suspend' : 'unsuspend'} ${id} ${reason}`), id === USER
    ),
    removePhoto: async (id: string) => (id === USER ? { previous: 'photos/u/a.jpg' } : false),
    openReports: async () => [],
    resolveReport: async (id: string) => (log.push(`resolve ${id}`), id === '7'),
  };
  const handler = adminHandler({
    admin,
    photoStore: { put: async () => {}, remove: async (k) => void removed.push(k) },
    growth: {} as GrowthAdmin,
    pickNow: async () => 0,
    channels: async () => [],
  });
  return { handler, log, removed };
}

describe('admin pages', () => {
  it('reads the admins group from the claim in either form', () => {
    expect(isAdmin(event('GET /admin/stats', { groups: '[admins]' }))).toBe(true);
    expect(isAdmin(event('GET /admin/stats', { groups: '[writers admins]' }))).toBe(true);
    expect(isAdmin(event('GET /admin/stats', { groups: ['admins'] }))).toBe(true);
    expect(isAdmin(event('GET /admin/stats', { groups: '[administrators]' }))).toBe(false);
    expect(isAdmin(event('GET /admin/stats', { groups: '' }))).toBe(false);
  });

  it('refuses anyone outside the admins group', async () => {
    const { handler, log } = setup();
    const r = parse(await handler(event('POST /admin/posts/{id}/remove', { groups: '[]', pathParameters: { id: POST } })));
    expect(r.status).toBe(403);
    expect(log).toEqual([]);
  });

  it('shows stats', async () => {
    const { handler } = setup();
    const r = parse(await handler(event('GET /admin/stats')));
    expect(r.status).toBe(200);
    expect(r.body.pendingReview).toBe(1);
  });

  it('reviews a held post with a known decision only', async () => {
    const { handler, log } = setup();
    const ok = await handler(
      event('POST /admin/posts/{id}/review', { pathParameters: { id: POST }, body: '{"decision":"publish"}' }),
    );
    expect(parse(ok).status).toBe(204);
    expect(log).toEqual([`publish ${POST} by ${ADMIN}`]);
    const bad = await handler(event('POST /admin/posts/{id}/review', { pathParameters: { id: POST }, body: '{"decision":"x"}' }));
    expect(parse(bad).status).toBe(400);
  });

  it('removes a post with a note, and 404s for an unknown one', async () => {
    const { handler, log } = setup();
    const ok = await handler(event('POST /admin/posts/{id}/remove', { pathParameters: { id: POST }, body: '{"note":" spam "}' }));
    expect(parse(ok).status).toBe(204);
    expect(log).toEqual([`remove ${POST} spam`]);
    const missing = await handler(event('POST /admin/posts/{id}/remove', { pathParameters: { id: USER } }));
    expect(parse(missing).status).toBe(404);
  });

  it('searches people by handle without the @', async () => {
    const { handler, log } = setup();
    await handler(event('GET /admin/users', { queryStringParameters: { q: ' @Yoonseo ' } }));
    expect(log).toEqual(['search yoonseo']);
  });

  it('suspends and unsuspends, but not oneself', async () => {
    const { handler, log } = setup();
    const on = { pathParameters: { id: USER }, body: '{"suspended":true,"reason":"abuse"}' };
    expect(parse(await handler(event('PUT /admin/users/{id}/suspension', on))).status).toBe(200);
    expect(log).toEqual([`suspend ${USER} abuse`]);
    const self = { pathParameters: { id: ADMIN }, body: '{"suspended":true}' };
    expect(parse(await handler(event('PUT /admin/users/{id}/suspension', self))).body.error).toBe('self');
  });

  it('removes a photo and deletes the stored file', async () => {
    const { handler, removed } = setup();
    const r = parse(await handler(event('DELETE /admin/users/{id}/photo', { pathParameters: { id: USER } })));
    expect(r.status).toBe(204);
    expect(removed).toEqual(['photos/u/a.jpg']);
  });

  it('resolves a report by its number only', async () => {
    const { handler, log } = setup();
    expect(parse(await handler(event('POST /admin/reports/{id}/resolve', { pathParameters: { id: '7' } }))).status).toBe(204);
    expect(parse(await handler(event('POST /admin/reports/{id}/resolve', { pathParameters: { id: 'x' } }))).status).toBe(400);
    expect(log).toEqual(['resolve 7']);
  });
});
