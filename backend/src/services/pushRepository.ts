import type { PushBatch, PushKind } from '../push/messages.js';
import type { PushStore, PushToken } from '../push/sender.js';
import { AuroraRepository } from './repository.js';

export interface PushSettings {
  empathy: boolean;
  follow: boolean;
  posts: boolean;
}

export type Platform = PushToken['platform'];

export interface PushRepository {
  /** False without a profile. A token another account had moves to this one. */
  saveToken(userId: string, token: string, platform: Platform): Promise<boolean>;
  removeToken(userId: string, token: string): Promise<void>;
  pushSettings(userId: string): Promise<PushSettings | null>;
  setPushSettings(userId: string, s: PushSettings): Promise<boolean>;
}

/**
 * Events that reach the sender are a few seconds old, so a 공감 or follow
 * still being written when the sender runs is picked up the next minute
 * instead of being skipped.
 */
const SETTLE = `interval '5 seconds'`;

/**
 * How far back the first run for a device looks. Someone who signs in again
 * after a week, or turns alerts on for the first time, gets what happened in
 * the last few minutes, not a pile of old events.
 */
const LOOKBACK = `interval '10 minutes'`;

export class AuroraPushRepository extends AuroraRepository implements PushRepository, PushStore {
  async saveToken(userId: string, token: string, platform: Platform): Promise<boolean> {
    const rows = await this.query(
      `INSERT INTO push_tokens (token, user_id, platform)
       SELECT :t, id, :p FROM users WHERE id = :u::uuid
       ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform, seen_at = now()
       RETURNING 1 AS ok`,
      { t: token, p: platform, u: userId },
    );
    return rows.length > 0;
  }

  async removeToken(userId: string, token: string): Promise<void> {
    await this.query(`DELETE FROM push_tokens WHERE token = :t AND user_id = :u::uuid`, { t: token, u: userId });
  }

  async pushSettings(userId: string): Promise<PushSettings | null> {
    const [r] = await this.query(`SELECT push_empathy, push_follow, push_posts FROM users WHERE id = :u::uuid`, {
      u: userId,
    });
    return r ? { empathy: !!r.push_empathy, follow: !!r.push_follow, posts: !!r.push_posts } : null;
  }

  async setPushSettings(userId: string, s: PushSettings): Promise<boolean> {
    const rows = await this.query(
      `UPDATE users SET push_empathy = :e, push_follow = :f, push_posts = :p WHERE id = :u::uuid RETURNING 1 AS ok`,
      { e: s.empathy, f: s.follow, p: s.posts, u: userId },
    );
    return rows.length > 0;
  }

  async takeBatches(): Promise<PushBatch[]> {
    const rows = await this.query(
      `WITH due AS (
         SELECT u.id, u.locale, greatest(u.push_checked_at, now() - ${LOOKBACK}) AS since, now() - ${SETTLE} AS upto,
                u.push_empathy, u.push_follow, u.push_posts
         FROM users u
         WHERE u.suspended_at IS NULL AND EXISTS (SELECT 1 FROM push_tokens t WHERE t.user_id = u.id)
         FOR UPDATE OF u SKIP LOCKED
       ), moved AS (
         UPDATE users u SET push_checked_at = due.upto FROM due WHERE u.id = due.id
       ), ev AS (
         SELECT d.id AS recipient, 'empathy' AS kind, e.created_at, e.user_id AS actor, p.id AS post_id,
                left(p.body, 80) AS excerpt
         FROM due d
           JOIN posts p ON p.author_id = d.id AND p.status = 'published'
           JOIN empathies e ON e.post_id = p.id AND e.created_at > d.since AND e.created_at <= d.upto
         WHERE d.push_empathy AND e.user_id <> d.id
         UNION ALL
         SELECT d.id, 'follow', f.created_at, f.follower_id, NULL, NULL
         FROM due d JOIN follows f ON f.followee_id = d.id AND NOT f.hidden
           AND f.created_at > d.since AND f.created_at <= d.upto
         WHERE d.push_follow
         UNION ALL
         SELECT d.id, 'post', p.created_at, p.author_id, p.id, left(p.body, 80)
         FROM due d
           JOIN follows f ON f.follower_id = d.id AND f.alerts_since IS NOT NULL AND NOT f.hidden
           JOIN posts p ON p.author_id = f.followee_id AND p.status = 'published'
             AND p.created_at >= f.alerts_since AND p.created_at > d.since AND p.created_at <= d.upto
           JOIN users au ON au.id = p.author_id AND au.suspended_at IS NULL
         WHERE d.push_posts
       ), fresh AS (
         SELECT ev.* FROM ev
         WHERE NOT EXISTS (SELECT 1 FROM blocks b
           WHERE (b.blocker_id = ev.recipient AND b.blocked_id = ev.actor)
              OR (b.blocker_id = ev.actor AND b.blocked_id = ev.recipient))
           AND NOT EXISTS (SELECT 1 FROM push_sent s
             WHERE s.user_id = ev.recipient AND s.kind = ev.kind AND s.actor_id = ev.actor
               AND s.post_id = coalesce(ev.post_id, '00000000-0000-0000-0000-000000000000'::uuid) AND s.at > now() - interval '1 day')
       ), remember AS (
         INSERT INTO push_sent (user_id, kind, actor_id, post_id)
         SELECT DISTINCT recipient, kind, actor, coalesce(post_id, '00000000-0000-0000-0000-000000000000'::uuid) FROM fresh WHERE kind <> 'post'
         ON CONFLICT (user_id, kind, actor_id, post_id) DO UPDATE SET at = now()
       ), latest AS (
         SELECT ev.*, count(*) OVER w AS n, row_number() OVER (w ORDER BY ev.created_at DESC) AS rn,
                min(ev.post_id::text) OVER w IS DISTINCT FROM max(ev.post_id::text) OVER w AS many_posts
         FROM fresh ev
         WINDOW w AS (PARTITION BY ev.recipient, ev.kind)
       )
       SELECT l.recipient::text AS user_id, d.locale, l.kind, l.n, l.actor::text AS actor_id,
              a.display_name, l.post_id::text, l.excerpt, l.many_posts
       FROM latest l JOIN due d ON d.id = l.recipient JOIN users a ON a.id = l.actor
       WHERE l.rn = 1`,
    );
    return rows.map((r) => ({
      userId: r.user_id as string,
      lang: (r.locale as string) ?? 'ko',
      kind: r.kind as PushKind,
      count: Number(r.n),
      actorId: r.actor_id as string,
      actorName: r.display_name as string,
      postId: (r.post_id as string | null) ?? null,
      excerpt: (r.excerpt as string | null) ?? null,
      manyPosts: !!r.many_posts,
    }));
  }

  /** What the notifications tab would count as unread, up to 99, for the app icon. */
  async unread(userIds: string[]): Promise<Map<string, number>> {
    const out = new Map<string, number>();
    if (userIds.length === 0) return out;
    const rows = await this.query(
      `SELECT me.id::text AS user_id, (
         SELECT count(*) FROM (
           SELECT 1 FROM (
             SELECT e.created_at, e.user_id AS actor
             FROM posts p JOIN empathies e ON e.post_id = p.id
             WHERE p.author_id = me.id AND p.status = 'published'
             UNION ALL
             SELECT f.created_at, f.follower_id FROM follows f WHERE f.followee_id = me.id AND NOT f.hidden
             UNION ALL
             SELECT p.created_at, p.author_id
             FROM follows f JOIN posts p ON p.author_id = f.followee_id
               JOIN users au ON au.id = p.author_id AND au.suspended_at IS NULL
             WHERE f.follower_id = me.id AND f.alerts_since IS NOT NULL AND NOT f.hidden
               AND p.status = 'published' AND p.created_at >= f.alerts_since
           ) n
           WHERE n.created_at > me.notifications_seen_at
             AND NOT EXISTS (SELECT 1 FROM blocks b
               WHERE (b.blocker_id = me.id AND b.blocked_id = n.actor) OR (b.blocker_id = n.actor AND b.blocked_id = me.id))
           LIMIT 99
         ) x) AS n
       FROM users me WHERE me.id::text = ANY(string_to_array(:ids, ','))`,
      { ids: userIds.join(',') },
    );
    for (const r of rows) out.set(r.user_id as string, Number(r.n));
    return out;
  }

  async tokens(userIds: string[]): Promise<Map<string, PushToken[]>> {
    const out = new Map<string, PushToken[]>();
    if (userIds.length === 0) return out;
    const rows = await this.query(
      `SELECT user_id::text, token, platform FROM push_tokens
       WHERE user_id::text = ANY(string_to_array(:ids, ','))`,
      { ids: userIds.join(',') },
    );
    for (const r of rows) {
      const list = out.get(r.user_id as string) ?? [];
      list.push({ token: r.token as string, platform: r.platform as Platform });
      out.set(r.user_id as string, list);
    }
    return out;
  }

  async removeTokens(tokens: string[]): Promise<void> {
    if (tokens.length === 0) return;
    // Tokens hold ':' and '-' but never a newline, so newline-separated is safe.
    await this.query(`DELETE FROM push_tokens WHERE token = ANY(string_to_array(:t, E'\\n'))`, {
      t: tokens.join('\n'),
    });
  }
}
