import { newInviteCode, nextEveningSlot } from '../growth/codes.js';
import type {
  AuditEntry,
  Dashboard,
  DueItem,
  GrowthAdmin,
  GrowthRepository,
  LinkStat,
  LinkTarget,
  Platform,
  PromoCandidate,
  PromoDecision,
  PromoItem,
  PromoStatus,
  PromoStore,
  PublicPost,
  Question,
  SharingSettings,
  SourceResult,
} from './growthPorts.js';
import { AuroraRepository } from './repository.js';

/** A post Saenggak may show outside the app: p = posts, u = its writer. */
const SHAREABLE = `p.status = 'published' AND NOT p.share_excluded AND u.share_ok AND u.suspended_at IS NULL`;
/** The writer's name, unless they chose to be shown without it. */
const SHOWN_NAME = `CASE WHEN u.share_anonymous THEN NULL ELSE u.display_name END`;
/** A post scoring this low reads as copied or empty, so it is never featured. */
const MIN_FEATURE_SCORE = 40;
const KST = `'Asia/Seoul'`;

/** Active from day N after joining: a post or a 공감 at or after it. u = users, :n = N. */
const ACTIVE_FROM = (n: string) => `(EXISTS (SELECT 1 FROM posts p WHERE p.author_id = u.id AND p.status <> 'deleted'
                           AND p.created_at >= u.created_at + make_interval(days => ${n}))
        OR EXISTS (SELECT 1 FROM empathies e WHERE e.user_id = u.id AND e.created_at >= u.created_at + make_interval(days => ${n})))`;

const question = (r: Record<string, unknown>): Question => ({
  id: r.id as string,
  day: r.day as string,
  textKo: r.text_ko as string,
  textEn: r.text_en as string,
  status: r.status as Question['status'],
});

const parsePosted = (v: unknown): Record<string, string> => {
  try {
    const o: unknown = JSON.parse(String(v ?? '{}'));
    return o && typeof o === 'object' ? (o as Record<string, string>) : {};
  } catch {
    return {};
  }
};

export class AuroraGrowthRepository extends AuroraRepository implements GrowthRepository, GrowthAdmin, PromoStore {
  // ---- The reader's own settings and links ----

  async sharing(userId: string): Promise<SharingSettings | null> {
    const [r] = await this.query(`SELECT share_ok, share_anonymous FROM users WHERE id = :u::uuid`, { u: userId });
    return r ? { shareOk: Boolean(r.share_ok), anonymous: Boolean(r.share_anonymous) } : null;
  }

  async setSharing(userId: string, s: SharingSettings): Promise<boolean> {
    const rows = await this.query(
      `UPDATE users SET share_ok = :ok, share_anonymous = :anon WHERE id = :u::uuid RETURNING id`,
      { u: userId, ok: s.shareOk, anon: s.anonymous },
    );
    return rows.length > 0;
  }

  async setPostExcluded(userId: string, postId: string, excluded: boolean): Promise<boolean> {
    const rows = await this.query(
      `UPDATE posts SET share_excluded = :x
       WHERE id = :p::uuid AND author_id = :u::uuid AND status = 'published' RETURNING id`,
      { u: userId, p: postId, x: excluded },
    );
    return rows.length > 0;
  }

  async inviteCode(userId: string): Promise<string | null> {
    for (let attempt = 0; attempt < 4; attempt++) {
      try {
        const [r] = await this.query(
          `UPDATE users SET invite_code = coalesce(invite_code, :c) WHERE id = :u::uuid RETURNING invite_code`,
          { u: userId, c: newInviteCode() },
        );
        return r ? (r.invite_code as string) : null;
      } catch (e) {
        // Another person already has that code: try a new one.
        if (!/invite_code|duplicate key/i.test(String(e))) throw e;
      }
    }
    throw new Error('no free invite code');
  }

  async resolveCode(code: string): Promise<LinkTarget | null> {
    const [r] = await this.query(
      `SELECT invite_code AS code, 'invite' AS channel, id::text AS referrer FROM users WHERE invite_code = upper(:c)
       UNION ALL
       SELECT code, channel, NULL FROM link_codes WHERE code = lower(:c)
       LIMIT 1`,
      { c: code },
    );
    return r ? { code: r.code as string, channel: r.channel as string, referrerId: (r.referrer as string | null) ?? null } : null;
  }

  async recordClick(code: string, platform: Platform): Promise<void> {
    await this.query(`INSERT INTO link_clicks (code, platform) VALUES (:c, :p)`, { c: code, p: platform });
  }

  async recordSource(userId: string, code: string): Promise<SourceResult> {
    const [me] = await this.query(
      `SELECT created_at > now() - interval '1 day' AS fresh,
              EXISTS (SELECT 1 FROM signup_sources s WHERE s.user_id = users.id) AS done
       FROM users WHERE id = :u::uuid`,
      { u: userId },
    );
    if (!me) return 'profile_required';
    if (me.done) return 'already';
    if (!me.fresh) return 'too_late';
    const target = await this.resolveCode(code);
    if (!target) return 'unknown_code';
    if (target.referrerId === userId) return 'self';
    const rows = await this.query(
      `INSERT INTO signup_sources (user_id, code, channel, referrer_id)
       VALUES (:u::uuid, :c, :ch, CAST(:r AS uuid))
       ON CONFLICT (user_id) DO NOTHING RETURNING user_id`,
      { u: userId, c: target.code, ch: target.channel, r: target.referrerId },
    );
    return rows.length > 0 ? 'ok' : 'already';
  }

  async todayQuestion(userId: string): Promise<Question | null> {
    const [r] = await this.query(
      `SELECT q.id::text, q.day::text, q.text_ko, q.text_en, q.status
       FROM daily_questions q, users u
       WHERE u.id = :u::uuid AND q.status = 'approved' AND q.day = (now() AT TIME ZONE u.time_zone)::date`,
      { u: userId },
    );
    return r ? question(r) : null;
  }

  async publicPost(postId: string): Promise<PublicPost | null> {
    const [r] = await this.query(
      `SELECT p.id::text, p.body, p.lang, p.typing_ms, p.created_at::text, ${SHOWN_NAME} AS name,
              (SELECT count(*) FROM empathies e WHERE e.post_id = p.id) AS empathies
       FROM posts p JOIN users u ON u.id = p.author_id
       WHERE p.id = :p::uuid AND ${SHAREABLE}`,
      { p: postId },
    );
    if (!r) return null;
    return {
      id: r.id as string,
      body: r.body as string,
      lang: r.lang as string,
      authorName: (r.name as string | null) ?? null,
      typingMs: Number(r.typing_ms),
      empathyCount: Number(r.empathies),
      createdAt: r.created_at as string,
    };
  }

  async publicPostIds(limit: number): Promise<{ id: string; at: string }[]> {
    const rows = await this.query(
      `SELECT p.id::text, coalesce(p.edited_at, p.created_at)::text AS at
       FROM posts p JOIN users u ON u.id = p.author_id
       WHERE ${SHAREABLE}
       ORDER BY p.created_at DESC LIMIT :limit`,
      { limit },
    );
    return rows.map((r) => ({ id: r.id as string, at: r.at as string }));
  }

  // ---- Admin pages ----

  async dashboard(days: number): Promise<Dashboard> {
    const since = `now() - make_interval(days => CAST(:days AS int) + 1)`;
    const local = (col: string) => `(${col} AT TIME ZONE ${KST})::date`;
    const [series, retention, sources] = await Promise.all([
      this.query(
        `WITH d AS (
           SELECT generate_series(${local('now()')} - (CAST(:days AS int) - 1), ${local('now()')}, interval '1 day')::date AS day
         ), s AS (SELECT ${local('created_at')} AS day, count(*) AS n FROM users WHERE created_at > ${since} GROUP BY 1
         ), p AS (SELECT ${local('created_at')} AS day, count(*) AS n FROM posts
                  WHERE created_at > ${since} AND status = 'published' GROUP BY 1
         ), e AS (SELECT ${local('created_at')} AS day, count(*) AS n FROM empathies WHERE created_at > ${since} GROUP BY 1
         ), a AS (SELECT day, count(DISTINCT who) AS n FROM (
                    SELECT ${local('created_at')} AS day, author_id AS who FROM posts WHERE created_at > ${since} AND status <> 'deleted'
                    UNION ALL
                    SELECT ${local('created_at')}, user_id FROM empathies WHERE created_at > ${since}) x GROUP BY day)
         SELECT d.day::text, coalesce(s.n, 0) AS signups, coalesce(p.n, 0) AS posts,
                coalesce(e.n, 0) AS empathies, coalesce(a.n, 0) AS active
         FROM d LEFT JOIN s USING (day) LEFT JOIN p USING (day) LEFT JOIN e USING (day) LEFT JOIN a USING (day)
         ORDER BY d.day`,
        { days },
      ),
      this.query(
        `SELECT n.n, count(u.id) AS cohort, count(u.id) FILTER (WHERE ${ACTIVE_FROM('n.n')}) AS kept
         FROM (VALUES (1), (7), (30)) AS n(n)
         LEFT JOIN users u ON u.created_at < now() - make_interval(days => n.n) AND u.created_at > now() - interval '90 days'
         GROUP BY n.n`,
      ),
      this.query(
        `SELECT coalesce(s.channel, 'direct') AS channel, count(*) AS signups,
                count(*) FILTER (WHERE ${ACTIVE_FROM('7')}) AS active7
         FROM users u LEFT JOIN signup_sources s ON s.user_id = u.id
         WHERE u.created_at > now() - interval '90 days'
         GROUP BY 1 ORDER BY 2 DESC`,
      ),
    ]);
    const ret = (n: number) => {
      const r = retention.find((x) => Number(x.n) === n);
      const cohort = Number(r?.cohort ?? 0);
      return { cohort, rate: cohort > 0 ? Number(r?.kept ?? 0) / cohort : null };
    };
    return {
      days: series.map((r) => ({
        day: r.day as string,
        signups: Number(r.signups),
        posts: Number(r.posts),
        empathies: Number(r.empathies),
        activePeople: Number(r.active),
      })),
      retention: { d1: ret(1), d7: ret(7), d30: ret(30) },
      sources: sources.map((r) => ({ channel: r.channel as string, signups: Number(r.signups), active7: Number(r.active7) })),
    };
  }

  async audit(limit: number, before?: string): Promise<AuditEntry[]> {
    const rows = await this.query(
      `SELECT a.id::text, u.handle, a.action, a.target_id::text, a.note, a.at::text
       FROM admin_actions a LEFT JOIN users u ON u.id = a.admin_id
       WHERE (CAST(:before AS text) IS NULL OR a.at < CAST(:before AS timestamptz))
       ORDER BY a.at DESC LIMIT :limit`,
      { before: before ?? null, limit },
    );
    return rows.map((r) => ({
      id: r.id as string,
      adminHandle: (r.handle as string | null) ?? null,
      action: r.action as string,
      targetId: r.target_id as string,
      note: r.note as string,
      at: r.at as string,
    }));
  }

  async promoItems(statuses: PromoStatus[], limit: number): Promise<PromoItem[]> {
    const rows = await this.query(
      `SELECT i.id::text, i.post_id::text, i.status, i.caption, i.score, i.link_code, i.card_key,
              i.scheduled_for::text, i.posted::text, i.error, i.created_at::text,
              p.body, p.lang, p.typing_ms, u.handle, ${SHOWN_NAME} AS name, p.id IS NOT NULL AS has_post,
              (SELECT count(*) FROM empathies e WHERE e.post_id = p.id) AS empathies,
              (SELECT count(*) FROM link_clicks c WHERE c.code = i.link_code) AS clicks,
              (SELECT count(*) FROM signup_sources s WHERE s.code = i.link_code) AS signups
       FROM promo_items i
       LEFT JOIN posts p ON p.id = i.post_id AND p.status <> 'deleted'
       LEFT JOIN users u ON u.id = p.author_id
       WHERE i.status = ANY (string_to_array(:st, ','))
       ORDER BY coalesce(i.scheduled_for, i.created_at) DESC LIMIT :limit`,
      { st: statuses.join(','), limit },
    );
    return rows.map((r) => ({
      id: r.id as string,
      postId: r.post_id as string,
      status: r.status as PromoStatus,
      caption: r.caption as string,
      score: Number(r.score),
      linkCode: r.link_code as string,
      cardKey: (r.card_key as string | null) ?? null,
      scheduledFor: (r.scheduled_for as string | null) ?? null,
      posted: parsePosted(r.posted),
      error: (r.error as string | null) ?? null,
      createdAt: r.created_at as string,
      post: r.has_post
        ? {
            body: r.body as string,
            lang: r.lang as string,
            authorHandle: r.handle as string,
            authorName: (r.name as string | null) ?? null,
            empathyCount: Number(r.empathies),
            typingMs: Number(r.typing_ms),
          }
        : null,
      clicks: Number(r.clicks),
      signups: Number(r.signups),
    }));
  }

  async decidePromo(itemId: string, adminId: string, d: PromoDecision): Promise<boolean> {
    const rows = await this.query(
      `WITH done AS (
         UPDATE promo_items SET
           status = CASE WHEN :approve THEN 'approved' ELSE 'skipped' END,
           caption = coalesce(CAST(:caption AS text), caption),
           card_key = coalesce(CAST(:card AS text), card_key),
           scheduled_for = CASE WHEN :approve THEN coalesce(CAST(:at AS timestamptz), CAST(:slot AS timestamptz)) END,
           error = NULL, decided_by = :admin::uuid, decided_at = now()
         WHERE id = :id::uuid AND status IN ('pending', 'approved', 'failed')
         RETURNING id
       ), logged AS (
         INSERT INTO admin_actions (admin_id, action, target_id)
         SELECT :admin::uuid, CASE WHEN :approve THEN 'promo_approve' ELSE 'promo_skip' END, id FROM done
       )
       SELECT id::text FROM done`,
      {
        id: itemId,
        admin: adminId,
        approve: d.approve,
        caption: d.caption ?? null,
        card: d.cardKey ?? null,
        at: d.scheduledFor ?? null,
        slot: nextEveningSlot(new Date()).toISOString(),
      },
    );
    return rows.length > 0;
  }

  async markPromo(itemId: string, adminId: string, status: 'posted' | 'withdrawn'): Promise<boolean> {
    const from = status === 'posted' ? `('approved', 'failed')` : `('pending', 'approved', 'failed', 'posted', 'takedown')`;
    const rows = await this.query(
      `WITH done AS (
         UPDATE promo_items SET status = :s, decided_by = :admin::uuid, decided_at = now()
         WHERE id = :id::uuid AND status IN ${from}
         RETURNING id
       ), logged AS (
         INSERT INTO admin_actions (admin_id, action, target_id)
         SELECT :admin::uuid, 'promo_' || :s, id FROM done
       )
       SELECT id::text FROM done`,
      { id: itemId, admin: adminId, s: status },
    );
    return rows.length > 0;
  }

  async linkStats(limit: number): Promise<LinkStat[]> {
    const rows = await this.query(
      `SELECT l.code, l.channel, l.label, l.created_at::text,
              (SELECT count(*) FROM link_clicks c WHERE c.code = l.code) AS clicks,
              count(u.id) AS signups, count(u.id) FILTER (WHERE ${ACTIVE_FROM('7')}) AS active7
       FROM link_codes l
       LEFT JOIN signup_sources s ON s.code = l.code
       LEFT JOIN users u ON u.id = s.user_id
       WHERE l.channel <> 'promo'
       GROUP BY l.code
       UNION ALL
       SELECT '*', 'invite', '', NULL,
              (SELECT count(*) FROM link_clicks c WHERE c.code ~ '^[A-Z0-9]{8}$'),
              count(u.id), count(u.id) FILTER (WHERE ${ACTIVE_FROM('7')})
       FROM signup_sources s JOIN users u ON u.id = s.user_id WHERE s.channel = 'invite'
       UNION ALL
       SELECT '*', 'promo', '', NULL,
              (SELECT count(*) FROM link_clicks c JOIN promo_items i ON i.link_code = c.code),
              count(u.id), count(u.id) FILTER (WHERE ${ACTIVE_FROM('7')})
       FROM signup_sources s JOIN users u ON u.id = s.user_id WHERE s.channel = 'promo'
       ORDER BY 4 DESC NULLS FIRST LIMIT :limit`,
      { limit },
    );
    return rows.map((r) => ({
      code: r.code as string,
      channel: r.channel as string,
      label: r.label as string,
      clicks: Number(r.clicks),
      signups: Number(r.signups),
      active7: Number(r.active7),
      createdAt: (r.created_at as string | null) ?? '',
    }));
  }

  async createLinkCode(adminId: string, code: string, channel: string, label: string): Promise<'ok' | 'taken'> {
    const rows = await this.query(
      `WITH made AS (
         INSERT INTO link_codes (code, channel, label) VALUES (:c, :ch, :l)
         ON CONFLICT (code) DO NOTHING RETURNING code
       ), logged AS (
         INSERT INTO admin_actions (admin_id, action, target_id, note)
         SELECT :admin::uuid, 'link_code', :admin::uuid, code FROM made
       )
       SELECT code FROM made`,
      { admin: adminId, c: code, ch: channel, l: label },
    );
    return rows.length > 0 ? 'ok' : 'taken';
  }

  async questions(fromDay: string, limit: number): Promise<Question[]> {
    const rows = await this.query(
      `SELECT id::text, day::text, text_ko, text_en, status FROM daily_questions
       WHERE day >= CAST(:from AS date) ORDER BY day LIMIT :limit`,
      { from: fromDay, limit },
    );
    return rows.map(question);
  }

  async saveQuestion(adminId: string, q: { day: string; textKo: string; textEn: string; approve: boolean }): Promise<Question> {
    const [r] = await this.query(
      `WITH saved AS (
         INSERT INTO daily_questions (day, text_ko, text_en, status)
         VALUES (CAST(:day AS date), :ko, :en, CASE WHEN :approve THEN 'approved' ELSE 'draft' END)
         ON CONFLICT (day) DO UPDATE SET text_ko = EXCLUDED.text_ko, text_en = EXCLUDED.text_en, status = EXCLUDED.status
         RETURNING id, day, text_ko, text_en, status
       ), logged AS (
         INSERT INTO admin_actions (admin_id, action, target_id, note)
         SELECT :admin::uuid, 'question_' || status, id, day::text FROM saved
       )
       SELECT id::text, day::text, text_ko, text_en, status FROM saved`,
      { admin: adminId, day: q.day, ko: q.textKo, en: q.textEn, approve: q.approve },
    );
    return question(r!);
  }

  // ---- The promo agent ----

  async candidates(limit: number): Promise<PromoCandidate[]> {
    const rows = await this.query(
      `SELECT id, body, lang, score FROM (
         SELECT DISTINCT ON (p.author_id) p.id::text AS id, p.body, p.lang,
                (e.n * 3 + coalesce(p.thought_score, 50) / 10)::int AS score
         FROM posts p JOIN users u ON u.id = p.author_id
         CROSS JOIN LATERAL (SELECT count(*) AS n FROM empathies x WHERE x.post_id = p.id) e
         WHERE ${SHAREABLE}
           AND p.created_at > now() - interval '3 days'
           AND coalesce(p.thought_score, 50) >= ${MIN_FEATURE_SCORE}
           AND NOT EXISTS (SELECT 1 FROM promo_items i WHERE i.post_id = p.id)
           -- One writer at most once in two weeks.
           AND NOT EXISTS (SELECT 1 FROM promo_items i JOIN posts q ON q.id = i.post_id
                           WHERE q.author_id = p.author_id AND i.created_at > now() - interval '14 days')
           -- Nothing anyone reported, and no one with an open report.
           AND NOT EXISTS (SELECT 1 FROM reports r WHERE r.post_id = p.id
                           OR (r.user_id = p.author_id AND r.resolved_at IS NULL))
         ORDER BY p.author_id, score DESC
       ) best
       ORDER BY score DESC LIMIT :limit`,
      { limit },
    );
    return rows.map((r) => ({ postId: r.id as string, body: r.body as string, lang: r.lang as string, score: Number(r.score) }));
  }

  async addItem(c: PromoCandidate, caption: string, linkCode: string): Promise<void> {
    await this.query(
      `WITH code AS (INSERT INTO link_codes (code, channel, label) VALUES (:code, 'promo', 'promo post'))
       INSERT INTO promo_items (post_id, caption, score, link_code)
       VALUES (:p::uuid, :caption, :score, :code) ON CONFLICT (post_id) DO NOTHING`,
      { p: c.postId, caption, score: c.score, code: linkCode },
    );
  }

  async due(limit: number): Promise<DueItem[]> {
    const rows = await this.query(
      `SELECT i.id::text, i.caption, i.card_key, i.link_code, i.posted::text, p.body, p.lang, ${SHOWN_NAME} AS name
       FROM promo_items i JOIN posts p ON p.id = i.post_id JOIN users u ON u.id = p.author_id
       WHERE i.status = 'approved' AND i.scheduled_for <= now() AND ${SHAREABLE}
       ORDER BY i.scheduled_for LIMIT :limit`,
      { limit },
    );
    return rows.map((r) => ({
      id: r.id as string,
      caption: r.caption as string,
      cardKey: (r.card_key as string | null) ?? null,
      linkCode: r.link_code as string,
      posted: parsePosted(r.posted),
      body: r.body as string,
      lang: r.lang as string,
      authorName: (r.name as string | null) ?? null,
    }));
  }

  async markPosted(itemId: string, posted: Record<string, string>, error: string | null): Promise<void> {
    await this.query(
      `UPDATE promo_items SET posted = CAST(:posted AS jsonb), error = :err,
              status = CASE WHEN CAST(:err AS text) IS NULL THEN 'posted' ELSE 'failed' END
       WHERE id = :id::uuid`,
      { id: itemId, posted: JSON.stringify(posted), err: error },
    );
  }

  async withdrawUnshareable(): Promise<string[]> {
    const rows = await this.query(
      `WITH gone AS (
         SELECT i.id, i.card_key FROM promo_items i
         LEFT JOIN posts p ON p.id = i.post_id
         LEFT JOIN users u ON u.id = p.author_id
         WHERE i.status IN ('pending', 'approved', 'failed', 'posted')
           AND NOT coalesce(${SHAREABLE}, false)
       )
       UPDATE promo_items i
       SET status = CASE WHEN i.status = 'posted' OR i.posted <> '{}'::jsonb THEN 'takedown' ELSE 'withdrawn' END,
           card_key = NULL
       FROM gone
       WHERE i.id = gone.id
       RETURNING gone.card_key`,
    );
    return rows.map((r) => r.card_key as string | null).filter((k): k is string => !!k);
  }

  async daysWithoutQuestion(from: string, count: number): Promise<string[]> {
    const rows = await this.query(
      `SELECT d::date::text AS day
       FROM generate_series(CAST(:from AS date), CAST(:from AS date) + (CAST(:n AS int) - 1), interval '1 day') d
       WHERE NOT EXISTS (SELECT 1 FROM daily_questions q WHERE q.day = d::date)
       ORDER BY d`,
      { from, n: count },
    );
    return rows.map((r) => r.day as string);
  }

  async recentQuestions(limit: number): Promise<string[]> {
    const rows = await this.query(`SELECT text_ko FROM daily_questions ORDER BY day DESC LIMIT :limit`, { limit });
    return rows.map((r) => r.text_ko as string);
  }

  async addQuestionDrafts(drafts: { day: string; textKo: string; textEn: string }[]): Promise<void> {
    for (const q of drafts) {
      await this.query(
        `INSERT INTO daily_questions (day, text_ko, text_en) VALUES (CAST(:day AS date), :ko, :en)
         ON CONFLICT (day) DO NOTHING`,
        { day: q.day, ko: q.textKo, en: q.textEn },
      );
    }
  }
}
