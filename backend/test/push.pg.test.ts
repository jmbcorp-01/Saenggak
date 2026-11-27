import { fileURLToPath } from 'node:url';
import type { RDSDataClient } from '@aws-sdk/client-rds-data';
import pg from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { loadMigrations, migrate, type MigrationDb } from '../src/db/migrate.js';
import { AuroraPushRepository } from '../src/services/pushRepository.js';
import { PgDataApi } from './pgDataApi.js';

/** The push queries against Postgres. Runs when TEST_DATABASE_URL is set. */
const url = process.env.TEST_DATABASE_URL;
const A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const C = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const TA = 'token-for-a-ios-0123456789:APA91b';
const TB = 'token-for-b-web-0123456789:APA91b';

describe.skipIf(!url)('AuroraPushRepository on Postgres', () => {
  let client: pg.Client;
  let repo: AuroraPushRepository;
  const sql = (text: string, values: unknown[] = []) => client.query(text, values);
  /** Puts every mark a minute back, as if the sender last ran then. */
  const rewind = () => sql(`UPDATE users SET push_checked_at = now() - interval '1 minute'`);
  const ago = `now() - interval '30 seconds'`;

  beforeAll(async () => {
    client = new pg.Client({ connectionString: url });
    await client.connect();
    const schema = `p_${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
    await client.query(`CREATE SCHEMA ${schema}`);
    await client.query(`SET search_path TO ${schema}, public`);
    const db: MigrationDb = {
      begin: async () => (await client.query('BEGIN'), 'tx'),
      exec: async (s) => (await client.query({ text: s, rowMode: 'array' })).rows,
      commit: async () => void (await client.query('COMMIT')),
      rollback: async () => void (await client.query('ROLLBACK')),
    };
    await migrate(db, loadMigrations(fileURLToPath(new URL('../src/db/migrations', import.meta.url))));
    repo = new AuroraPushRepository('arn:cluster', 'arn:secret', 'test', new PgDataApi(client) as unknown as RDSDataClient);
    for (const [id, handle] of [[A, 'aa'], [B, 'bb'], [C, 'cc']] as const) {
      expect(
        await repo.saveProfile(id, { handle, displayName: `${handle} name`, bio: '', locale: 'ko', timeZone: 'Asia/Seoul' }),
      ).toBe('ok');
    }
  });
  afterAll(async () => {
    await client?.end();
  });

  it('keeps one owner per token and drops a removed one', async () => {
    expect(await repo.saveToken(A, TA, 'ios')).toBe(true);
    expect(await repo.saveToken(B, TA, 'ios')).toBe(true);
    expect((await repo.tokens([A, B])).get(B)).toEqual([{ token: TA, platform: 'ios' }]);
    expect((await repo.tokens([A])).get(A)).toBeUndefined();
    await repo.removeToken(A, TA); // not A's any more
    expect((await repo.tokens([B])).get(B)).toHaveLength(1);
    await repo.removeToken(B, TA);
    expect((await repo.tokens([B])).size).toBe(0);
    expect(await repo.saveToken('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', TA, 'web')).toBe(false);
  });

  it('saves which kinds to send', async () => {
    expect(await repo.pushSettings(A)).toEqual({ empathy: true, follow: true, posts: true });
    expect(await repo.setPushSettings(A, { empathy: false, follow: true, posts: true })).toBe(true);
    expect(await repo.pushSettings(A)).toEqual({ empathy: false, follow: true, posts: true });
    await repo.setPushSettings(A, { empathy: true, follow: true, posts: true });
  });

  it('groups new events by person and kind, once', async () => {
    await repo.saveToken(A, TA, 'ios');
    await repo.saveToken(B, TB, 'web');
    await rewind();
    const p = (
      await sql(
        `INSERT INTO posts (author_id, body, lang, typing_ms, local_date) VALUES ($1, '비 오는 날의 생각', 'ko', 60000, current_date) RETURNING id::text`,
        [A],
      )
    ).rows[0].id as string;
    await sql(`INSERT INTO empathies (post_id, user_id, created_at) VALUES ($1, $2, ${ago} - interval '5 seconds'), ($1, $3, ${ago})`, [p, B, C]);
    await sql(`INSERT INTO follows (follower_id, followee_id, created_at, alerts_since) VALUES ($1, $2, ${ago}, now() - interval '1 hour')`, [B, A]);
    // A's post is new, and B follows A with alerts on, but A wrote it before
    // the follow existed in this test, so set it inside the window.
    await sql(`UPDATE posts SET created_at = ${ago} WHERE id = $1`, [p]);

    const batches = await repo.takeBatches();
    const forA = batches.filter((b) => b.userId === A).sort((x, y) => x.kind.localeCompare(y.kind));
    expect(forA.map((b) => [b.kind, b.count, b.actorName])).toEqual([
      ['empathy', 2, 'cc name'],
      ['follow', 1, 'bb name'],
    ]);
    expect(forA[0]!.postId).toBe(p);
    expect(forA[0]!.excerpt).toBe('비 오는 날의 생각');
    const forB = batches.filter((b) => b.userId === B);
    expect(forB.map((b) => [b.kind, b.count, b.postId])).toEqual([['post', 1, p]]);

    // The mark moved, so the same events are not sent again.
    expect(await repo.takeBatches()).toEqual([]);
  });

  it('leaves out kinds turned off, blocked people and people without a device', async () => {
    // What the last test wrote is long past now.
    for (const t of ['empathies', 'follows', 'posts']) await sql(`UPDATE ${t} SET created_at = created_at - interval '1 hour'`);
    await rewind();
    const p = (
      await sql(
        `INSERT INTO posts (author_id, body, lang, typing_ms, local_date, created_at) VALUES ($1, '또 다른 생각', 'ko', 60000, current_date, ${ago}) RETURNING id::text`,
        [B],
      )
    ).rows[0].id as string;
    await sql(`INSERT INTO empathies (post_id, user_id, created_at) VALUES ($1, $2, ${ago})`, [p, A]);
    await sql(`INSERT INTO empathies (post_id, user_id, created_at) VALUES ($1, $2, ${ago})`, [p, C]);
    await sql(`INSERT INTO blocks (blocker_id, blocked_id) VALUES ($1, $2)`, [B, C]);
    await repo.setPushSettings(B, { empathy: true, follow: true, posts: false });
    const batches = await repo.takeBatches();
    expect(batches.map((b) => [b.userId, b.kind, b.count, b.actorName])).toEqual([[B, 'empathy', 1, 'aa name']]);

    await rewind();
    await repo.setPushSettings(B, { empathy: false, follow: true, posts: true });
    await sql(`INSERT INTO empathies (post_id, user_id, created_at) VALUES ($1, $2, ${ago}) ON CONFLICT DO NOTHING`, [p, A]);
    expect((await repo.takeBatches()).filter((b) => b.kind === 'empathy')).toEqual([]);
  });

  it('looks back only a few minutes after a long gap, and says when 공감 span posts', async () => {
    await repo.saveToken(A, TA, 'ios');
    for (const t of ['empathies', 'follows', 'posts']) await sql(`UPDATE ${t} SET created_at = created_at - interval '1 hour'`);
    // As if A signed out a week ago and just came back.
    await sql(`UPDATE users SET push_checked_at = now() - interval '7 days' WHERE id = $1`, [A]);
    const post = async (body: string) =>
      (
        await sql(
          `INSERT INTO posts (author_id, body, lang, typing_ms, local_date, created_at) VALUES ($1, $2, 'ko', 60000, current_date, now() - interval '3 days') RETURNING id::text`,
          [A, body],
        )
      ).rows[0].id as string;
    const [p1, p2, old] = [await post('첫 생각'), await post('둘째 생각'), await post('오래된 생각')];
    await sql(`INSERT INTO empathies (post_id, user_id, created_at) VALUES ($1, $2, now() - interval '2 days')`, [old, B]);
    await sql(`INSERT INTO empathies (post_id, user_id, created_at) VALUES ($1, $2, ${ago}), ($3, $4, ${ago})`, [p1, B, p2, C]);

    const [b, ...rest] = (await repo.takeBatches()).filter((x) => x.userId === A);
    expect(rest).toEqual([]);
    expect([b!.kind, b!.count, b!.manyPosts]).toEqual(['empathy', 2, true]);
  });

  it('does not alert twice when a 공감 or follow is undone and done again, and counts unread for the icon', async () => {
    await repo.saveToken(A, TA, 'ios');
    for (const t of ['empathies', 'follows', 'posts']) await sql(`UPDATE ${t} SET created_at = created_at - interval '1 hour'`);
    await sql(`UPDATE users SET notifications_seen_at = now() - interval '2 minutes' WHERE id = $1`, [A]);
    const p = (
      await sql(
        `INSERT INTO posts (author_id, body, lang, typing_ms, local_date, created_at) VALUES ($1, '다시 누른 생각', 'ko', 60000, current_date, now() - interval '1 day') RETURNING id::text`,
        [A],
      )
    ).rows[0].id as string;
    await sql(`DELETE FROM follows WHERE follower_id = $1 AND followee_id = $2`, [C, A]);
    await rewind();
    await sql(`INSERT INTO empathies (post_id, user_id, created_at) VALUES ($1, $2, ${ago})`, [p, C]);
    await sql(`INSERT INTO follows (follower_id, followee_id, created_at) VALUES ($1, $2, ${ago})`, [C, A]);
    expect((await repo.takeBatches()).filter((b) => b.userId === A).map((b) => b.kind).sort()).toEqual(['empathy', 'follow']);
    expect((await repo.unread([A])).get(A)).toBe(2);

    await sql(`DELETE FROM empathies WHERE post_id = $1 AND user_id = $2`, [p, C]);
    await sql(`DELETE FROM follows WHERE follower_id = $1 AND followee_id = $2`, [C, A]);
    await rewind();
    await sql(`INSERT INTO empathies (post_id, user_id, created_at) VALUES ($1, $2, ${ago})`, [p, C]);
    await sql(`INSERT INTO follows (follower_id, followee_id, created_at) VALUES ($1, $2, ${ago})`, [C, A]);
    expect((await repo.takeBatches()).filter((b) => b.userId === A)).toEqual([]);

    // A day later the same 공감 is news again.
    await sql(`UPDATE push_sent SET at = at - interval '2 days'`);
    await sql(`UPDATE follows SET created_at = created_at - interval '1 hour'`);
    await sql(`DELETE FROM empathies WHERE post_id = $1 AND user_id = $2`, [p, C]);
    await rewind();
    await sql(`INSERT INTO empathies (post_id, user_id, created_at) VALUES ($1, $2, ${ago})`, [p, C]);
    expect((await repo.takeBatches()).filter((b) => b.userId === A).map((b) => b.kind)).toEqual(['empathy']);
  });

  it('forgets tokens in bulk', async () => {
    await repo.removeTokens([TA, TB]);
    expect((await repo.tokens([A, B])).size).toBe(0);
  });
});
