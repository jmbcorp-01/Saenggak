import { isLang, translateFeed } from '../posts/feed.js';
import { deletePost } from '../posts/publish.js';
import { DAYS_TO_FOLLOW } from '../rules/follow.js';
import type { Repository, Translator } from '../services/ports.js';
import { AuroraRepository } from '../services/repository.js';
import { AwsTranslator } from '../services/translator.js';
import { isUuid, json, parseBody, userId, type Event } from './http.js';

const PAGE_SIZE = 30;
const HANDLE = /^[a-z0-9_]{3,20}$/;
type Deps = { repo: Repository; translator: Translator };

/**
 * Everything except writing posts:
 *   GET    /feed?tab=all|following&author=<id>&lang=ko|en&before=<createdAt>
 *   POST   /posts/{id}/empathy
 *   DELETE /posts/{id}
 *   GET    /me            PUT /me { handle, displayName, bio, locale, timeZone }
 *   GET    /users/{id}
 *   PUT    /users/{id}/follow    DELETE /users/{id}/follow
 */
export const apiHandler = (deps: Deps) => async (event: Event) => {
  const me = userId(event);
  const id = event.pathParameters?.id;
  const { repo } = deps;

  switch (event.routeKey) {
    case 'GET /feed': {
      const q = event.queryStringParameters ?? {};
      const lang = isLang(q.lang) ? q.lang : 'ko';
      const before = q.before && !Number.isNaN(Date.parse(q.before)) ? q.before : undefined;
      if (q.author !== undefined && !isUuid(q.author)) return json(400, { error: 'bad_request' });
      const posts = await repo.feed(me, { following: q.tab === 'following', authorId: q.author, before, limit: PAGE_SIZE });
      const items = await translateFeed(deps, posts, lang);
      const last = items.at(-1);
      return json(200, { items, next: items.length === PAGE_SIZE && last ? last.createdAt : null });
    }

    case 'POST /posts/{id}/empathy': {
      if (!isUuid(id)) return json(400, { error: 'bad_request' });
      const result = await repo.toggleEmpathy(id, me);
      return result ? json(200, result) : json(404, { error: 'not_found' });
    }

    case 'DELETE /posts/{id}': {
      if (!isUuid(id)) return json(400, { error: 'bad_request' });
      return (await deletePost(repo, id, me)) ? json(204, null) : json(404, { error: 'not_found' });
    }

    case 'GET /me':
    case 'GET /users/{id}': {
      const target = event.routeKey === 'GET /me' ? me : id;
      if (!isUuid(target)) return json(400, { error: 'bad_request' });
      const profile = await repo.profile(target, me);
      if (!profile) return json(404, { error: 'not_found' });
      return json(200, { ...profile, daysToFollow: DAYS_TO_FOLLOW, isMe: target === me });
    }

    case 'PUT /me': {
      const b = parseBody(event);
      const handle = typeof b?.handle === 'string' ? b.handle.trim().toLowerCase() : '';
      const displayName = typeof b?.displayName === 'string' ? b.displayName.trim() : '';
      const bio = typeof b?.bio === 'string' ? b.bio.trim() : '';
      const locale = isLang(b?.locale) ? b.locale : 'ko';
      const timeZone = typeof b?.timeZone === 'string' && validTimeZone(b.timeZone) ? b.timeZone : 'Asia/Seoul';
      if (!HANDLE.test(handle) || displayName.length === 0 || displayName.length > 30 || bio.length > 160) {
        return json(400, { error: 'bad_request' });
      }
      const saved = await repo.saveProfile(me, { handle, displayName, bio, locale, timeZone });
      if (saved === 'handle_taken') return json(409, { error: 'handle_taken' });
      return json(200, { ...(await repo.profile(me, me)), daysToFollow: DAYS_TO_FOLLOW, isMe: true });
    }

    case 'PUT /users/{id}/follow': {
      if (!isUuid(id)) return json(400, { error: 'bad_request' });
      const result = await repo.follow(me, id);
      if (result === 'ok') return json(200, { following: true });
      if (result === 'not_found') return json(404, { error: 'not_found' });
      return json(403, { error: result });
    }

    case 'DELETE /users/{id}/follow': {
      if (!isUuid(id)) return json(400, { error: 'bad_request' });
      await repo.unfollow(me, id);
      return json(200, { following: false });
    }
  }
  return json(404, { error: 'not_found' });
};

function validTimeZone(tz: string): boolean {
  try {
    new Intl.DateTimeFormat('en', { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

let live: Deps | undefined;
export const handler = (event: Event) =>
  apiHandler((live ??= { repo: new AuroraRepository(), translator: new AwsTranslator() }))(event);
