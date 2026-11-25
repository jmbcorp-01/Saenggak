import { checkLength, type LengthVerdict } from '../rules/weightedLength.js';
import { evaluate, parseSession, type HumanCheckIssue } from '../rules/humanCheck.js';
import { extractPhrases, pickFirstPhrases, type Phrase } from '../rules/phrases.js';
import { MAX_COSINE_DISTANCE, summarizeSimilar, type SimilarSummary } from '../rules/similar.js';
import { BLOCK_WINDOW_DAYS, followUnlocked } from '../rules/follow.js';
import type { ContentFilter, Embedder, ModerationReason, Repository } from '../services/ports.js';

export interface PublishDeps {
  repo: Repository;
  filter: ContentFilter;
  embedder: Embedder;
}

export interface PublishInput {
  authorId: string;
  /** The text exactly as typed, before trimming. */
  text: string;
  session: unknown;
  /** The writer's calendar day, YYYY-MM-DD, from their time zone. */
  localDate: string;
}

export type PublishResult =
  | { kind: 'invalid_length'; verdict: Exclude<LengthVerdict, 'ok'> }
  | { kind: 'not_human'; issues: HumanCheckIssue[] }
  | { kind: 'blocked'; reason: ModerationReason; followUnlocked: boolean }
  | {
      kind: 'published';
      postId: string;
      typingMs: number;
      similar: SimilarSummary;
      firstPhrases: Phrase[];
      writingDays: number;
      followUnlocked: boolean;
    };

/** Detects the post language. Korean and English at launch. */
export function detectLang(text: string): 'ko' | 'en' {
  return /[가-힣]/.test(text) ? 'ko' : 'en';
}

const DATE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * The full posting flow: length, human typing, content filter, then the
 * after-posting extras (similar thoughts, first-used phrases, follow status).
 */
export async function publishPost(deps: PublishDeps, input: PublishInput): Promise<PublishResult> {
  const { repo, filter, embedder } = deps;
  const body = input.text.trim();

  const verdict = checkLength(body);
  if (verdict !== 'ok') return { kind: 'invalid_length', verdict };

  const session = parseSession(input.session);
  if (!session || !DATE.test(input.localDate)) {
    return { kind: 'not_human', issues: ['invalid_session'] };
  }
  const issues = evaluate(session, [...input.text].length);
  if (issues.length > 0) return { kind: 'not_human', issues };

  const lang = detectLang(body);
  const moderation = await filter.moderate(body);
  if (!moderation.allowed) {
    await repo.insertPost({
      authorId: input.authorId,
      body,
      lang,
      typingMs: session.activeMs,
      localDate: input.localDate,
      status: 'blocked',
      blockedReason: moderation.reason,
      session,
      issues: [],
    });
    const unlocked = await refreshFollow(repo, input.authorId);
    return { kind: 'blocked', reason: moderation.reason, followUnlocked: unlocked };
  }

  const embedding = await embedder.embed(body);
  const postId = await repo.insertPost({
    authorId: input.authorId,
    body,
    lang,
    typingMs: session.activeMs,
    localDate: input.localDate,
    status: 'published',
    embedding,
    session,
    issues: [],
  });

  const [people, firsts, writingDays, unlocked] = await Promise.all([
    repo.countSimilarAuthors(postId, embedding, MAX_COSINE_DISTANCE),
    repo.claimPhrases(postId, input.authorId, extractPhrases(body)),
    repo.writingDays(input.authorId),
    refreshFollow(repo, input.authorId),
  ]);

  return {
    kind: 'published',
    postId,
    typingMs: session.activeMs,
    similar: summarizeSimilar(people),
    firstPhrases: pickFirstPhrases(firsts),
    writingDays,
    followUnlocked: unlocked,
  };
}

async function refreshFollow(repo: Repository, authorId: string): Promise<boolean> {
  const [writingDays, recentBlocks, daysSinceLoss] = await Promise.all([
    repo.writingDays(authorId),
    repo.recentBlocks(authorId, BLOCK_WINDOW_DAYS),
    repo.writingDaysSinceLoss(authorId),
  ]);
  const unlocked = followUnlocked({ writingDays, recentBlocks, daysSinceLoss });
  await repo.setFollowUnlocked(authorId, unlocked);
  return unlocked;
}
