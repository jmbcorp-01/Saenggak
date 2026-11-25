import type { BlockedUser, NewReport, Notification, SocialRepository } from './ports.js';
import { AuroraRepository } from './repository.js';

/** Reports, blocks and notifications on Aurora. */
export class AuroraSocialRepository extends AuroraRepository implements SocialRepository {
  async report(reporterId: string, r: NewReport): Promise<'ok' | 'not_found' | 'self'> {
    if (r.userId === reporterId) return 'self';
    const rows = await this.query(
      `WITH target AS (
         SELECT u.id FROM users u
         WHERE u.id = :user::uuid
           AND (CAST(:post AS text) IS NULL OR EXISTS (
                 SELECT 1 FROM posts p WHERE p.id = CAST(:post AS uuid) AND p.author_id = u.id AND p.status = 'published'))
       ), ins AS (
         INSERT INTO reports (reporter_id, user_id, post_id, reason, note)
         SELECT :reporter::uuid, id, CAST(:post AS uuid), :reason, :note FROM target
         ON CONFLICT DO NOTHING
       )
       SELECT 1 AS ok FROM target`,
      { reporter: reporterId, user: r.userId, post: r.postId ?? null, reason: r.reason, note: r.note },
    );
    return rows.length > 0 ? 'ok' : 'not_found';
  }

  async block(blockerId: string, blockedId: string): Promise<'ok' | 'not_found' | 'self'> {
    if (blockerId === blockedId) return 'self';
    const rows = await this.query(
      `WITH target AS (SELECT id FROM users WHERE id = :b::uuid),
       ins AS (
         INSERT INTO blocks (blocker_id, blocked_id) SELECT :a::uuid, id FROM target ON CONFLICT DO NOTHING
       ), unfollow AS (
         DELETE FROM follows
         WHERE (follower_id = :a::uuid AND followee_id IN (SELECT id FROM target))
            OR (followee_id = :a::uuid AND follower_id IN (SELECT id FROM target))
       )
       SELECT 1 AS ok FROM target`,
      { a: blockerId, b: blockedId },
    );
    return rows.length > 0 ? 'ok' : 'not_found';
  }

  async unblock(blockerId: string, blockedId: string): Promise<void> {
    await this.query(`DELETE FROM blocks WHERE blocker_id = :a::uuid AND blocked_id = :b::uuid`, {
      a: blockerId,
      b: blockedId,
    });
  }

  async blocked(userId: string): Promise<BlockedUser[]> {
    const rows = await this.query(
      `SELECT u.id::text, u.handle, u.display_name FROM blocks b JOIN users u ON u.id = b.blocked_id
       WHERE b.blocker_id = :u::uuid ORDER BY b.created_at DESC`,
      { u: userId },
    );
    return rows.map((r) => ({ id: r.id as string, handle: r.handle as string, displayName: r.display_name as string }));
  }

  async notifications(userId: string, limit: number, before?: string) {
    // Empathies on the person's posts and new followers, minus anyone blocked either way.
    const events = `
      SELECT 'empathy' AS kind, e.created_at, e.user_id AS actor, p.id AS post_id, left(p.body, 60) AS excerpt
      FROM empathies e JOIN posts p ON p.id = e.post_id
      WHERE p.author_id = :u::uuid AND p.status = 'published'
      UNION ALL
      SELECT 'follow', f.created_at, f.follower_id, NULL, NULL
      FROM follows f WHERE f.followee_id = :u::uuid AND NOT f.hidden`;
    const notBlocked = `NOT EXISTS (SELECT 1 FROM blocks b
        WHERE (b.blocker_id = :u::uuid AND b.blocked_id = n.actor) OR (b.blocker_id = n.actor AND b.blocked_id = :u::uuid))`;
    const rows = await this.query(
      `SELECT n.kind, n.created_at::text, a.id::text AS actor_id, a.handle, a.display_name, a.photo_key,
              n.post_id::text, n.excerpt
       FROM (${events}) n JOIN users a ON a.id = n.actor
       WHERE ${notBlocked}
         AND (CAST(:before AS text) IS NULL OR n.created_at < CAST(:before AS timestamptz))
       ORDER BY n.created_at DESC
       LIMIT :limit`,
      { u: userId, before: before ?? null, limit },
    );
    const [count] = await this.query(
      `SELECT count(*) AS n FROM (
         SELECT 1 FROM (${events}) n, users me
         WHERE me.id = :u::uuid AND n.created_at > me.notifications_seen_at AND ${notBlocked}
         LIMIT 100
       ) x`,
      { u: userId },
    );
    const items: Notification[] = rows.map((r) => ({
      kind: r.kind as 'empathy' | 'follow',
      at: r.created_at as string,
      actorId: r.actor_id as string,
      actorHandle: r.handle as string,
      actorName: r.display_name as string,
      actorPhotoKey: (r.photo_key as string | null) ?? null,
      postId: (r.post_id as string | null) ?? null,
      excerpt: (r.excerpt as string | null) ?? null,
    }));
    return { items, unread: Number(count?.n ?? 0) };
  }

  async markNotificationsSeen(userId: string): Promise<void> {
    await this.query(`UPDATE users SET notifications_seen_at = now() WHERE id = :u::uuid`, { u: userId });
  }
}
