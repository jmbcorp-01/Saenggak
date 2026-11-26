import { checkLength, type LengthVerdict } from '../rules/weightedLength.js';
import { evaluate, parseSession, type HumanCheckIssue, type TypingSession } from '../rules/humanCheck.js';
import { extractPhrases, pickFirstPhrases, type Phrase } from '../rules/phrases.js';
import { MAX_COSINE_DISTANCE, summarizeSimilar, type SimilarSummary } from '../rules/similar.js';
import { BLOCK_WINDOW_DAYS, followUnlocked } from '../rules/follow.js';
import {
  NEAR_DUPLICATE_DISTANCE,
  contentScore,
  processScore,
  thoughtScore,
  type TextSignals,
} from '../rules/thoughtScore.js';
import type { ContentFilter, Embedder, ModerationReason, Repository } from '../services/ports.js';

/** Posts, edits and profile changes a writer can send per hour. Each one costs a filter call. */
export const WRITES_PER_HOUR = 20;

/**
 * First-used phrases are recorded from the first post but shown only once the
 * app holds this many posts. Before that almost every phrase is new, so the
 * label would mean nothing. Set FIRST_PHRASES_MIN_POSTS to change it.
 */
export const firstPhrasesMinPosts = () => Number(process.env.FIRST_PHRASES_MIN_POSTS ?? 10_000);

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
}

export interface EditInput extends PublishInput {
  postId: string;
}

type Rejected =
  | { kind: 'invalid_length'; verdict: Exclude<LengthVerdict, 'ok'> }
  | { kind: 'not_human'; issues: HumanCheckIssue[] }
  | { kind: 'blocked'; reason: ModerationReason; followUnlocked: boolean }
  | { kind: 'profile_required' }
  | { kind: 'rate_limited' }
  | { kind: 'filter_unavailable' };

export interface Published {
  kind: 'published';
  postId: string;
  typingMs: number;
  similar: SimilarSummary;
  firstPhrases: Phrase[];
  writingDays: number;
  followUnlocked: boolean;
}

export type PublishResult = Rejected | Published;
export type EditResult = Rejected | Published | { kind: 'not_found' } | { kind: 'locked' };

/** Detects the post language. Korean and English at launch. */
export function detectLang(text: string): 'ko' | 'en' {
  return /[가-힣]/.test(text) ? 'ko' : 'en';
}

interface Screened {
  body: string;
  lang: 'ko' | 'en';
  session: TypingSession;
  /** The writer's calendar day in their own time zone, worked out on the server. */
  localDate: string;
}

/**
 * Length and hand-typing checks. No service is called before these pass.
 * [baseText] is the text the draft started from: empty for a new post, the
 * current text for an edit, so the session only has to account for the change.
 */
function screen(input: PublishInput, baseText = ''): Omit<Screened, 'localDate'> | Rejected {
  const body = input.text.trim();
  const verdict = checkLength(body);
  if (verdict !== 'ok') return { kind: 'invalid_length', verdict };

  const session = parseSession(input.session);
  if (!session) return { kind: 'not_human', issues: ['invalid_session'] };
  const issues = evaluate(session, [...input.text].length - [...baseText].length);
  if (issues.length > 0) return { kind: 'not_human', issues };

  return { body, lang: detectLang(body), session };
}

/**
 * After the free checks pass: the writer's local day (which also confirms the
 * profile exists) and the hourly write limit, before any paid service is called.
 * The day comes from the profile's time zone, never from the client, so
 * writing days cannot be made up by sending other dates.
 */
async function prepare(
  repo: Repository,
  input: PublishInput,
  screened: Omit<Screened, 'localDate'> | Rejected,
): Promise<Screened | Rejected> {
  if ('kind' in screened) return screened;
  const [localDate, allowed] = await Promise.all([
    repo.localDate(input.authorId),
    repo.recordWrite(input.authorId, WRITES_PER_HOUR),
  ]);
  if (!localDate) return { kind: 'profile_required' };
  if (!allowed) return { kind: 'rate_limited' };
  return { ...screened, localDate };
}

/**
 * Runs the content filter. A blocked text is stored as a blocked post, so
 * blocked edits count toward losing follow permission just like new posts.
 */
async function moderate(
  deps: PublishDeps,
  input: PublishInput,
  s: Screened,
): Promise<Rejected | { signals: TextSignals | null }> {
  let verdict;
  try {
    verdict = await deps.filter.moderate(s.body);
  } catch (e) {
    console.error('content filter failed', e);
    return { kind: 'filter_unavailable' };
  }
  if (verdict.allowed) return { signals: verdict.signals ?? null };
  await deps.repo.insertPost({
    authorId: input.authorId,
    body: s.body,
    lang: s.lang,
    typingMs: s.session.activeMs,
    localDate: s.localDate,
    status: 'blocked',
    blockedReason: verdict.reason,
    session: s.session,
    issues: [],
  });
  const unlocked = await refreshFollow(deps.repo, input.authorId);
  return { kind: 'blocked', reason: verdict.reason, followUnlocked: unlocked };
}

/**
 * The content filter and the embedding run side by side, since the filter is
 * the slow step and most posts pass it. An embedding error only matters when
 * the post is allowed.
 */
async function moderateAndEmbed(
  deps: PublishDeps,
  input: PublishInput,
  s: Screened,
): Promise<Rejected | { signals: TextSignals | null; embedding: number[] }> {
  const embedding = deps.embedder.embed(s.body);
  // Keep an early failure from being reported as unhandled while the filter runs.
  embedding.catch(() => {});
  const moderated = await moderate(deps, input, s);
  if ('kind' in moderated) return moderated;
  return { signals: moderated.signals, embedding: await embedding };
}

/**
 * Similar thoughts, first-used phrases and follow status for a stored post,
 * and its thought score.
 */
async function extras(
  repo: Repository,
  postId: string,
  authorId: string,
  s: Screened,
  embedding: number[],
  signals: TextSignals | null,
): Promise<Published> {
  const [people, duplicates, firsts, showFirsts, writingDays, unlocked] = await Promise.all([
    repo.countSimilarAuthors(postId, embedding, MAX_COSINE_DISTANCE),
    repo.countSimilarAuthors(postId, embedding, NEAR_DUPLICATE_DISTANCE),
    repo.claimPhrases(postId, authorId, extractPhrases(s.body)),
    repo.hasPublished(firstPhrasesMinPosts()),
    repo.writingDays(authorId),
    refreshFollow(repo, authorId),
  ]);
  const process = processScore(s.session);
  const content = contentScore({ signals, nearDuplicate: duplicates > 0, firstPhrases: firsts.length });
  await repo.setThoughtScores(postId, { process, content, thought: thoughtScore(process, content) });
  return {
    kind: 'published',
    postId,
    typingMs: s.session.activeMs,
    similar: summarizeSimilar(people),
    firstPhrases: showFirsts ? pickFirstPhrases(firsts) : [],
    writingDays,
    followUnlocked: unlocked,
  };
}

/**
 * The full posting flow: length, human typing, content filter, then the
 * after-posting extras (similar thoughts, first-used phrases, follow status).
 */
export async function publishPost(deps: PublishDeps, input: PublishInput): Promise<PublishResult> {
  const s = await prepare(deps.repo, input, screen(input));
  if ('kind' in s) return s;
  const moderated = await moderateAndEmbed(deps, input, s);
  if ('kind' in moderated) return moderated;

  const { embedding } = moderated;
  const postId = await deps.repo.insertPost({
    authorId: input.authorId,
    body: s.body,
    lang: s.lang,
    typingMs: s.session.activeMs,
    localDate: s.localDate,
    status: 'published',
    embedding,
    session: s.session,
    issues: [],
  });
  return extras(deps.repo, postId, input.authorId, s, embedding, moderated.signals);
}

/**
 * Replaces a post's text. Allowed only for the author and only until the
 * first 공감. The new text goes through every check a new post does, and the
 * post's first-used phrases are worked out again from the new text. Typing
 * time spent on the edit is added to the post's typing time.
 */
export async function editPost(deps: PublishDeps, input: EditInput): Promise<EditResult> {
  const current = await deps.repo.postState(input.postId);
  if (!current || current.authorId !== input.authorId || current.status !== 'published') return { kind: 'not_found' };
  if (current.empathyCount > 0) return { kind: 'locked' };

  // The app opens the editor with the current text, so the session records only the change.
  const s = await prepare(deps.repo, input, screen(input, current.body));
  if ('kind' in s) return s;

  const moderated = await moderateAndEmbed(deps, input, s);
  if ('kind' in moderated) return moderated;

  const { embedding } = moderated;
  const updated = await deps.repo.updatePost(input.postId, input.authorId, {
    body: s.body,
    lang: s.lang,
    typingMs: s.session.activeMs,
    embedding,
    session: s.session,
  });
  // Someone may have sent the first 공감 while the filter was running.
  if (!updated) return { kind: 'locked' };
  return extras(deps.repo, input.postId, input.authorId, s, embedding, moderated.signals);
}

/** Deletes the author's post and rechecks follow permission, since writing days may drop. */
export async function deletePost(repo: Repository, postId: string, authorId: string): Promise<boolean> {
  const deleted = await repo.deletePost(postId, authorId);
  if (deleted) await refreshFollow(repo, authorId);
  return deleted;
}

export async function refreshFollow(repo: Repository, authorId: string): Promise<boolean> {
  const [writingDays, recentBlocks, daysSinceLoss] = await Promise.all([
    repo.writingDays(authorId),
    repo.recentBlocks(authorId, BLOCK_WINDOW_DAYS),
    repo.writingDaysSinceLoss(authorId),
  ]);
  const unlocked = followUnlocked({ writingDays, recentBlocks, daysSinceLoss });
  await repo.setFollowUnlocked(authorId, unlocked);
  return unlocked;
}
