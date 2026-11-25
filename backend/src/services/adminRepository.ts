import type { AdminRepository, AdminStats, AdminUser, OpenReport, ReviewDecision, ReviewItem } from './ports.js';
import { AuroraRepository } from './repository.js';

/**
 * The admin pages' queries. Each change and its log row are one statement,
 * so an action is never taken without being recorded.
 */
export class AuroraAdminRepository extends AuroraRepository implements AdminRepository {
  async stats(): Promise<AdminStats> {
    const [r] = await this.query(
      `SELECT (SELECT count(*) FROM users) AS users,
              (SELECT count(*) FROM users WHERE created_at > now() - interval '1 day') AS users_today,
              (SELECT count(*) FROM posts WHERE status = 'published') AS posts,
              (SELECT count(*) FROM posts WHERE status = 'published' AND created_at > now() - interval '1 day') AS posts_today,
              (SELECT count(*) FROM posts WHERE status = 'blocked' AND reviewed_at IS NULL) AS pending,
              (SELECT count(*) FROM users WHERE suspended_at IS NOT NULL) AS suspended,
              (SELECT count(*) FROM reports WHERE resolved_at IS NULL) AS reports`,
    );
    return {
      users: Number(r?.users ?? 0),
      usersToday: Number(r?.users_today ?? 0),
      posts: Number(r?.posts ?? 0),
      postsToday: Number(r?.posts_today ?? 0),
      pendingReview: Number(r?.pending ?? 0),
      suspended: Number(r?.suspended ?? 0),
      openReports: Number(r?.reports ?? 0),
    };
  }

  async reviewQueue(limit: number, before?: string): Promise<ReviewItem[]> {
    const rows = await this.query(
      `SELECT p.id::text, p.author_id::text, u.handle, u.display_name, p.body, p.blocked_reason,
              array_to_string(coalesce(s.issues, '{}'), ',') AS issues, p.typing_ms, p.created_at::text
       FROM posts p JOIN users u ON u.id = p.author_id
       LEFT JOIN typing_sessions s ON s.post_id = p.id
       WHERE p.status = 'blocked' AND p.reviewed_at IS NULL
         AND (CAST(:before AS text) IS NULL OR p.created_at < CAST(:before AS timestamptz))
       ORDER BY p.created_at DESC
       LIMIT :limit`,
      { before: before ?? null, limit },
    );
    return rows.map((r) => ({
      id: r.id as string,
      authorId: r.author_id as string,
      authorHandle: r.handle as string,
      authorName: r.display_name as string,
      body: r.body as string,
      blockedReason: (r.blocked_reason as string | null) ?? null,
      issues: (r.issues as string) ? (r.issues as string).split(',') : [],
      typingMs: Number(r.typing_ms),
      createdAt: r.created_at as string,
    }));
  }

  async reviewPost(postId: string, adminId: string, decision: ReviewDecision): Promise<boolean> {
    const rows = await this.query(
      `WITH done AS (
         UPDATE posts
         SET reviewed_at = now(), reviewed_by = :admin::uuid,
             status = CASE WHEN :decision = 'publish' THEN 'published' ELSE status END,
             blocked_reason = CASE WHEN :decision = 'publish' THEN NULL ELSE blocked_reason END
         WHERE id = :post::uuid AND status = 'blocked' AND reviewed_at IS NULL
         RETURNING id
       ), logged AS (
         INSERT INTO admin_actions (admin_id, action, target_id)
         SELECT :admin::uuid, :decision, id FROM done
       )
       SELECT id::text FROM done`,
      { post: postId, admin: adminId, decision },
    );
    return rows.length > 0;
  }

  async removePost(postId: string, adminId: string, note: string): Promise<boolean> {
    const rows = await this.query(
      `WITH done AS (
         UPDATE posts SET status = 'deleted', removed_by = :admin::uuid
         WHERE id = :post::uuid AND status = 'published'
         RETURNING id
       ), phrases AS (
         DELETE FROM phrase_firsts WHERE post_id IN (SELECT id FROM done)
       ), logged AS (
         INSERT INTO admin_actions (admin_id, action, target_id, note)
         SELECT :admin::uuid, 'remove_post', id, :note FROM done
       )
       SELECT id::text FROM done`,
      { post: postId, admin: adminId, note },
    );
    return rows.length > 0;
  }

  async searchUsers(query: string, limit: number): Promise<AdminUser[]> {
    const rows = await this.query(
      `SELECT u.id::text, u.handle, u.display_name, u.bio, u.photo_key, u.created_at::text,
              u.suspended_at::text, u.suspended_reason,
              (SELECT count(*) FROM posts p WHERE p.author_id = u.id AND p.status = 'published') AS posts,
              (SELECT count(*) FROM posts p WHERE p.author_id = u.id AND p.status = 'blocked'
                 AND p.created_at > now() - interval '30 days') AS blocks
       FROM users u
       WHERE :q = '' OR u.handle ILIKE :pattern OR u.display_name ILIKE :pattern
       ORDER BY u.created_at DESC
       LIMIT :limit`,
      { q: query, pattern: `%${query.replace(/[\\%_]/g, (c) => `\\${c}`)}%`, limit },
    );
    return rows.map((r) => ({
      id: r.id as string,
      handle: r.handle as string,
      displayName: r.display_name as string,
      bio: r.bio as string,
      photoKey: (r.photo_key as string | null) ?? null,
      createdAt: r.created_at as string,
      posts: Number(r.posts),
      recentBlocks: Number(r.blocks),
      suspendedAt: (r.suspended_at as string | null) ?? null,
      suspendedReason: (r.suspended_reason as string | null) ?? null,
    }));
  }

  async setSuspended(userId: string, adminId: string, suspended: boolean, reason: string): Promise<boolean> {
    const rows = await this.query(
      `WITH done AS (
         UPDATE users
         SET suspended_at = CASE WHEN :on THEN coalesce(suspended_at, now()) ELSE NULL END,
             suspended_reason = CASE WHEN :on THEN :reason ELSE NULL END
         WHERE id = :user::uuid
         RETURNING id
       ), logged AS (
         INSERT INTO admin_actions (admin_id, action, target_id, note)
         SELECT :admin::uuid, CASE WHEN :on THEN 'suspend' ELSE 'unsuspend' END, id, :reason FROM done
       )
       SELECT id::text FROM done`,
      { user: userId, admin: adminId, on: suspended, reason },
    );
    return rows.length > 0;
  }

  async openReports(limit: number): Promise<OpenReport[]> {
    const rows = await this.query(
      `SELECT r.id::text, r.reason, r.note, r.created_at::text, rep.handle AS reporter, u.id::text AS user_id,
              u.handle, u.display_name, p.id::text AS post_id, p.body,
              (SELECT count(*) FROM reports o WHERE o.user_id = r.user_id AND o.resolved_at IS NULL) AS on_user
       FROM reports r
       JOIN users u ON u.id = r.user_id
       JOIN users rep ON rep.id = r.reporter_id
       LEFT JOIN posts p ON p.id = r.post_id
       WHERE r.resolved_at IS NULL
       ORDER BY r.created_at DESC
       LIMIT :limit`,
      { limit },
    );
    return rows.map((r) => ({
      id: r.id as string,
      reason: r.reason as string,
      note: r.note as string,
      createdAt: r.created_at as string,
      reporterHandle: r.reporter as string,
      userId: r.user_id as string,
      userHandle: r.handle as string,
      userName: r.display_name as string,
      postId: (r.post_id as string | null) ?? null,
      postBody: (r.body as string | null) ?? null,
      reportsOnUser: Number(r.on_user),
    }));
  }

  async resolveReport(reportId: string, adminId: string, note: string): Promise<boolean> {
    const rows = await this.query(
      `WITH done AS (
         UPDATE reports SET resolved_at = now(), resolved_by = :admin::uuid
         WHERE id = CAST(:id AS bigint) AND resolved_at IS NULL
         RETURNING id, user_id
       ), logged AS (
         INSERT INTO admin_actions (admin_id, action, target_id, note)
         SELECT :admin::uuid, 'resolve_report', user_id, :note FROM done
       )
       SELECT id::text FROM done`,
      { id: reportId, admin: adminId, note },
    );
    return rows.length > 0;
  }

  async removePhoto(userId: string, adminId: string): Promise<{ previous: string | null } | false> {
    const rows = await this.query(
      `WITH old AS (
         SELECT id, photo_key FROM users WHERE id = :user::uuid FOR UPDATE
       ), done AS (
         UPDATE users u SET photo_key = NULL FROM old WHERE u.id = old.id
         RETURNING old.photo_key AS previous, u.id
       ), logged AS (
         INSERT INTO admin_actions (admin_id, action, target_id)
         SELECT :admin::uuid, 'remove_photo', id FROM done
       )
       SELECT previous FROM done`,
      { user: userId, admin: adminId },
    );
    if (rows.length === 0) return false;
    return { previous: (rows[0]!.previous as string | null) ?? null };
  }
}
