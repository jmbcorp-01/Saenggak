import { publishPost, type PublishDeps } from '../posts/publish.js';
import { ClaudeContentFilter } from '../services/contentFilter.js';
import { TitanEmbedder } from '../services/embedder.js';
import { AuroraRepository } from '../services/repository.js';
import { json, parseBody, userId, type Event } from './http.js';

/** POST /posts  { text, session, localDate } */
export const createPostHandler = (deps: PublishDeps) => async (event: Event) => {
  const body = parseBody(event);
  if (!body || typeof body.text !== 'string' || typeof body.localDate !== 'string') {
    return json(400, { error: 'bad_request' });
  }

  const result = await publishPost(deps, {
    authorId: userId(event),
    text: body.text,
    session: body.session,
    localDate: body.localDate,
  });

  switch (result.kind) {
    case 'invalid_length':
      return json(422, { error: 'invalid_length', verdict: result.verdict });
    case 'not_human':
      return json(422, { error: 'not_human', issues: result.issues });
    case 'blocked':
      return json(422, { error: 'blocked', reason: result.reason, followUnlocked: result.followUnlocked });
    case 'published':
      return json(201, {
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
  createPostHandler(
    (live ??= { repo: new AuroraRepository(), filter: new ClaudeContentFilter(), embedder: new TitanEmbedder() }),
  )(event);
