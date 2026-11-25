import { isLang, translateFeed } from '../posts/feed.js';
import type { Repository, Translator } from '../services/ports.js';
import { AuroraRepository } from '../services/repository.js';
import { AwsTranslator } from '../services/translator.js';
import { json, userId, type Event } from './http.js';

const PAGE_SIZE = 30;
type Deps = { repo: Repository; translator: Translator };

/** GET /feed?tab=all|following&lang=ko|en&before=<createdAt> */
export const feedHandler = (deps: Deps) => async (event: Event) => {
  const q = event.queryStringParameters ?? {};
  const lang = isLang(q.lang) ? q.lang : 'ko';
  const before = q.before && !Number.isNaN(Date.parse(q.before)) ? q.before : undefined;

  const posts = await deps.repo.feed(userId(event), {
    following: q.tab === 'following',
    before,
    limit: PAGE_SIZE,
  });
  const items = await translateFeed(deps, posts, lang);
  const last = items.at(-1);
  return json(200, { items, next: items.length === PAGE_SIZE && last ? last.createdAt : null });
};

let live: Deps | undefined;
export const handler = (event: Event) =>
  feedHandler((live ??= { repo: new AuroraRepository(), translator: new AwsTranslator() }))(event);
