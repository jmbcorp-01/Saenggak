import {
  ExecuteStatementCommand,
  RDSDataClient,
  type Field,
  type SqlParameter,
} from '@aws-sdk/client-rds-data';
import type { Phrase } from '../rules/phrases.js';
import type {
  FeedOptions,
  FeedPost,
  FollowResult,
  NewPost,
  PostState,
  PostUpdate,
  Profile,
  ProfileInput,
  Repository,
} from './ports.js';

type Param = string | number | boolean | null;

function toParam(name: string, value: Param): SqlParameter {
  if (value === null) return { name, value: { isNull: true } };
  if (typeof value === 'number') {
    return Number.isInteger(value)
      ? { name, value: { longValue: value } }
      : { name, value: { doubleValue: value } };
  }
  if (typeof value === 'boolean') return { name, value: { booleanValue: value } };
  return { name, value: { stringValue: value } };
}

function fieldValue(f: Field | undefined): unknown {
  if (!f || f.isNull) return null;
  return f.stringValue ?? f.longValue ?? f.doubleValue ?? f.booleanValue ?? null;
}

/** Aurora PostgreSQL through the RDS Data API (no connection pool in Lambda). */
export class AuroraRepository implements Repository {
  constructor(
    private readonly resourceArn = process.env.DB_CLUSTER_ARN!,
    private readonly secretArn = process.env.DB_SECRET_ARN!,
    private readonly database = process.env.DB_NAME ?? 'saenggak',
    private readonly client = new RDSDataClient({}),
  ) {}

  protected async query(sql: string, params: Record<string, Param> = {}): Promise<Record<string, unknown>[]> {
    const out = await this.client.send(
      new ExecuteStatementCommand({
        resourceArn: this.resourceArn,
        secretArn: this.secretArn,
        database: this.database,
        sql,
        parameters: Object.entries(params).map(([k, v]) => toParam(k, v)),
        includeResultMetadata: true,
      }),
    );
    const names = (out.columnMetadata ?? []).map((c) => c.name ?? '');
    return (out.records ?? []).map((row) =>
      Object.fromEntries(row.map((f, k) => [names[k] ?? String(k), fieldValue(f)])),
    );
  }

  async insertPost(p: NewPost): Promise<string> {
    // One statement, so a post never exists without its typing session.
    const rows = await this.query(
      `WITH post AS (
         INSERT INTO posts (author_id, body, lang, typing_ms, local_date, status, blocked_reason, embedding)
         VALUES (:author::uuid, :body, :lang, :typing, :day::date, :status, :reason,
                 CAST(CAST(:emb AS text) AS vector))
         RETURNING id
       ), s AS (
         INSERT INTO typing_sessions (post_id, session, issues)
         SELECT id, :session::jsonb, string_to_array(:issues, ',') FROM post
       )
       SELECT id::text FROM post`,
      {
        author: p.authorId,
        body: p.body,
        lang: p.lang,
        typing: p.typingMs,
        day: p.localDate,
        status: p.status,
        reason: p.blockedReason ?? null,
        emb: p.embedding ? JSON.stringify(p.embedding) : null,
        session: JSON.stringify(p.session),
        issues: p.issues.join(','),
      },
    );
    return rows[0]?.id as string;
  }

  async localDate(authorId: string): Promise<string | null> {
    const rows = await this.query(
      `SELECT to_char(now() AT TIME ZONE time_zone, 'YYYY-MM-DD') AS d FROM users WHERE id = :a::uuid`,
      { a: authorId },
    );
    return (rows[0]?.d as string | undefined) ?? null;
  }

  async recordWrite(authorId: string, limit: number): Promise<boolean> {
    const rows = await this.query(
      `INSERT INTO write_log (author_id)
       SELECT :a::uuid
       WHERE (SELECT count(*) FROM write_log
              WHERE author_id = :a::uuid AND at > now() - interval '1 hour') < :lim
       RETURNING 1 AS ok`,
      { a: authorId, lim: limit },
    );
    return rows.length > 0;
  }

  async countSimilarAuthors(postId: string, embedding: number[], maxDistance: number): Promise<number> {
    const rows = await this.query(
      // ORDER BY distance with LIMIT lets the HNSW index do the search; a plain
      // distance filter would scan every post.
      `SELECT count(DISTINCT near.author_id) AS n
       FROM (
         SELECT p.author_id, p.embedding <=> :emb::vector AS dist
         FROM posts p
         WHERE p.status = 'published' AND p.id <> :id::uuid
         ORDER BY p.embedding <=> :emb::vector
         LIMIT 500
       ) near, posts me
       WHERE me.id = :id::uuid AND near.author_id <> me.author_id AND near.dist <= :maxd`,
      { id: postId, emb: JSON.stringify(embedding), maxd: maxDistance },
    );
    return Number(rows[0]?.n ?? 0);
  }

  async claimPhrases(postId: string, authorId: string, phrases: Phrase[]): Promise<Phrase[]> {
    if (phrases.length === 0) return [];
    const rows = await this.query(
      `INSERT INTO phrase_firsts (phrase_key, post_id, author_id, shown_text)
       SELECT x.key, :post::uuid, :author::uuid, x.text
       FROM jsonb_to_recordset(:items::jsonb) AS x(key text, text text)
       ON CONFLICT (phrase_key) DO NOTHING
       RETURNING phrase_key`,
      { post: postId, author: authorId, items: JSON.stringify(phrases.map(({ key, text }) => ({ key, text }))) },
    );
    const won = new Set(rows.map((r) => r.phrase_key as string));
    return phrases.filter((p) => won.has(p.key));
  }

  async hasPublished(n: number): Promise<boolean> {
    const rows = await this.query(
      `SELECT count(*) AS c FROM (SELECT 1 FROM posts WHERE status = 'published' LIMIT :n) x`,
      { n },
    );
    return Number(rows[0]?.c ?? 0) >= n;
  }

  async writingDays(authorId: string): Promise<number> {
    const rows = await this.query(`SELECT days FROM writing_days WHERE author_id = :a::uuid`, { a: authorId });
    return Number(rows[0]?.days ?? 0);
  }

  async recentBlocks(authorId: string, windowDays: number): Promise<number> {
    const rows = await this.query(
      `SELECT count(*) AS n FROM posts
       WHERE author_id = :a::uuid AND status = 'blocked'
         AND blocked_reason IS DISTINCT FROM 'classifier_declined'
         AND created_at > now() - make_interval(days => CAST(:d AS integer))`,
      { a: authorId, d: windowDays },
    );
    return Number(rows[0]?.n ?? 0);
  }

  async writingDaysSinceLoss(authorId: string): Promise<number | null> {
    const rows = await this.query(
      `SELECT l.lost_at IS NOT NULL AS lost,
              (SELECT count(DISTINCT local_date) FROM posts
                WHERE author_id = :a::uuid AND status = 'published' AND created_at > l.lost_at) AS days
       FROM (SELECT max(lost_at) AS lost_at FROM follow_losses WHERE author_id = :a::uuid) l`,
      { a: authorId },
    );
    return rows[0]?.lost ? Number(rows[0]?.days ?? 0) : null;
  }

  async setFollowUnlocked(authorId: string, unlocked: boolean): Promise<void> {
    const changed = await this.query(
      `UPDATE users SET follow_unlocked = :u
       WHERE id = :a::uuid AND follow_unlocked <> :u RETURNING id`,
      { a: authorId, u: unlocked },
    );
    if (changed.length === 0) return;
    if (!unlocked) {
      await this.query(`INSERT INTO follow_losses (author_id) VALUES (:a::uuid)`, { a: authorId });
    }
    await this.query(
      `UPDATE follows SET hidden = :h WHERE follower_id = :a::uuid OR followee_id = :a::uuid`,
      { a: authorId, h: !unlocked },
    );
  }

  async toggleEmpathy(postId: string, userId: string) {
    const removed = await this.query(
      `DELETE FROM empathies WHERE post_id = :p::uuid AND user_id = :u::uuid RETURNING post_id`,
      { p: postId, u: userId },
    );
    if (removed.length === 0) {
      // ON CONFLICT: a double tap can send two requests at once; both end empathized.
      const added = await this.query(
        `WITH target AS (
           SELECT id FROM posts WHERE id = :p::uuid AND status = 'published' AND author_id <> :u::uuid
         ), ins AS (
           INSERT INTO empathies (post_id, user_id) SELECT id, :u::uuid FROM target
           ON CONFLICT DO NOTHING
         )
         SELECT 1 AS ok FROM target`,
        { p: postId, u: userId },
      );
      if (added.length === 0) return null;
    }
    const rows = await this.query(`SELECT count(*) AS n FROM empathies WHERE post_id = :p::uuid`, { p: postId });
    return { empathized: removed.length === 0, count: Number(rows[0]?.n ?? 0) };
  }

  async feed(viewerId: string, opts: FeedOptions): Promise<FeedPost[]> {
    const rows = await this.query(
      `SELECT p.id::text, p.author_id::text, u.handle, u.display_name, u.photo_key,
              p.body, p.lang, p.typing_ms, p.created_at::text, p.edited_at::text,
              (SELECT count(*) FROM empathies e WHERE e.post_id = p.id) AS empathy_count,
              EXISTS (SELECT 1 FROM empathies e WHERE e.post_id = p.id AND e.user_id = :v::uuid) AS mine
       FROM posts p JOIN users u ON u.id = p.author_id
       WHERE p.status = 'published' AND u.suspended_at IS NULL
         AND (CAST(:before AS text) IS NULL OR p.created_at < CAST(:before AS timestamptz))
         AND (NOT :following OR EXISTS (
               SELECT 1 FROM follows f
               WHERE f.follower_id = :v::uuid AND f.followee_id = p.author_id AND NOT f.hidden))
         AND (CAST(:author AS text) IS NULL OR p.author_id = CAST(:author AS uuid))
       ORDER BY p.created_at DESC
       LIMIT :limit`,
      { v: viewerId, before: opts.before ?? null, following: opts.following, author: opts.authorId ?? null, limit: opts.limit },
    );
    return rows.map((r) => ({
      id: r.id as string,
      authorId: r.author_id as string,
      authorHandle: r.handle as string,
      authorName: r.display_name as string,
      photoKey: (r.photo_key as string | null) ?? null,
      body: r.body as string,
      lang: r.lang as string,
      typingMs: Number(r.typing_ms),
      empathyCount: Number(r.empathy_count),
      empathizedByMe: Boolean(r.mine),
      createdAt: r.created_at as string,
      editedAt: (r.edited_at as string | null) ?? null,
    }));
  }

  async cachedTranslation(postId: string, lang: string): Promise<string | null> {
    const rows = await this.query(
      `SELECT body FROM translations WHERE post_id = :p::uuid AND target_lang = :l`,
      { p: postId, l: lang },
    );
    return (rows[0]?.body as string | undefined) ?? null;
  }

  async saveTranslation(postId: string, lang: string, body: string): Promise<void> {
    await this.query(
      `INSERT INTO translations (post_id, target_lang, body) VALUES (:p::uuid, :l, :b)
       ON CONFLICT (post_id, target_lang) DO NOTHING`,
      { p: postId, l: lang, b: body },
    );
  }

  async postState(postId: string): Promise<PostState | null> {
    const rows = await this.query(
      `SELECT author_id::text, body, status, (SELECT count(*) FROM empathies e WHERE e.post_id = p.id) AS n
       FROM posts p WHERE id = :p::uuid AND status <> 'deleted'`,
      { p: postId },
    );
    const r = rows[0];
    if (!r) return null;
    return {
      authorId: r.author_id as string,
      body: r.body as string,
      status: r.status as PostState['status'],
      empathyCount: Number(r.n),
    };
  }

  async updatePost(postId: string, authorId: string, u: PostUpdate): Promise<boolean> {
    // One statement, so a 공감 arriving mid-edit either blocks the edit or comes after it.
    const rows = await this.query(
      `WITH updated AS (
         UPDATE posts SET body = :body, lang = :lang, typing_ms = typing_ms + CAST(:typing AS integer),
                embedding = :emb::vector, edited_at = now()
         WHERE id = :p::uuid AND author_id = :a::uuid AND status = 'published'
           AND NOT EXISTS (SELECT 1 FROM empathies e WHERE e.post_id = posts.id)
         RETURNING id
       ), t AS (
         DELETE FROM translations WHERE post_id IN (SELECT id FROM updated)
       ), f AS (
         DELETE FROM phrase_firsts WHERE post_id IN (SELECT id FROM updated)
       ), s AS (
         UPDATE typing_sessions SET session = :session::jsonb WHERE post_id IN (SELECT id FROM updated)
       )
       SELECT id::text FROM updated`,
      {
        p: postId,
        a: authorId,
        body: u.body,
        lang: u.lang,
        typing: u.typingMs,
        emb: JSON.stringify(u.embedding),
        session: JSON.stringify(u.session),
      },
    );
    return rows.length > 0;
  }

  async deletePost(postId: string, authorId: string): Promise<boolean> {
    const rows = await this.query(
      `DELETE FROM posts WHERE id = :p::uuid AND author_id = :a::uuid AND status = 'published' RETURNING id`,
      { p: postId, a: authorId },
    );
    return rows.length > 0;
  }

  async deleteAccount(userId: string): Promise<{ photoKey: string | null } | false> {
    // One statement: foreign keys are checked at its end, after every row is gone.
    const rows = await this.query(
      `WITH me AS (SELECT id, photo_key FROM users WHERE id = :u::uuid FOR UPDATE),
       mine AS (SELECT id FROM posts WHERE author_id IN (SELECT id FROM me)),
       e AS (DELETE FROM empathies WHERE user_id IN (SELECT id FROM me) OR post_id IN (SELECT id FROM mine)),
       f AS (DELETE FROM follows WHERE follower_id IN (SELECT id FROM me) OR followee_id IN (SELECT id FROM me)),
       ph AS (DELETE FROM phrase_firsts WHERE author_id IN (SELECT id FROM me)),
       t AS (DELETE FROM translations WHERE post_id IN (SELECT id FROM mine)),
       s AS (DELETE FROM typing_sessions WHERE post_id IN (SELECT id FROM mine)),
       l AS (DELETE FROM follow_losses WHERE author_id IN (SELECT id FROM me)),
       w AS (DELETE FROM write_log WHERE author_id IN (SELECT id FROM me)),
       p AS (DELETE FROM posts WHERE id IN (SELECT id FROM mine)),
       u AS (DELETE FROM users WHERE id IN (SELECT id FROM me))
       SELECT photo_key FROM me`,
      { u: userId },
    );
    if (rows.length === 0) return false;
    return { photoKey: (rows[0]!.photo_key as string | null) ?? null };
  }

  async isSuspended(userId: string): Promise<boolean> {
    const rows = await this.query(`SELECT suspended_at IS NOT NULL AS s FROM users WHERE id = :u::uuid`, { u: userId });
    return Boolean(rows[0]?.s);
  }

  async setPhoto(userId: string, photoKey: string): Promise<{ previous: string | null } | null> {
    const rows = await this.query(
      `UPDATE users u SET photo_key = :k
       FROM (SELECT id, photo_key FROM users WHERE id = :u::uuid FOR UPDATE) old
       WHERE u.id = old.id
       RETURNING old.photo_key AS previous`,
      { u: userId, k: photoKey },
    );
    if (rows.length === 0) return null;
    return { previous: (rows[0]!.previous as string | null) ?? null };
  }

  async saveProfile(userId: string, i: ProfileInput): Promise<'ok' | 'handle_taken'> {
    const taken = await this.query(
      `SELECT 1 FROM users WHERE lower(handle) = lower(:h) AND id <> :u::uuid`,
      { h: i.handle, u: userId },
    );
    if (taken.length > 0) return 'handle_taken';
    try {
      await this.query(
        `INSERT INTO users (id, handle, display_name, bio, locale, time_zone)
         VALUES (:u::uuid, :h, :n, :b, :l, :tz)
         ON CONFLICT (id) DO UPDATE SET handle = EXCLUDED.handle, display_name = EXCLUDED.display_name,
           bio = EXCLUDED.bio, locale = EXCLUDED.locale, time_zone = EXCLUDED.time_zone`,
        { u: userId, h: i.handle, n: i.displayName, b: i.bio, l: i.locale, tz: i.timeZone },
      );
    } catch (e) {
      // Another sign-up took the handle between the check and the insert.
      if (/users_handle|duplicate key/i.test(String(e))) return 'handle_taken';
      throw e;
    }
    return 'ok';
  }

  async profile(userId: string, viewerId: string): Promise<(Profile & { followedByMe: boolean }) | null> {
    const rows = await this.query(
      `SELECT u.id::text, u.handle, u.display_name, u.bio, u.photo_key, u.locale, u.time_zone, u.follow_unlocked,
              coalesce(w.days, 0) AS days,
              (SELECT count(*) FROM follows f WHERE f.followee_id = u.id AND NOT f.hidden) AS followers,
              (SELECT count(*) FROM follows f WHERE f.follower_id = u.id AND NOT f.hidden) AS following,
              EXISTS (SELECT 1 FROM follows f
                      WHERE f.follower_id = :v::uuid AND f.followee_id = u.id AND NOT f.hidden) AS mine
       FROM users u LEFT JOIN writing_days w ON w.author_id = u.id
       WHERE u.id = :u::uuid`,
      { u: userId, v: viewerId },
    );
    const r = rows[0];
    if (!r) return null;
    return {
      id: r.id as string,
      handle: r.handle as string,
      displayName: r.display_name as string,
      bio: r.bio as string,
      photoKey: (r.photo_key as string | null) ?? null,
      locale: r.locale as string,
      timeZone: r.time_zone as string,
      writingDays: Number(r.days),
      followUnlocked: Boolean(r.follow_unlocked),
      followers: Number(r.followers),
      following: Number(r.following),
      followedByMe: Boolean(r.mine),
    };
  }

  async follow(followerId: string, followeeId: string): Promise<FollowResult> {
    if (followerId === followeeId) return 'self';
    const rows = await this.query(
      `SELECT id::text, follow_unlocked FROM users WHERE id IN (:a::uuid, :b::uuid)`,
      { a: followerId, b: followeeId },
    );
    const followee = rows.find((r) => r.id === followeeId);
    const follower = rows.find((r) => r.id === followerId);
    if (!followee) return 'not_found';
    if (!follower?.follow_unlocked || !followee.follow_unlocked) return 'not_allowed';
    await this.query(
      `INSERT INTO follows (follower_id, followee_id) VALUES (:a::uuid, :b::uuid) ON CONFLICT DO NOTHING`,
      { a: followerId, b: followeeId },
    );
    return 'ok';
  }

  async unfollow(followerId: string, followeeId: string): Promise<void> {
    await this.query(`DELETE FROM follows WHERE follower_id = :a::uuid AND followee_id = :b::uuid`, {
      a: followerId,
      b: followeeId,
    });
  }
}
