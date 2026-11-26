import { isLang, spreadAuthors, translateFeed } from '../posts/feed.js';
import { deletePost } from '../posts/publish.js';
import { DAYS_TO_FOLLOW } from '../rules/follow.js';
import { evaluate, parseSession } from '../rules/humanCheck.js';
import { CHECK_PHRASES, isCheckPhrase, needsHumanCheck, type ActionKind } from '../rules/risk.js';
import {
  REPORT_REASONS,
  type Embedder,
  type FeedPost,
  type PhotoStore,
  type ReportReason,
  type Repository,
  type SocialRepository,
  type Translator,
  type UserDirectory,
} from '../services/ports.js';
import { AuroraRepository } from '../services/repository.js';
import { AuroraSocialRepository } from '../services/socialRepository.js';
import { photoUrl, S3PhotoStore } from '../services/photos.js';
import { CognitoUserDirectory } from '../services/users.js';
import { AwsTranslator } from '../services/translator.js';
import { TitanEmbedder } from '../services/embedder.js';
import { isAdmin } from './admin.js';
import { isUuid, json, parseBody, safely, userId, type Event } from './http.js';

const PAGE_SIZE = 30;
type Deps = {
  repo: Repository;
  social: SocialRepository;
  translator: Translator;
  photoStore: PhotoStore;
  users: UserDirectory;
  embedder: Embedder;
};

/** Meaning search returns posts at most this far in cosine distance. */
export const SEARCH_MAX_DISTANCE = 0.75;
const SEARCH_LIMIT = 20;

const isReason = (v: unknown): v is ReportReason => REPORT_REASONS.includes(v as ReportReason);

/**
 * Everything except writing posts:
 *   GET    /feed?tab=all|latest|following&author=<id>&lang=ko|en&cursor=<next>
 *          "all" is the 추천 order; author pages, "latest" and "following" are newest first
 *   GET    /posts/{id}?lang=      PUT|DELETE /posts/{id}/bookmark    GET /bookmarks?cursor=
 *   GET    /search/users?q=       GET /search/posts?q=&lang=
 *   GET    /me/export             everything stored about the reader, as JSON
 *   GET    /me/human-check?lang=  POST /me/human-check { text, session }
 *   POST   /posts/{id}/empathy
 *   DELETE /posts/{id}
 *   GET    /me
 *   DELETE /me                  erases the account and everything in it
 *   GET    /users/{id}
 *   PUT    /users/{id}/follow    DELETE /users/{id}/follow
 *   PUT    /users/{id}/alerts    DELETE /users/{id}/alerts   alerts for their new posts
 *   POST   /posts/{id}/report    POST /users/{id}/report    { reason, note }
 *   PUT    /users/{id}/block     DELETE /users/{id}/block   GET /me/blocks
 *   GET    /notifications?before=<at>    POST /notifications/seen
 */
export const apiHandler = (deps: Deps) => safely(async (event: Event) => {
  const me = userId(event);
  const id = event.pathParameters?.id;
  const { repo, social } = deps;
  const q = event.queryStringParameters ?? {};
  const lang = isLang(q.lang) ? q.lang : 'en';
  const shown = async (posts: FeedPost[]) =>
    (await translateFeed(deps, posts, lang)).map((p) => ({ ...p, photoUrl: photoUrl(p.photoKey) }));

  /**
   * Activity that looks automated must pass a typing check first (428). Then
   * the action is counted for the next check.
   */
  const guard = async (kind: ActionKind) => {
    if (needsHumanCheck(await repo.activity(me))) return json(428, { error: 'human_check' });
    await repo.recordAction(me, kind);
    return null;
  };

  switch (event.routeKey) {
    case 'GET /feed': {
      const cursor = q.cursor ?? q.before;
      if (q.author !== undefined && !isUuid(q.author)) return json(400, { error: 'bad_request' });
      const following = q.tab === 'following';
      const ranked = !following && q.author === undefined && q.tab !== 'latest';
      if (ranked) {
        const offset = cursor && /^\d{1,6}$/.test(cursor) ? Number(cursor) : 0;
        const posts = await repo.feed(me, { following: false, ranked: true, offset, limit: PAGE_SIZE });
        return json(200, {
          items: await shown(spreadAuthors(posts)),
          next: posts.length === PAGE_SIZE ? String(offset + PAGE_SIZE) : null,
        });
      }
      const before = cursor && !Number.isNaN(Date.parse(cursor)) ? cursor : undefined;
      const posts = await repo.feed(me, { following, authorId: q.author, before, limit: PAGE_SIZE });
      const last = posts.at(-1);
      return json(200, { items: await shown(posts), next: posts.length === PAGE_SIZE && last ? last.createdAt : null });
    }

    case 'GET /posts/{id}': {
      if (!isUuid(id)) return json(400, { error: 'bad_request' });
      const post = await repo.post(me, id);
      if (!post) return json(404, { error: 'not_found' });
      return json(200, (await shown([post]))[0]);
    }

    case 'PUT /posts/{id}/bookmark':
    case 'DELETE /posts/{id}/bookmark': {
      if (!isUuid(id)) return json(400, { error: 'bad_request' });
      const saved = event.routeKey === 'PUT /posts/{id}/bookmark';
      return (await repo.setBookmark(me, id, saved)) ? json(200, { saved }) : json(404, { error: 'not_found' });
    }

    case 'GET /bookmarks': {
      // Paged by when each post was saved.
      const before = q.cursor && !Number.isNaN(Date.parse(q.cursor)) ? q.cursor : undefined;
      const posts = await repo.feed(me, { following: false, saved: true, before, limit: PAGE_SIZE });
      return json(200, { items: await shown(posts), next: null });
    }

    case 'GET /search/users': {
      const query = (q.q ?? '').trim().slice(0, 50);
      if (query.replace(/^@/, '').length === 0) return json(200, { items: [] });
      const users = await repo.findUsers(me, query, SEARCH_LIMIT);
      return json(200, { items: users.map(({ photoKey, ...u }) => ({ ...u, photoUrl: photoUrl(photoKey) })) });
    }

    case 'GET /search/posts': {
      const query = (q.q ?? '').trim().slice(0, 200);
      if ([...query].length < 2) return json(200, { items: [] });
      const embedding = await deps.embedder.embed(query);
      const posts = await repo.searchPosts(me, embedding, SEARCH_MAX_DISTANCE, SEARCH_LIMIT);
      return json(200, { items: await shown(posts) });
    }

    case 'GET /me/export': {
      const data = await repo.exportData(me);
      return data ? json(200, data) : json(404, { error: 'not_found' });
    }

    case 'GET /me/human-check': {
      const list = CHECK_PHRASES[lang];
      return json(200, { phrase: list[Math.floor(Math.random() * list.length)] });
    }

    case 'POST /me/human-check': {
      const b = parseBody(event);
      const text = typeof b?.text === 'string' ? b.text : '';
      const session = parseSession(b?.session);
      const passed = isCheckPhrase(text) && session !== null && evaluate(session, [...text].length).length === 0;
      if (!passed) {
        await repo.recordAction(me, 'check_failed');
        return json(400, { error: 'not_human' });
      }
      await repo.setHumanChecked(me);
      return json(204, null);
    }

    case 'POST /posts/{id}/empathy': {
      if (!isUuid(id)) return json(400, { error: 'bad_request' });
      const stop = await guard('empathy');
      if (stop) return stop;
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
      return json(200, {
        ...profile,
        photoUrl: photoUrl(profile.photoKey),
        daysToFollow: DAYS_TO_FOLLOW,
        isMe: target === me,
        // Only the reader learns this about themselves; it shows the admin pages' entry.
        ...(target === me ? { isAdmin: isAdmin(event) } : {}),
      });
    }

    case 'DELETE /me': {
      // Data first, then the photo, then the sign-in account. If a later step
      // fails, asking again finishes it: each step is safe to repeat.
      const gone = await repo.deleteAccount(me);
      if (gone && gone.photoKey) await deps.photoStore.remove(gone.photoKey);
      await deps.users.deleteUser(me);
      return json(204, null);
    }

    case 'POST /posts/{id}/report':
    case 'POST /users/{id}/report': {
      const b = parseBody(event);
      if (!isUuid(id) || !isReason(b?.reason)) return json(400, { error: 'bad_request' });
      const stop = await guard('report');
      if (stop) return stop;
      const onPost = event.routeKey === 'POST /posts/{id}/report';
      const post = onPost ? await repo.postState(id) : null;
      if (onPost && !post) return json(404, { error: 'not_found' });
      const result = await social.report(me, {
        userId: post ? post.authorId : id,
        postId: onPost ? id : undefined,
        reason: b.reason,
        note: typeof b.note === 'string' ? b.note.trim().slice(0, 500) : '',
      });
      if (result === 'self') return json(400, { error: 'self' });
      return result === 'ok' ? json(204, null) : json(404, { error: 'not_found' });
    }

    case 'PUT /users/{id}/block': {
      if (!isUuid(id)) return json(400, { error: 'bad_request' });
      const stop = await guard('block');
      if (stop) return stop;
      const result = await social.block(me, id);
      if (result === 'self') return json(400, { error: 'self' });
      return result === 'ok' ? json(200, { blocked: true }) : json(404, { error: 'not_found' });
    }

    case 'DELETE /users/{id}/block': {
      if (!isUuid(id)) return json(400, { error: 'bad_request' });
      await social.unblock(me, id);
      return json(200, { blocked: false });
    }

    case 'GET /me/blocks':
      return json(200, { items: await social.blocked(me) });

    case 'GET /notifications': {
      const before = event.queryStringParameters?.before;
      const page = await social.notifications(me, PAGE_SIZE, before && !Number.isNaN(Date.parse(before)) ? before : undefined);
      const last = page.items.at(-1);
      return json(200, {
        items: page.items.map(({ actorPhotoKey, ...n }) => ({ ...n, actorPhotoUrl: photoUrl(actorPhotoKey) })),
        unread: page.unread,
        next: page.items.length === PAGE_SIZE && last ? last.at : null,
      });
    }

    case 'POST /notifications/seen':
      await social.markNotificationsSeen(me);
      return json(204, null);

    case 'PUT /users/{id}/follow': {
      if (!isUuid(id)) return json(400, { error: 'bad_request' });
      const stop = await guard('follow');
      if (stop) return stop;
      const result = await repo.follow(me, id);
      if (result === 'ok') return json(200, { following: true });
      if (result === 'not_found') return json(404, { error: 'not_found' });
      return json(403, { error: result });
    }

    case 'PUT /users/{id}/alerts':
    case 'DELETE /users/{id}/alerts': {
      if (!isUuid(id)) return json(400, { error: 'bad_request' });
      const on = event.routeKey === 'PUT /users/{id}/alerts';
      // Only for people the reader follows.
      return (await repo.setPostAlerts(me, id, on)) ? json(200, { alerts: on }) : json(404, { error: 'not_following' });
    }

    case 'DELETE /users/{id}/follow': {
      if (!isUuid(id)) return json(400, { error: 'bad_request' });
      await repo.unfollow(me, id);
      return json(200, { following: false });
    }
  }
  return json(404, { error: 'not_found' });
});

let live: Deps | undefined;
export const handler = (event: Event) =>
  apiHandler(
    (live ??= {
      repo: new AuroraRepository(),
      social: new AuroraSocialRepository(),
      translator: new AwsTranslator(),
      photoStore: new S3PhotoStore(),
      users: new CognitoUserDirectory(),
      embedder: new TitanEmbedder(),
    }),
  )(event);
