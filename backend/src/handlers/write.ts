import { isLang } from '../posts/feed.js';
import { savePhoto, type PhotoDeps } from '../posts/photo.js';
import { editPost, publishPost, WRITES_PER_HOUR, type EditResult, type PublishDeps } from '../posts/publish.js';
import { DAYS_TO_FOLLOW } from '../rules/follow.js';
import { ClaudeContentFilter } from '../services/contentFilter.js';
import { TitanEmbedder } from '../services/embedder.js';
import { photoUrl, RekognitionPhotoChecker, S3PhotoStore } from '../services/photos.js';
import { AuroraRepository } from '../services/repository.js';
import { isUuid, json, parseBody, safely, userId, validTimeZone, type Event } from './http.js';

const HANDLE = /^[a-z0-9_]{3,20}$/;

/**
 * Every route that calls the content filter:
 *   POST  /posts       { text, session }
 *   PATCH /posts/{id}  { text, session }
 *   PUT   /me          { handle, displayName, bio, locale, timeZone }
 *   PUT   /me/photo    { jpeg: base64 }  one clear human face, taken with the camera
 * Posts run the full check: length, hand typing, content filter. The writer's
 * day comes from their profile's time zone; a localDate sent by older apps is ignored.
 */
export type WriteDeps = PublishDeps & PhotoDeps;

export const writeHandler = (deps: WriteDeps) =>
  safely(async (event: Event) => {
    if (event.routeKey === 'PUT /me') return saveProfile(deps, event);
    if (event.routeKey === 'PUT /me/photo') return putPhoto(deps, event);

    const body = parseBody(event);
    if (!body || typeof body.text !== 'string') return json(400, { error: 'bad_request' });
    const input = { authorId: userId(event), text: body.text, session: body.session };

    let result: EditResult;
    if (event.routeKey === 'PATCH /posts/{id}') {
      const postId = event.pathParameters?.id;
      if (!isUuid(postId)) return json(400, { error: 'bad_request' });
      result = await editPost(deps, { ...input, postId });
    } else {
      result = await publishPost(deps, input);
    }

    switch (result.kind) {
      case 'invalid_length':
        return json(422, { error: 'invalid_length', verdict: result.verdict });
      case 'not_human':
        return json(422, { error: 'not_human', issues: result.issues });
      case 'blocked':
        return json(422, { error: 'blocked', reason: result.reason, followUnlocked: result.followUnlocked });
      case 'not_found':
        return json(404, { error: 'not_found' });
      case 'locked':
        return json(409, { error: 'locked' });
      case 'profile_required':
        return json(409, { error: 'profile_required' });
      case 'rate_limited':
        return json(429, { error: 'rate_limited' });
      case 'filter_unavailable':
        return json(503, { error: 'filter_unavailable' });
      case 'published':
        return json(event.routeKey === 'POST /posts' ? 201 : 200, {
          id: result.postId,
          typingMs: result.typingMs,
          similar: result.similar,
          firstPhrases: result.firstPhrases.map((p) => p.text),
          writingDays: result.writingDays,
          followUnlocked: result.followUnlocked,
        });
    }
  });

/** Name and bio are seen by everyone, so a change to them goes through the filter too. */
async function saveProfile({ repo, filter }: PublishDeps, event: Event) {
  const me = userId(event);
  const b = parseBody(event);
  const handle = typeof b?.handle === 'string' ? b.handle.trim().toLowerCase() : '';
  const displayName = typeof b?.displayName === 'string' ? b.displayName.trim() : '';
  const bio = typeof b?.bio === 'string' ? b.bio.trim() : '';
  const locale = isLang(b?.locale) ? b.locale : 'ko';
  const timeZone = typeof b?.timeZone === 'string' && validTimeZone(b.timeZone) ? b.timeZone : 'Asia/Seoul';
  if (!HANDLE.test(handle) || displayName.length === 0 || [...displayName].length > 30 || [...bio].length > 160) {
    return json(400, { error: 'bad_request' });
  }

  const current = await repo.profile(me, me);
  const textChanged = !current || current.displayName !== displayName || current.bio !== bio || current.handle !== handle;
  if (textChanged) {
    if (!(await repo.recordWrite(me, WRITES_PER_HOUR))) return json(429, { error: 'rate_limited' });
    const allowed = await filter.moderateProfile({ name: `${displayName} (@${handle})`, bio });
    if (!allowed) return json(422, { error: 'profile_blocked' });
  }

  const saved = await repo.saveProfile(me, { handle, displayName, bio, locale, timeZone });
  if (saved === 'handle_taken') return json(409, { error: 'handle_taken' });
  return json(200, await myProfile(repo, me));
}

async function myProfile(repo: PublishDeps['repo'], me: string) {
  const profile = await repo.profile(me, me);
  return { ...profile, photoUrl: photoUrl(profile?.photoKey), daysToFollow: DAYS_TO_FOLLOW, isMe: true };
}

async function putPhoto(deps: WriteDeps, event: Event) {
  const me = userId(event);
  const result = await savePhoto(deps, me, parseBody(event)?.jpeg);
  switch (result.kind) {
    case 'bad_image':
      return json(400, { error: 'bad_image' });
    case 'profile_required':
      return json(409, { error: 'profile_required' });
    case 'rate_limited':
      return json(429, { error: 'rate_limited' });
    case 'refused':
      return json(422, { error: 'photo_refused', problem: result.problem });
    case 'saved':
      return json(200, await myProfile(deps.repo, me));
  }
}

let live: WriteDeps | undefined;
export const handler = (event: Event) =>
  writeHandler(
    (live ??= {
      repo: new AuroraRepository(),
      filter: new ClaudeContentFilter(),
      embedder: new TitanEmbedder(),
      photoChecker: new RekognitionPhotoChecker(),
      photoStore: new S3PhotoStore(),
    }),
  )(event);
