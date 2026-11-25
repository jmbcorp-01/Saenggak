import { isLang, translateFeed } from '../posts/feed.js';
import { deletePost } from '../posts/publish.js';
import { DAYS_TO_FOLLOW } from '../rules/follow.js';
import {
  REPORT_REASONS,
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
import { isAdmin } from './admin.js';
import { isUuid, json, parseBody, safely, userId, type Event } from './http.js';

const PAGE_SIZE = 30;
type Deps = {
  repo: Repository;
  social: SocialRepository;
  translator: Translator;
  photoStore: PhotoStore;
  users: UserDirectory;
};

const isReason = (v: unknown): v is ReportReason => REPORT_REASONS.includes(v as ReportReason);

/**
 * Everything except writing posts:
 *   GET    /feed?tab=all|following&author=<id>&lang=ko|en&before=<createdAt>
 *   POST   /posts/{id}/empathy
 *   DELETE /posts/{id}
 *   GET    /me
 *   DELETE /me                  erases the account and everything in it
 *   GET    /users/{id}
 *   PUT    /users/{id}/follow    DELETE /users/{id}/follow
 *   POST   /posts/{id}/report    POST /users/{id}/report    { reason, note }
 *   PUT    /users/{id}/block     DELETE /users/{id}/block   GET /me/blocks
 *   GET    /notifications?before=<at>    POST /notifications/seen
 */
export const apiHandler = (deps: Deps) => safely(async (event: Event) => {
  const me = userId(event);
  const id = event.pathParameters?.id;
  const { repo, social } = deps;

  switch (event.routeKey) {
    case 'GET /feed': {
      const q = event.queryStringParameters ?? {};
      const lang = isLang(q.lang) ? q.lang : 'ko';
      const before = q.before && !Number.isNaN(Date.parse(q.before)) ? q.before : undefined;
      if (q.author !== undefined && !isUuid(q.author)) return json(400, { error: 'bad_request' });
      const posts = await repo.feed(me, { following: q.tab === 'following', authorId: q.author, before, limit: PAGE_SIZE });
      const items = await translateFeed(deps, posts, lang);
      const last = items.at(-1);
      return json(200, {
        items: items.map((p) => ({ ...p, photoUrl: photoUrl(p.photoKey) })),
        next: items.length === PAGE_SIZE && last ? last.createdAt : null });
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
    }),
  )(event);
