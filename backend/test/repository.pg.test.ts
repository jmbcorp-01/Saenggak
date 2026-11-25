import { readFileSync } from 'node:fs';
import type { RDSDataClient } from '@aws-sdk/client-rds-data';
import pg from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { deletePost, editPost, publishPost } from '../src/posts/publish.js';
import { MAX_COSINE_DISTANCE } from '../src/rules/similar.js';
import { AuroraRepository } from '../src/services/repository.js';
import { humanSession } from './helpers.js';
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
    },
    embedder: { embed: async () => nextVec },
  });
  const input = (authorId: string, text = TEXT, localDate = '2026-11-25') => ({
    authorId,
    text,
    session: humanSession(text),
    localDate,
  });

  beforeAll(async () => {
    client = new pg.Client({ connectionString: url });
    await client.connect();
    const schema = `t_${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
    await client.query(`CREATE SCHEMA ${schema}`);
    await client.query(`SET search_path TO ${schema}, public`);
    await client.query(readFileSync(new URL('../src/db/schema.sql', import.meta.url), 'utf8'));
    repo = new AuroraRepository('arn:cluster', 'arn:secret', 'test', new PgDataApi(client) as unknown as RDSDataClient);
    for (const [id, handle] of [[A, 'aa'], [B, 'bb'], [C, 'cc']] as const) {
      const saved = await repo.saveProfile(id, { handle, displayName: handle, bio: '', locale: 'ko', timeZone: 'Asia/Seoul' });
      expect(saved).toBe('ok');
    }
  });
  afterAll(async () => client?.end());

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

    const edited = await editPost(deps(), { ...input(A, EDITED), postId: id });
    expect(edited.kind).toBe('published');
    expect(await repo.cachedTranslation(id, 'en')).toBeNull();
    const [after] = await repo.feed(C, { following: false, authorId: A, limit: 1 });
    expect(after!.body).toBe(EDITED);
    expect(after!.editedAt).not.toBeNull();

    expect(await repo.toggleEmpathy(id, C)).toEqual({ empathized: true, count: 1 });
    expect(await editPost(deps(), { ...input(A, TEXT), postId: id })).toEqual({ kind: 'locked' });
    expect(await repo.toggleEmpathy(id, A)).toBeNull();
  });

  it('frees the phrases of a deleted post', async () => {
    const [post] = await repo.feed(C, { following: false, authorId: B, limit: 1 });
    expect(await deletePost(repo, post!.id, A)).toBe(false);
    expect(await deletePost(repo, post!.id, B)).toBe(true);
    const again = await publishPost(deps(), input(C));
    expect(again.kind === 'published' && again.firstPhrases.length).toBeGreaterThan(0);
  });

  it('follows with permission and hides follows after 3 blocks', async () => {
    for (let d = 1; d <= 10; d++) {
      for (const who of [A, B]) await publishPost(deps(), input(who, TEXT, `2026-10-${String(d).padStart(2, '0')}`));
    }
    expect((await repo.profile(A, A))?.followUnlocked).toBe(true);
    expect(await repo.follow(A, C)).toBe('not_allowed');
    expect(await repo.follow(A, B)).toBe('ok');
    expect((await repo.feed(A, { following: true, limit: 30 })).length).toBeGreaterThan(0);
    expect(await repo.profile(B, A)).toMatchObject({ followers: 1, followedByMe: true });

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
});
