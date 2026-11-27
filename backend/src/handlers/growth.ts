import { isCode } from '../growth/codes.js';
import type { GrowthRepository } from '../services/growthPorts.js';
import { AuroraGrowthRepository } from '../services/growthRepository.js';
import { isUuid, json, parseBody, safely, userId, type Event } from './http.js';

type Deps = { growth: GrowthRepository; site: string };

/**
 * The reader's side of growth:
 *   GET  /me/sharing              { shareOk, anonymous }
 *   PUT  /me/sharing              { shareOk, anonymous }  off until the writer turns it on
 *   PUT  /posts/{id}/sharing      { excluded }             keeps one post out of sharing
 *   GET  /me/invite               { code, url }            the reader's own invite link
 *   POST /me/source               { code }                 where a new person came from, once
 *   GET  /questions/today         { question: { ko, en } | null }
 */
export const growthHandler = (deps: Deps) =>
  safely(async (event: Event) => {
    const me = userId(event);
    const { growth } = deps;
    switch (event.routeKey) {
      case 'GET /me/sharing': {
        const s = await growth.sharing(me);
        return s ? json(200, s) : json(409, { error: 'profile_required' });
      }

      case 'PUT /me/sharing': {
        const b = parseBody(event);
        if (typeof b?.shareOk !== 'boolean' || (b.anonymous !== undefined && typeof b.anonymous !== 'boolean')) {
          return json(400, { error: 'bad_request' });
        }
        const s = { shareOk: b.shareOk, anonymous: b.anonymous === true };
        return (await growth.setSharing(me, s)) ? json(200, s) : json(409, { error: 'profile_required' });
      }

      case 'PUT /posts/{id}/sharing': {
        const id = event.pathParameters?.id;
        const b = parseBody(event);
        if (!isUuid(id) || typeof b?.excluded !== 'boolean') return json(400, { error: 'bad_request' });
        return (await growth.setPostExcluded(me, id, b.excluded))
          ? json(200, { excluded: b.excluded })
          : json(404, { error: 'not_found' });
      }

      case 'GET /me/invite': {
        const code = await growth.inviteCode(me);
        return code ? json(200, { code, url: `${deps.site}/i/${code}` }) : json(409, { error: 'profile_required' });
      }

      case 'POST /me/source': {
        const code = parseBody(event)?.code;
        if (!isCode(code)) return json(400, { error: 'bad_request' });
        const result = await growth.recordSource(me, code);
        if (result === 'ok') return json(204, null);
        if (result === 'unknown_code') return json(404, { error: 'unknown_code' });
        if (result === 'profile_required') return json(409, { error: 'profile_required' });
        // Too late, already recorded, or one's own code: nothing to do, and nothing to fix.
        return json(200, { recorded: false, reason: result });
      }

      case 'GET /questions/today': {
        const q = await growth.todayQuestion(me);
        return json(200, { question: q ? { ko: q.textKo, en: q.textEn } : null });
      }
    }
    return json(404, { error: 'not_found' });
  });

let live: Deps | undefined;
export const handler = (event: Event) =>
  growthHandler((live ??= { growth: new AuroraGrowthRepository(), site: process.env.SITE_URL ?? '' }))(event);
