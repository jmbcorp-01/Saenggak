import { editPost, publishPost, type EditResult, type PublishDeps } from '../posts/publish.js';
import { ClaudeContentFilter } from '../services/contentFilter.js';
import { TitanEmbedder } from '../services/embedder.js';
import { AuroraRepository } from '../services/repository.js';
import { isUuid, json, parseBody, userId, type Event } from './http.js';

/**
 * POST  /posts       { text, session, localDate }
 * PATCH /posts/{id}  { text, session, localDate }
 * Both run the full check: length, hand typing, content filter.
 */
export const writeHandler = (deps: PublishDeps) => async (event: Event) => {
  const body = parseBody(event);
  if (!body || typeof body.text !== 'string' || typeof body.localDate !== 'string') {
    return json(400, { error: 'bad_request' });
  }
  const input = { authorId: userId(event), text: body.text, session: body.session, localDate: body.localDate };

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
};

let live: PublishDeps | undefined;
export const handler = (event: Event) =>
  writeHandler(
    (live ??= { repo: new AuroraRepository(), filter: new ClaudeContentFilter(), embedder: new TitanEmbedder() }),
  )(event);
