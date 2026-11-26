import { fileURLToPath } from 'node:url';
import type { RDSDataClient } from '@aws-sdk/client-rds-data';
import pg from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { loadMigrations, migrate, type MigrationDb } from '../src/db/migrate.js';
import { deletePost, editPost, publishPost } from '../src/posts/publish.js';
import { MAX_COSINE_DISTANCE } from '../src/rules/similar.js';
import { AuroraAdminRepository } from '../src/services/adminRepository.js';
import { AuroraRepository } from '../src/services/repository.js';
import { AuroraSocialRepository } from '../src/services/socialRepository.js';
import { CLEANUP_SQL } from '../src/handlers/cleanup.js';
import { editSession, humanSession } from './helpers.js';
import { PgDataApi } from './pgDataApi.js';

/**
 * The repository's real SQL against Postgres with pgvector, through a Data
 * API stand-in. Runs when TEST_DATABASE_URL is set; each run creates its own
 * schema, so nothing existing is touched.
 */
const url = process.env.TEST_DATABASE_URL;
const A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const C = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

const TEXT = '요즘은 조용한 아침에 창문을 열고 바람 소리를 듣는 시간이 하루 중 가장 좋다. 그 짧은 순간이 나를 다시 사람으로 만든다.';
const EDITED = '오래된 편지를 다시 읽다가 그때의 내가 지금의 나보다 조금 더 용감했다는 걸 알았다. 이상하게 위로가 되는 밤이다.';

/** Unit vectors with an exact cosine similarity to the x axis. */
function vec(similarity: number): number[] {
  const v = Array(1024).fill(0);
  v[0] = similarity;
  v[1] = Math.sqrt(1 - similarity ** 2);
  return v;
}

describe.skipIf(!url)('AuroraRepository on Postgres', () => {
  let client: pg.Client;
  let repo: AuroraRepository;
  let nextVec = vec(1);
  const deps = () => ({
    repo,
    filter: {
      moderate: async (t: string) =>
        t.includes('BAD') ? { allowed: false as const, reason: 'spam' as const } : { allowed: true as const },
      moderateProfile: async () => true,
    },
    embedder: { embed: async () => nextVec },
  });
  const input = (authorId: string, text = TEXT) => ({ authorId, text, session: humanSession(text) });

  beforeAll(async () => {
    // A handful of posts here, so show first phrases from the first one.
    process.env.FIRST_PHRASES_MIN_POSTS = '1';
    client = new pg.Client({ connectionString: url });
    await client.connect();
    const schema = `t_${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
    await client.query(`CREATE SCHEMA ${schema}`);
    await client.query(`SET search_path TO ${schema}, public`);
    // The same migrations and statement splitting the deploy uses.
    const db: MigrationDb = {
      begin: async () => (await client.query('BEGIN'), 'tx'),
      exec: async (sql) => (await client.query({ text: sql, rowMode: 'array' })).rows,
      commit: async () => void (await client.query('COMMIT')),
      rollback: async () => void (await client.query('ROLLBACK')),
    };
    const migrations = loadMigrations(fileURLToPath(new URL('../src/db/migrations', import.meta.url)));
    expect(await migrate(db, migrations)).toEqual(migrations.map((m) => m.id));
    expect(await migrate(db, migrations)).toEqual([]);
    repo = new AuroraRepository('arn:cluster', 'arn:secret', 'test', new PgDataApi(client) as unknown as RDSDataClient);
    for (const [id, handle] of [[A, 'aa'], [B, 'bb'], [C, 'cc']] as const) {
      const saved = await repo.saveProfile(id, { handle, displayName: handle, bio: '', locale: 'ko', timeZone: 'Asia/Seoul' });
      expect(saved).toBe('ok');
    }
  });
  afterAll(async () => {
    delete process.env.FIRST_PHRASES_MIN_POSTS;
    await client?.end();
  });

  it('rejects a taken handle regardless of case', async () => {
    const saved = await repo.saveProfile(C, { handle: 'AA', displayName: 'x', bio: '', locale: 'ko', timeZone: 'Asia/Seoul' });
    expect(saved).toBe('handle_taken');
  });

  it('publishes, finds similar authors and claims first phrases', async () => {
    nextVec = vec(1);
    const first = await publishPost(deps(), input(A));
    expect(first.kind).toBe('published');
    if (first.kind !== 'published') return;
    expect(first.firstPhrases.length).toBeGreaterThan(0);
    expect(first.writingDays).toBe(1);

    nextVec = vec(0.9);
    const second = await publishPost(deps(), input(B));
    expect(second.kind).toBe('published');
    if (second.kind !== 'published') return;
    expect(second.firstPhrases).toEqual([]);
    expect(await repo.countSimilarAuthors(second.postId, vec(0.9), MAX_COSINE_DISTANCE)).toBe(1);
    // A vector at right angles to every stored post matches nobody.
    const unrelated = Array(1024).fill(0);
    unrelated[2] = 1;
    expect(await repo.countSimilarAuthors(first.postId, unrelated, MAX_COSINE_DISTANCE)).toBe(0);
  });

  it('pages the feed and filters by author', async () => {
    const all = await repo.feed(C, { following: false, limit: 30 });
    expect(all.map((p) => p.authorHandle)).toEqual(['bb', 'aa']);
    const older = await repo.feed(C, { following: false, before: all[0]!.createdAt, limit: 30 });
    expect(older.map((p) => p.authorHandle)).toEqual(['aa']);
    expect(await repo.feed(C, { following: false, authorId: A, limit: 30 })).toHaveLength(1);
    expect(await repo.feed(C, { following: true, limit: 30 })).toEqual([]);
  });

  it('edits until the first 공감 and clears old translations', async () => {
    const [post] = await repo.feed(C, { following: false, authorId: A, limit: 1 });
    const id = post!.id;
    await repo.saveTranslation(id, 'en', 'old translation');

    const edited = await editPost(deps(), { ...input(A, EDITED), session: editSession(TEXT, EDITED), postId: id });
    expect(edited.kind).toBe('published');
    expect(await repo.cachedTranslation(id, 'en')).toBeNull();
    const [after] = await repo.feed(C, { following: false, authorId: A, limit: 1 });
    expect(after!.body).toBe(EDITED);
    expect(after!.editedAt).not.toBeNull();

    expect(await repo.toggleEmpathy(id, C)).toEqual({ empathized: true, count: 1 });
    expect(await editPost(deps(), { ...input(A, TEXT), session: editSession(EDITED, TEXT), postId: id })).toEqual({ kind: 'locked' });
    expect(await repo.toggleEmpathy(id, A)).toBeNull();
  });

  it('frees the phrases of a deleted post', async () => {
    const [post] = await repo.feed(C, { following: false, authorId: B, limit: 1 });
    expect(await deletePost(repo, post!.id, A)).toBe(false);
    expect(await deletePost(repo, post!.id, B)).toBe(true);
    const again = await publishPost(deps(), input(C));
    expect(again.kind === 'published' && again.firstPhrases.length).toBeGreaterThan(0);
  });

  it('stores a thought score for each published post', async () => {
    const rows = await client.query(`SELECT thought_score, process_score, content_score FROM posts WHERE status = 'published'`);
    expect(rows.rows.length).toBeGreaterThan(0);
    for (const r of rows.rows) {
      expect(r.thought_score).toBeGreaterThanOrEqual(0);
      expect(r.thought_score).toBeLessThanOrEqual(100);
    }
  });

  it('ranks the 추천 feed by score, 공감 and the reader\'s taste, and pages by offset', async () => {
    const ranked = await repo.feed(B, { following: false, ranked: true, limit: 30 });
    expect(ranked.length).toBeGreaterThan(0);
    // A post with a much higher score comes first.
    const low = ranked.at(-1)!;
    await client.query(`UPDATE posts SET thought_score = 100 WHERE id = $1`, [low.id]);
    await client.query(`UPDATE posts SET thought_score = 0 WHERE id <> $1`, [low.id]);
    const again = await repo.feed(B, { following: false, ranked: true, limit: 30 });
    expect(again[0]!.id).toBe(low.id);
    expect(await repo.feed(B, { following: false, ranked: true, offset: again.length, limit: 30 })).toEqual([]);
  });

  it('saves and lists bookmarks', async () => {
    const [post] = await repo.feed(B, { following: false, limit: 1 });
    expect(await repo.setBookmark(B, post!.id, true)).toBe(true);
    expect(await repo.setBookmark(B, post!.id, true)).toBe(true);
    const saved = await repo.feed(B, { following: false, saved: true, limit: 30 });
    expect(saved.map((p) => p.id)).toEqual([post!.id]);
    expect(saved[0]!.bookmarkedByMe).toBe(true);
    expect((await repo.post(B, post!.id))!.bookmarkedByMe).toBe(true);
    expect(await repo.setBookmark(B, '00000000-0000-4000-8000-000000000999', true)).toBe(false);
    expect(await repo.setBookmark(B, post!.id, false)).toBe(true);
    expect(await repo.feed(B, { following: false, saved: true, limit: 30 })).toEqual([]);
  });

  it('finds people by handle or name, and posts by meaning', async () => {
    expect((await repo.findUsers(C, '@b', 10)).map((u) => u.handle)).toEqual(['bb']);
    expect((await repo.findUsers(C, '%', 10))).toEqual([]);
    const hits = await repo.searchPosts(C, vec(1), 0.5, 10);
    expect(hits.length).toBeGreaterThan(0);
    const unrelated = Array(1024).fill(0);
    unrelated[2] = 1;
    expect(await repo.searchPosts(C, unrelated, 0.5, 10)).toEqual([]);
  });

  it('counts recent actions and clears failed checks once a check passes', async () => {
    await repo.recordAction(C, 'empathy');
    await repo.recordAction(C, 'empathy');
    await repo.recordAction(C, 'check_failed');
    const a = await repo.activity(C);
    expect(a.last10m.empathy).toBe(2);
    expect(a.lastHour.check_failed).toBe(1);
    expect(a.hoursSinceCheck).toBeNull();
    await repo.setHumanChecked(C);
    const b = await repo.activity(C);
    expect(b.lastHour.check_failed).toBeUndefined();
    expect(b.hoursSinceCheck).toBeLessThan(1);
  });

  it('exports what is stored about a person', async () => {
    const data = await repo.exportData(C);
    expect(data).not.toBeNull();
    expect((data!.profile as { handle: string }).handle).toBe('cc');
    expect(Array.isArray(data!.posts)).toBe(true);
    expect(await repo.exportData('00000000-0000-4000-8000-000000000999')).toBeNull();
  });

  it('follows with permission and hides follows after 3 blocks', async () => {
    // Writing days come from the server clock, so earlier days are seeded directly.
    for (let d = 1; d <= 9; d++) {
      for (const who of [A, B]) {
        await client.query(
          `INSERT INTO posts (author_id, body, lang, typing_ms, local_date, created_at)
           VALUES ($1, 'seed', 'ko', 1000, $2::date, now() - make_interval(days => $3))`,
          [who, `2026-10-${String(d).padStart(2, '0')}`, 40 - d],
        );
      }
    }
    for (const who of [A, B]) await publishPost(deps(), input(who));
    expect((await repo.profile(A, A))?.followUnlocked).toBe(true);
    expect(await repo.follow(A, C)).toBe('not_allowed');
    expect(await repo.follow(A, B)).toBe('ok');
    expect((await repo.feed(A, { following: true, limit: 30 })).length).toBeGreaterThan(0);
    expect(await repo.profile(B, A)).toMatchObject({ followers: 1, followedByMe: true });

    await client.query(`DELETE FROM write_log`);
    for (let k = 0; k < 3; k++) {
      expect((await publishPost(deps(), input(B, `${TEXT} BAD`))).kind).toBe('blocked');
    }
    expect((await repo.profile(B, B))?.followUnlocked).toBe(false);
    expect(await repo.profile(B, A)).toMatchObject({ followers: 0, followedByMe: false });
    expect(await repo.writingDaysSinceLoss(B)).toBe(0);
    expect(await repo.recentBlocks(B, 30)).toBe(3);

    await repo.unfollow(A, B);
    expect(await repo.feed(A, { following: true, limit: 30 })).toEqual([]);
  });

  it('swaps the profile photo and returns the old key', async () => {
    expect(await repo.setPhoto(A, 'photos/a/1.jpg')).toEqual({ previous: null });
    expect(await repo.setPhoto(A, 'photos/a/2.jpg')).toEqual({ previous: 'photos/a/1.jpg' });
    expect((await repo.profile(A, B))?.photoKey).toBe('photos/a/2.jpg');
    expect(await repo.setPhoto('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'x')).toBeNull();
  });

  it('counts published posts up to a limit', async () => {
    expect(await repo.hasPublished(1)).toBe(true);
    expect(await repo.hasPublished(1_000_000)).toBe(false);
  });

  it('works out the writer day from their time zone', async () => {
    const today = (tz: string) =>
      client.query(`SELECT to_char(now() AT TIME ZONE $1, 'YYYY-MM-DD') AS d`, [tz]).then((r) => r.rows[0].d);
    expect(await repo.localDate(A)).toBe(await today('Asia/Seoul'));
    expect(await repo.localDate('dddddddd-dddd-4ddd-8ddd-dddddddddddd')).toBeNull();
  });

  it('limits writes per hour and does not count declined reviews', async () => {
    await client.query(`DELETE FROM write_log`);
    for (let k = 0; k < 3; k++) expect(await repo.recordWrite(C, 3)).toBe(true);
    expect(await repo.recordWrite(C, 3)).toBe(false);

    const before = await repo.recentBlocks(C, 30);
    await repo.insertPost({
      authorId: C, body: TEXT, lang: 'ko', typingMs: 1, localDate: '2026-11-25', status: 'blocked',
      blockedReason: 'classifier_declined', session: humanSession(TEXT) as never, issues: [],
    });
    expect(await repo.recentBlocks(C, 30)).toBe(before);
  });

  it('keeps 공감 consistent when two taps arrive together', async () => {
    const [post] = await repo.feed(B, { following: false, authorId: A, limit: 1 });
    const id = post!.id;
    await client.query(`DELETE FROM empathies WHERE post_id = $1`, [id]);
    // Both deletes run before either insert, so the second insert meets the first one's row.
    const results = await Promise.all([repo.toggleEmpathy(id, B), repo.toggleEmpathy(id, B)]);
    expect(results).toEqual([
      { empathized: true, count: 1 },
      { empathized: true, count: 1 },
    ]);
  });

  it('runs the admin pages: review, removal, search, suspension, photo, stats', async () => {
    const admin = new AuroraAdminRepository('arn:cluster', 'arn:secret', 'test', new PgDataApi(client) as unknown as RDSDataClient);
    const ADMIN = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
    const held = await repo.insertPost({
      authorId: C, body: 'held for review', lang: 'ko', typingMs: 1, localDate: '2026-11-25', status: 'blocked',
      blockedReason: 'classifier_declined', session: humanSession('x') as never, issues: ['fast'],
    });
    const queue = await admin.reviewQueue(30);
    const item = queue.find((q) => q.id === held);
    expect(item).toMatchObject({ authorHandle: 'cc', blockedReason: 'classifier_declined', issues: ['fast'] });
    expect((await admin.stats()).pendingReview).toBeGreaterThan(0);

    expect(await admin.reviewPost(held, ADMIN, 'publish')).toBe(true);
    expect(await admin.reviewPost(held, ADMIN, 'publish')).toBe(false);
    expect((await admin.reviewQueue(30)).some((q) => q.id === held)).toBe(false);
    expect((await repo.feed(A, { following: false, authorId: C, limit: 30 })).some((p) => p.id === held)).toBe(true);

    expect(await admin.removePost(held, ADMIN, 'spam')).toBe(true);
    expect(await admin.removePost(held, ADMIN, 'spam')).toBe(false);
    expect((await repo.feed(A, { following: false, authorId: C, limit: 30 })).some((p) => p.id === held)).toBe(false);

    expect((await admin.searchUsers('A', 30)).map((u) => u.handle)).toEqual(['aa']);
    expect((await admin.searchUsers('', 30)).length).toBeGreaterThanOrEqual(3);
    expect(await admin.searchUsers('%', 30)).toEqual([]);

    expect(await repo.isSuspended(B)).toBe(false);
    expect(await admin.setSuspended(B, ADMIN, true, 'abuse')).toBe(true);
    expect(await repo.isSuspended(B)).toBe(true);
    expect((await repo.feed(A, { following: false, limit: 30 })).some((p) => p.authorId === B)).toBe(false);
    expect((await admin.searchUsers('bb', 30))[0]).toMatchObject({ suspendedReason: 'abuse' });
    expect(await admin.setSuspended(B, ADMIN, false, '')).toBe(true);
    expect(await repo.isSuspended(B)).toBe(false);

    await repo.setPhoto(C, 'photos/c/1.jpg');
    expect(await admin.removePhoto(C, ADMIN)).toEqual({ previous: 'photos/c/1.jpg' });
    expect((await repo.profile(C, C))?.photoKey).toBeNull();
    expect(await admin.removePhoto('dddddddd-dddd-4ddd-8ddd-dddddddddddd', ADMIN)).toBe(false);

    const log = await client.query(`SELECT action FROM admin_actions ORDER BY id`);
    expect(log.rows.map((r) => r.action)).toEqual(['publish', 'remove_post', 'suspend', 'unsuspend', 'remove_photo']);
  });

  it('deletes an account with everything it made', async () => {
    const D = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
    await repo.saveProfile(D, { handle: 'dd', displayName: 'dd', bio: '', locale: 'ko', timeZone: 'Asia/Seoul' });
    await repo.setPhoto(D, 'photos/d/1.jpg');
    nextVec = vec(1);
    const mine = await publishPost(deps(), input(D, EDITED + ' 지운다'));
    expect(mine.kind).toBe('published');
    const [other] = await repo.feed(D, { following: false, authorId: A, limit: 1 });
    await repo.toggleEmpathy(other!.id, D);
    if (mine.kind === 'published') await repo.toggleEmpathy(mine.postId, A);

    expect(await repo.deleteAccount(D)).toEqual({ photoKey: 'photos/d/1.jpg' });
    expect(await repo.profile(D, D)).toBeNull();
    const left = await client.query(
      `SELECT (SELECT count(*) FROM posts WHERE author_id = $1) + (SELECT count(*) FROM empathies WHERE user_id = $1)
              + (SELECT count(*) FROM phrase_firsts WHERE author_id = $1) AS n`,
      [D],
    );
    expect(Number(left.rows[0].n)).toBe(0);
    expect(await repo.deleteAccount(D)).toBe(false);
  });

  it('reports, blocks and notifications', async () => {
    const social = new AuroraSocialRepository('arn:cluster', 'arn:secret', 'test', new PgDataApi(client) as unknown as RDSDataClient);
    const admin = new AuroraAdminRepository('arn:cluster', 'arn:secret', 'test', new PgDataApi(client) as unknown as RDSDataClient);
    const [post] = await repo.feed(C, { following: false, authorId: A, limit: 1 });
    const id = post!.id;

    expect(await social.report(C, { userId: A, postId: id, reason: 'spam', note: '' })).toBe('ok');
    expect(await social.report(C, { userId: A, postId: id, reason: 'spam', note: '' })).toBe('ok'); // not doubled
    expect(await social.report(C, { userId: B, postId: id, reason: 'spam', note: '' })).toBe('not_found'); // not B's post
    expect(await social.report(C, { userId: B, reason: 'impersonation', note: 'fake' })).toBe('ok');
    const open = await admin.openReports(30);
    expect(open.filter((r) => r.userId === A)).toHaveLength(1);
    expect(open.find((r) => r.userId === A)).toMatchObject({ postBody: post!.body, reporterHandle: 'cc', reportsOnUser: 1 });
    expect((await admin.stats()).openReports).toBe(2);
    expect(await admin.resolveReport(open[0]!.id, C, 'ok')).toBe(true);
    expect(await admin.resolveReport(open[0]!.id, C, 'ok')).toBe(false);

    // C gives A's post 공감, then A sees it in notifications.
    await client.query(`DELETE FROM empathies WHERE post_id = $1`, [id]);
    await repo.toggleEmpathy(id, C);
    let n = await social.notifications(A, 30);
    expect(n.items.some((x) => x.kind === 'empathy' && x.actorHandle === 'cc' && x.postId === id)).toBe(true);
    expect(n.unread).toBeGreaterThan(0);
    await social.markNotificationsSeen(A);
    expect((await social.notifications(A, 30)).unread).toBe(0);

    // A blocks C: C's 공감 leaves A's notifications, and neither sees the other's posts.
    expect(await social.block(A, C)).toBe('ok');
    n = await social.notifications(A, 30);
    expect(n.items.some((x) => x.actorHandle === 'cc')).toBe(false);
    expect((await repo.feed(C, { following: false, limit: 30 })).some((p) => p.authorId === A)).toBe(false);
    expect((await repo.feed(A, { following: false, limit: 30 })).some((p) => p.authorId === C)).toBe(false);
    expect((await repo.profile(C, A))?.blockedByMe).toBe(true);
    await repo.toggleEmpathy(id, C); // removes the existing one
    expect(await repo.toggleEmpathy(id, C)).toBeNull(); // cannot add while blocked
    expect((await social.blocked(A)).map((u) => u.handle)).toEqual(['cc']);
    await social.unblock(A, C);
    expect((await repo.feed(C, { following: false, limit: 30 })).some((p) => p.authorId === A)).toBe(true);
  });

  it('runs the daily cleanup statements', async () => {
    await client.query(`INSERT INTO write_log (author_id, at) VALUES ($1, now() - interval '2 days'), ($1, now())`, [A]);
    for (const sql of CLEANUP_SQL) await client.query(sql);
    const left = await client.query(`SELECT count(*) AS n FROM write_log WHERE author_id = $1 AND at < now() - interval '1 day'`, [A]);
    expect(Number(left.rows[0].n)).toBe(0);
  });
});
