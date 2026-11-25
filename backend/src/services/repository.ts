import {
  ExecuteStatementCommand,
  RDSDataClient,
  type Field,
  type SqlParameter,
} from '@aws-sdk/client-rds-data';
import type { Phrase } from '../rules/phrases.js';
import type { FeedPost, NewPost, Repository } from './ports.js';

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

  private async query(sql: string, params: Record<string, Param> = {}): Promise<Record<string, unknown>[]> {
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
    const rows = await this.query(
      `INSERT INTO posts (author_id, body, lang, typing_ms, local_date, status, blocked_reason, embedding)
       VALUES (:author::uuid, :body, :lang, :typing, :day::date, :status, :reason,
               CASE WHEN :emb IS NULL THEN NULL ELSE :emb::vector END)
       RETURNING id::text`,
      {
        author: p.authorId,
        body: p.body,
        lang: p.lang,
        typing: p.typingMs,
        day: p.localDate,
        status: p.status,
        reason: p.blockedReason ?? null,
        emb: p.embedding ? JSON.stringify(p.embedding) : null,
      },
    );
    const id = rows[0]?.id as string;
    await this.query(
      `INSERT INTO typing_sessions (post_id, session, issues)
       VALUES (:id::uuid, :session::jsonb, string_to_array(:issues, ','))`,
      { id, session: JSON.stringify(p.session), issues: p.issues.join(',') },
    );
    return id;
  }

  async countSimilarAuthors(postId: string, embedding: number[], maxDistance: number): Promise<number> {
    const rows = await this.query(
      `SELECT count(DISTINCT p.author_id) AS n
       FROM posts p, posts me
       WHERE me.id = :id::uuid
         AND p.status = 'published'
         AND p.author_id <> me.author_id
         AND p.embedding <=> :emb::vector <= :maxd`,
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

  async writingDays(authorId: string): Promise<number> {
    const rows = await this.query(`SELECT days FROM writing_days WHERE author_id = :a::uuid`, { a: authorId });
    return Number(rows[0]?.days ?? 0);
  }

  async recentBlocks(authorId: string, windowDays: number): Promise<number> {
    const rows = await this.query(
      `SELECT count(*) AS n FROM posts
       WHERE author_id = :a::uuid AND status = 'blocked'
         AND created_at > now() - make_interval(days => :d)`,
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
      const added = await this.query(
        `INSERT INTO empathies (post_id, user_id)
         SELECT id, :u::uuid FROM posts
         WHERE id = :p::uuid AND status = 'published' AND author_id <> :u::uuid
         RETURNING post_id`,
        { p: postId, u: userId },
      );
      if (added.length === 0) return null;
    }
    const rows = await this.query(`SELECT count(*) AS n FROM empathies WHERE post_id = :p::uuid`, { p: postId });
    return { empathized: removed.length === 0, count: Number(rows[0]?.n ?? 0) };
  }

  async feed(viewerId: string, opts: { following: boolean; before?: string; limit: number }): Promise<FeedPost[]> {
    const rows = await this.query(
      `SELECT p.id::text, p.author_id::text, u.handle, u.display_name, u.photo_key,
              p.body, p.lang, p.typing_ms, p.created_at::text, p.edited_at::text,
              (SELECT count(*) FROM empathies e WHERE e.post_id = p.id) AS empathy_count,
              EXISTS (SELECT 1 FROM empathies e WHERE e.post_id = p.id AND e.user_id = :v::uuid) AS mine
       FROM posts p JOIN users u ON u.id = p.author_id
       WHERE p.status = 'published'
         AND (:before IS NULL OR p.created_at < :before::timestamptz)
         AND (NOT :following OR EXISTS (
               SELECT 1 FROM follows f
               WHERE f.follower_id = :v::uuid AND f.followee_id = p.author_id AND NOT f.hidden))
       ORDER BY p.created_at DESC
       LIMIT :limit`,
      { v: viewerId, before: opts.before ?? null, following: opts.following, limit: opts.limit },
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
}
