import { randomUUID } from 'node:crypto';
import { pickCandidates } from '../growth/agent.js';
import { isChannel, LINK_CODE } from '../growth/codes.js';
import type { AdminRepository, PhotoStore } from '../services/ports.js';
import type { GrowthAdmin, PromoStatus } from '../services/growthPorts.js';
import { AuroraAdminRepository } from '../services/adminRepository.js';
import { ClaudeCopywriter } from '../services/copywriter.js';
import { AuroraGrowthRepository } from '../services/growthRepository.js';
import { publishersFrom, TokenSecret } from '../services/meta.js';
import { photoUrl, S3PhotoStore } from '../services/photos.js';
import { isUuid, json, parseBody, safely, userId, type Event } from './http.js';

const PAGE_SIZE = 30;
export const ADMIN_GROUP = 'admins';

type Deps = {
  admin: AdminRepository;
  photoStore: PhotoStore;
  growth: GrowthAdmin;
  /** Runs the promo agent's morning pick now; returns how many it added. */
  pickNow: () => Promise<number>;
  /** Which of Saenggak's own accounts are connected. */
  channels: () => Promise<string[]>;
};

/** The admin page's tabs of the promo queue. */
const PROMO_TABS: Record<string, PromoStatus[]> = {
  pending: ['pending'],
  scheduled: ['approved', 'failed', 'takedown'],
  done: ['posted', 'skipped', 'withdrawn'],
};
const MAX_CARD_BYTES = 4 * 1024 * 1024;
const PNG = [0x89, 0x50, 0x4e, 0x47];
const DAY = /^\d{4}-\d{2}-\d{2}$/;
const text = (v: unknown, max: number) => (typeof v === 'string' ? v.trim().slice(0, max) : '');

/**
 * Whether the signed-in person is in the Cognito admins group. API Gateway
 * passes list claims as text like "[admins other]", so both forms are read.
 */
export function isAdmin(event: Event): boolean {
  const raw: unknown = event.requestContext.authorizer.jwt.claims['cognito:groups'];
  const groups = Array.isArray(raw)
    ? raw.map(String)
    : typeof raw === 'string'
      ? raw.replace(/^\[|\]$/g, '').split(/[\s,]+/)
      : [];
  return groups.includes(ADMIN_GROUP);
}

const note = (v: unknown) => (typeof v === 'string' ? v.trim().slice(0, 500) : '');

/**
 * The admin pages. Only people in the admins group get past the first line.
 *   GET    /admin/stats
 *   GET    /admin/review?before=<createdAt>      blocked posts awaiting review
 *   POST   /admin/posts/{id}/review              { decision: 'publish' | 'keep_blocked' }
 *   POST   /admin/posts/{id}/remove              { note }
 *   GET    /admin/users?q=<handle or name>
 *   PUT    /admin/users/{id}/suspension          { suspended, reason }
 *   DELETE /admin/users/{id}/photo
 *   GET    /admin/reports                        open reports, newest first
 *   POST   /admin/reports/{id}/resolve           { note }
 *   GET    /admin/dashboard?days=30               daily counts, retention and where people came from
 *   GET    /admin/audit?before=<at>               every admin action, newest first
 *   GET    /admin/promo?tab=pending|scheduled|done
 *   POST   /admin/promo/run                       the agent's morning pick, now
 *   POST   /admin/promo/{id}/decision             { approve, caption?, png? (base64 card), scheduledFor? }
 *   POST   /admin/promo/{id}/mark                 { status: 'posted' | 'withdrawn' }  done by hand
 *   GET    /admin/links                           link codes with clicks, sign-ups and who stayed
 *   POST   /admin/links                           { code, channel, label }
 *   GET    /admin/questions?from=<day>
 *   PUT    /admin/questions/{day}                 { textKo, textEn, approve }
 */
export const adminHandler = (deps: Deps) =>
  safely(async (event: Event) => {
    if (!isAdmin(event)) return json(403, { error: 'forbidden' });
    const me = userId(event);
    const id = event.pathParameters?.id;
    const { admin } = deps;

    switch (event.routeKey) {
      case 'GET /admin/stats':
        return json(200, await admin.stats());

      case 'GET /admin/review': {
        const before = event.queryStringParameters?.before;
        const items = await admin.reviewQueue(PAGE_SIZE, before && !Number.isNaN(Date.parse(before)) ? before : undefined);
        const last = items.at(-1);
        return json(200, { items, next: items.length === PAGE_SIZE && last ? last.createdAt : null });
      }

      case 'POST /admin/posts/{id}/review': {
        const decision = parseBody(event)?.decision;
        if (!isUuid(id) || (decision !== 'publish' && decision !== 'keep_blocked')) {
          return json(400, { error: 'bad_request' });
        }
        return (await admin.reviewPost(id, me, decision)) ? json(204, null) : json(404, { error: 'not_found' });
      }

      case 'POST /admin/posts/{id}/remove': {
        if (!isUuid(id)) return json(400, { error: 'bad_request' });
        const done = await admin.removePost(id, me, note(parseBody(event)?.note));
        return done ? json(204, null) : json(404, { error: 'not_found' });
      }

      case 'GET /admin/users': {
        const q = (event.queryStringParameters?.q ?? '').trim().toLowerCase().replace(/^@/, '').slice(0, 40);
        const users = await admin.searchUsers(q, PAGE_SIZE);
        return json(200, { items: users.map((u) => ({ ...u, photoUrl: photoUrl(u.photoKey) })) });
      }

      case 'PUT /admin/users/{id}/suspension': {
        const b = parseBody(event);
        if (!isUuid(id) || typeof b?.suspended !== 'boolean') return json(400, { error: 'bad_request' });
        if (id === me && b.suspended) return json(400, { error: 'self' });
        const done = await admin.setSuspended(id, me, b.suspended, note(b.reason));
        return done ? json(200, { suspended: b.suspended }) : json(404, { error: 'not_found' });
      }

      case 'GET /admin/reports':
        return json(200, { items: await admin.openReports(PAGE_SIZE) });

      case 'POST /admin/reports/{id}/resolve': {
        if (!id || !/^\d{1,18}$/.test(id)) return json(400, { error: 'bad_request' });
        const done = await admin.resolveReport(id, me, note(parseBody(event)?.note));
        return done ? json(204, null) : json(404, { error: 'not_found' });
      }

      case 'GET /admin/dashboard': {
        const days = Number(event.queryStringParameters?.days ?? 30);
        return json(200, await deps.growth.dashboard(Number.isInteger(days) ? Math.min(90, Math.max(7, days)) : 30));
      }

      case 'GET /admin/audit': {
        const before = event.queryStringParameters?.before;
        const items = await deps.growth.audit(PAGE_SIZE, before && !Number.isNaN(Date.parse(before)) ? before : undefined);
        const last = items.at(-1);
        return json(200, { items, next: items.length === PAGE_SIZE && last ? last.at : null });
      }

      case 'GET /admin/promo': {
        const statuses = PROMO_TABS[event.queryStringParameters?.tab ?? 'pending'];
        if (!statuses) return json(400, { error: 'bad_request' });
        const [items, channels] = await Promise.all([deps.growth.promoItems(statuses, 50), deps.channels()]);
        return json(200, { items: items.map((i) => ({ ...i, cardUrl: photoUrl(i.cardKey) })), channels });
      }

      case 'POST /admin/promo/run':
        return json(200, { added: await deps.pickNow() });

      case 'POST /admin/promo/{id}/decision': {
        const b = parseBody(event);
        if (!isUuid(id) || typeof b?.approve !== 'boolean') return json(400, { error: 'bad_request' });
        const at = typeof b.scheduledFor === 'string' && !Number.isNaN(Date.parse(b.scheduledFor)) ? b.scheduledFor : undefined;
        const caption = typeof b.caption === 'string' ? text(b.caption, 300) : undefined;
        let cardKey: string | undefined;
        if (b.approve && typeof b.png === 'string') {
          const png = Buffer.from(b.png, 'base64');
          if (png.length > MAX_CARD_BYTES || !PNG.every((x, k) => png[k] === x)) return json(400, { error: 'bad_image' });
          // A new key each time, so the CDN never serves an older card.
          cardKey = `photos/promo/${id}-${randomUUID().slice(0, 8)}.png`;
          await deps.photoStore.put(cardKey, png, 'image/png');
        }
        const done = await deps.growth.decidePromo(id, me, { approve: b.approve, caption, cardKey, scheduledFor: at });
        return done ? json(204, null) : json(404, { error: 'not_found' });
      }

      case 'POST /admin/promo/{id}/mark': {
        const status = parseBody(event)?.status;
        if (!isUuid(id) || (status !== 'posted' && status !== 'withdrawn')) return json(400, { error: 'bad_request' });
        return (await deps.growth.markPromo(id, me, status)) ? json(204, null) : json(404, { error: 'not_found' });
      }

      case 'GET /admin/links':
        return json(200, { items: await deps.growth.linkStats(100) });

      case 'POST /admin/links': {
        const b = parseBody(event);
        const code = text(b?.code, 32).toLowerCase();
        if (!LINK_CODE.test(code) || !isChannel(b?.channel)) return json(400, { error: 'bad_request' });
        const made = await deps.growth.createLinkCode(me, code, b.channel, text(b.label, 80));
        return made === 'ok' ? json(201, { code }) : json(409, { error: 'taken' });
      }

      case 'GET /admin/questions': {
        const from = event.queryStringParameters?.from;
        const day = from && DAY.test(from) ? from : new Date(Date.now() + 9 * 3600_000).toISOString().slice(0, 10);
        return json(200, { items: await deps.growth.questions(day, 60) });
      }

      case 'PUT /admin/questions/{day}': {
        const day = event.pathParameters?.day;
        const b = parseBody(event);
        const textKo = text(b?.textKo, 80);
        const textEn = text(b?.textEn, 160);
        if (!day || !DAY.test(day) || Number.isNaN(Date.parse(day)) || !textKo || !textEn || typeof b?.approve !== 'boolean') {
          return json(400, { error: 'bad_request' });
        }
        return json(200, await deps.growth.saveQuestion(me, { day, textKo, textEn, approve: b.approve }));
      }

      case 'DELETE /admin/users/{id}/photo': {
        if (!isUuid(id)) return json(400, { error: 'bad_request' });
        const result = await admin.removePhoto(id, me);
        if (!result) return json(404, { error: 'not_found' });
        if (result.previous) await deps.photoStore.remove(result.previous);
        return json(204, null);
      }
    }
    return json(404, { error: 'not_found' });
  });

let live: Deps | undefined;
export const handler = (event: Event) =>
  adminHandler(
    (live ??= (() => {
      const growth = new AuroraGrowthRepository();
      const photoStore = new S3PhotoStore();
      const tokens = new TokenSecret();
      return {
        admin: new AuroraAdminRepository(),
        photoStore,
        growth,
        pickNow: () => pickCandidates({ store: growth, copywriter: new ClaudeCopywriter(), cards: photoStore }),
        channels: async () => publishersFrom(await tokens.read()).map((p) => p.channel),
      };
    })()),
  )(event);
