import { fileURLToPath } from 'node:url';
import type { RDSDataClient } from '@aws-sdk/client-rds-data';
import pg from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { loadMigrations, migrate, type MigrationDb } from '../src/db/migrate.js';
import { AuroraGrowthRepository } from '../src/services/growthRepository.js';
import { PgDataApi } from './pgDataApi.js';

/**
 * The growth queries against Postgres with pgvector, through the Data API
 * stand-in. Runs when TEST_DATABASE_URL is set, in a schema of its own.
 */
const url = process.env.TEST_DATABASE_URL;
const A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const C = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const ADMIN = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

describe.skipIf(!url)('AuroraGrowthRepository on Postgres', () => {
  let client: pg.Client;
  let repo: AuroraGrowthRepository;
  const sql = (text: string, values: unknown[] = []) => client.query(text, values);
  const post = async (author: string, body: string, opts: { empathies?: string[]; score?: number; ago?: string } = {}) => {
    const r = await sql(
      `INSERT INTO posts (author_id, body, lang, typing_ms, local_date, thought_score, created_at)
       VALUES ($1, $2, 'ko', 90000, current_date, $3, now() - $4::interval) RETURNING id::text`,
      [author, body, opts.score ?? 70, opts.ago ?? '1 hour'],
    );
    const id = r.rows[0].id as string;
    for (const u of opts.empathies ?? []) await sql(`INSERT INTO empathies (post_id, user_id) VALUES ($1, $2)`, [id, u]);
    return id;
  };

  beforeAll(async () => {
    client = new pg.Client({ connectionString: url });
    await client.connect();
    const schema = `g_${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
    await client.query(`CREATE SCHEMA ${schema}`);
    await client.query(`SET search_path TO ${schema}, public`);
    const db: MigrationDb = {
      begin: async () => (await client.query('BEGIN'), 'tx'),
      exec: async (s) => (await client.query({ text: s, rowMode: 'array' })).rows,
      commit: async () => void (await client.query('COMMIT')),
      rollback: async () => void (await client.query('ROLLBACK')),
    };
    await migrate(db, loadMigrations(fileURLToPath(new URL('../src/db/migrations', import.meta.url))));
    repo = new AuroraGrowthRepository('arn:cluster', 'arn:secret', 'test', new PgDataApi(client) as unknown as RDSDataClient);
    for (const [id, handle] of [[A, 'aa'], [B, 'bb'], [C, 'cc'], [ADMIN, 'admin']] as const) {
      expect(await repo.saveProfile(id, { handle, displayName: `${handle} name`, bio: '', locale: 'ko', timeZone: 'Asia/Seoul' })).toBe('ok');
    }
  });
  afterAll(async () => {
    await client?.end();
  });

  it('keeps sharing off until the writer turns it on', async () => {
    expect(await repo.sharing(A)).toEqual({ shareOk: false, anonymous: false });
    expect(await repo.setSharing(A, { shareOk: true, anonymous: false })).toBe(true);
    expect(await repo.sharing(A)).toEqual({ shareOk: true, anonymous: false });
    expect(await repo.sharing('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee')).toBeNull();
  });

  it('shows a post publicly only with consent, and not once excluded', async () => {
    const pa = await post(A, '창문을 열고 바람 소리를 듣는 아침', { empathies: [B] });
    const pb = await post(B, '아무도 모르게 쓴 생각');
    expect(await repo.publicPost(pa)).toMatchObject({ body: '창문을 열고 바람 소리를 듣는 아침', authorName: 'aa name', empathyCount: 1 });
    expect(await repo.publicPost(pb)).toBeNull();
    expect((await repo.publicPostIds(10)).map((p) => p.id)).toEqual([pa]);

    await repo.setSharing(A, { shareOk: true, anonymous: true });
    expect((await repo.publicPost(pa))?.authorName).toBeNull();

    expect(await repo.setPostExcluded(B, pa, true)).toBe(false); // not B's post
    expect(await repo.setPostExcluded(A, pa, true)).toBe(true);
    expect(await repo.publicPost(pa)).toBeNull();
    await repo.setPostExcluded(A, pa, false);
    await repo.setSharing(A, { shareOk: true, anonymous: false });
  });

  it('gives each person one stable invite code and resolves codes without case', async () => {
    const code = await repo.inviteCode(A);
    expect(code).toMatch(/^[A-Z0-9]{8}$/);
    expect(await repo.inviteCode(A)).toBe(code);
    expect(await repo.resolveCode(code!.toLowerCase())).toEqual({ code, channel: 'invite', referrerId: A });
    expect(await repo.resolveCode('WEB-POST')).toEqual({ code: 'web-post', channel: 'web', referrerId: null });
    expect(await repo.resolveCode('nothing')).toBeNull();
  });

  it('records where someone came from once, never their own code, and only in the first day', async () => {
    const code = (await repo.inviteCode(A))!;
    expect(await repo.recordSource(A, code)).toBe('self');
    expect(await repo.recordSource(B, 'nope-123')).toBe('unknown_code');
    expect(await repo.recordSource(B, code)).toBe('ok');
    expect(await repo.recordSource(B, 'web-post')).toBe('already');
    await sql(`UPDATE users SET created_at = now() - interval '3 days' WHERE id = $1`, [C]);
    expect(await repo.recordSource(C, code)).toBe('too_late');
    await sql(`UPDATE users SET created_at = now() WHERE id = $1`, [C]);
    await repo.recordClick(code, 'ios');
  });

  it('shows the approved question for the reader’s own day', async () => {
    expect(await repo.todayQuestion(A)).toBeNull();
    const today = new Date(Date.now() + 9 * 3600_000).toISOString().slice(0, 10);
    const q = await repo.saveQuestion(ADMIN, { day: today, textKo: '오늘 웃은 일은?', textEn: 'What made you smile?', approve: false });
    expect(q.status).toBe('draft');
    expect(await repo.todayQuestion(A)).toBeNull();
    await repo.saveQuestion(ADMIN, { day: today, textKo: '오늘 웃은 일은?', textEn: 'What made you smile?', approve: true });
    expect((await repo.todayQuestion(A))?.textKo).toBe('오늘 웃은 일은?');
    expect((await repo.questions(today, 10)).map((x) => x.status)).toEqual(['approved']);
  });

  it('drafts questions only for days that have none', async () => {
    const today = new Date(Date.now() + 9 * 3600_000).toISOString().slice(0, 10);
    const missing = await repo.daysWithoutQuestion(today, 3);
    expect(missing).toHaveLength(2);
    await repo.addQuestionDrafts(missing.map((day) => ({ day, textKo: `질문 ${day}`, textEn: `Q ${day}` })));
    expect(await repo.daysWithoutQuestion(today, 3)).toEqual([]);
    expect(await repo.recentQuestions(1)).toEqual([`질문 ${missing[1]}`]);
  });

  it('picks the best shareable post per writer, skipping reported ones, and queues it once', async () => {
    await repo.setSharing(C, { shareOk: true, anonymous: false });
    const low = await post(C, '복사한 것 같은 글', { score: 10 });
    const good = await post(C, '오늘 처음으로 혼자 영화를 봤다', { empathies: [A, B] });
    const reported = await post(B, '신고된 생각');
    await repo.setSharing(B, { shareOk: true, anonymous: false });
    await sql(`INSERT INTO reports (reporter_id, user_id, post_id, reason) VALUES ($1, $2, $3, 'spam')`, [A, B, reported]);

    const picked = await repo.candidates(10);
    const ids = picked.map((p) => p.postId);
    expect(ids).toContain(good);
    expect(ids).not.toContain(low);
    expect(ids).not.toContain(reported);
    // One per writer: A has a post too.
    expect(new Set(picked.map((p) => p.body)).size).toBe(picked.length);

    for (const c of picked) await repo.addItem(c, `캡션 ${c.postId}`, `p-${c.postId.slice(0, 6)}`);
    // Featured once, and a writer at most once in two weeks.
    expect(await repo.candidates(10)).toEqual([]);
    const items = await repo.promoItems(['pending'], 10);
    expect(items.map((i) => i.postId).sort()).toEqual(ids.sort());
    expect(items.find((i) => i.postId === good)?.post).toMatchObject({ authorHandle: 'cc', empathyCount: 2 });
  });

  it('approves with a card and a time, then posts when due', async () => {
    const [item] = await repo.promoItems(['pending'], 1);
    expect(await repo.decidePromo(item!.id, ADMIN, { approve: true, cardKey: 'photos/promo/x.png', caption: '새 캡션' })).toBe(true);
    let [approved] = await repo.promoItems(['approved'], 1);
    expect(approved).toMatchObject({ caption: '새 캡션', cardKey: 'photos/promo/x.png' });
    expect(new Date(approved!.scheduledFor!).getUTCHours()).toBe(12);
    expect(await repo.due(10)).toEqual([]);

    await repo.decidePromo(item!.id, ADMIN, { approve: true, scheduledFor: new Date(Date.now() - 60_000).toISOString() });
    const [due] = await repo.due(10);
    expect(due).toMatchObject({ id: item!.id, caption: '새 캡션', cardKey: 'photos/promo/x.png', posted: {} });

    await repo.markPosted(item!.id, { threads: 't1' }, 'instagram: 400');
    [approved] = await repo.promoItems(['failed'], 1);
    expect(approved).toMatchObject({ posted: { threads: 't1' }, error: 'instagram: 400' });
    await repo.decidePromo(item!.id, ADMIN, { approve: true, scheduledFor: new Date(Date.now() - 60_000).toISOString() });
    expect((await repo.due(10))[0]?.posted).toEqual({ threads: 't1' });
    await repo.markPosted(item!.id, { threads: 't1', instagram: 'i1' }, null);
    expect((await repo.promoItems(['posted'], 5)).map((i) => i.id)).toEqual([item!.id]);

    const actions = (await repo.audit(10)).map((a) => a.action);
    expect(actions).toContain('promo_approve');
    expect((await repo.audit(10))[0]?.adminHandle).toBe('admin');
  });

  it('withdraws items when consent goes, marking posted ones for takedown', async () => {
    const before = await repo.promoItems(['pending', 'posted'], 10);
    const posted = before.find((i) => i.status === 'posted')!;
    const owner = await sql(`SELECT author_id::text FROM posts WHERE id = $1`, [posted.postId]);
    await repo.setSharing(owner.rows[0].author_id, { shareOk: false, anonymous: false });
    const cards = await repo.withdrawUnshareable();
    expect(cards).toEqual(['photos/promo/x.png']);
    const after = await repo.promoItems(['takedown'], 10);
    expect(after.map((i) => i.id)).toEqual([posted.id]);
    expect(after[0]!.cardKey).toBeNull();
    expect(await repo.withdrawUnshareable()).toEqual([]);
    expect(await repo.markPromo(posted.id, ADMIN, 'withdrawn')).toBe(true);
  });

  it('counts the dashboard by Korean day, with retention and sources', async () => {
    const d = await repo.dashboard(7);
    expect(d.days).toHaveLength(7);
    const today = d.days.at(-1)!;
    expect(today.signups).toBeGreaterThanOrEqual(3);
    expect(today.posts).toBeGreaterThanOrEqual(5);
    expect(today.activePeople).toBeGreaterThanOrEqual(2);
    expect(d.retention.d1).toEqual({ rate: null, cohort: 0 });
    expect(d.sources.find((s) => s.channel === 'invite')).toEqual({ channel: 'invite', signups: 1, active7: 0 });
    expect(d.sources.find((s) => s.channel === 'direct')?.signups).toBe(3);
  });

  it('lists link codes with clicks and sign-ups, and refuses a taken code', async () => {
    expect(await repo.createLinkCode(ADMIN, 'disquiet', 'community', '디스콰이엇 런칭')).toBe('ok');
    expect(await repo.createLinkCode(ADMIN, 'disquiet', 'community', '')).toBe('taken');
    await repo.recordClick('disquiet', 'web');
    const stats = await repo.linkStats(50);
    expect(stats.find((s) => s.code === 'disquiet')).toMatchObject({ channel: 'community', label: '디스콰이엇 런칭', clicks: 1, signups: 0 });
    expect(stats.find((s) => s.channel === 'invite')).toMatchObject({ code: '*', clicks: 1, signups: 1 });
  });

  it('goes with the account: sources, and the referrer link', async () => {
    expect(await repo.deleteAccount(B)).not.toBe(false);
    expect((await sql(`SELECT count(*)::int AS n FROM signup_sources WHERE user_id = $1`, [B])).rows[0].n).toBe(0);
    // A deleted writer's queued item is withdrawn on the next run instead of disappearing.
    const [pending] = await repo.promoItems(['pending'], 1);
    const owner = (await sql(`SELECT author_id::text FROM posts WHERE id = $1`, [pending!.postId])).rows[0].author_id;
    expect(await repo.deleteAccount(owner)).not.toBe(false);
    await repo.withdrawUnshareable();
    const gone = (await repo.promoItems(['withdrawn'], 20)).find((i) => i.id === pending!.id);
    expect(gone?.post).toBeNull();
  });
});
