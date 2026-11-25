import { checkLength, type LengthVerdict } from '../rules/weightedLength.js';
import { evaluate, parseSession, type HumanCheckIssue, type TypingSession } from '../rules/humanCheck.js';
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

export interface EditInput extends PublishInput {
  postId: string;
}

type Rejected =
  | { kind: 'invalid_length'; verdict: Exclude<LengthVerdict, 'ok'> }
  | { kind: 'not_human'; issues: HumanCheckIssue[] }
  | { kind: 'blocked'; reason: ModerationReason; followUnlocked: boolean };

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

const DATE = /^\d{4}-\d{2}-\d{2}$/;

interface Screened {
  body: string;
  lang: 'ko' | 'en';
  session: TypingSession;
}

/**
 * Length and hand-typing checks. No service is called before these pass.
 * [baseText] is the text the draft started from: empty for a new post, the
 * current text for an edit, so the session only has to account for the change.
 */
function screen(input: PublishInput, baseText = ''): Screened | Rejected {
  const body = input.text.trim();
  const verdict = checkLength(body);
  if (verdict !== 'ok') return { kind: 'invalid_length', verdict };

  const session = parseSession(input.session);
  if (!session || !DATE.test(input.localDate)) return { kind: 'not_human', issues: ['invalid_session'] };
  const issues = evaluate(session, [...input.text].length - [...baseText].length);
  if (issues.length > 0) return { kind: 'not_human', issues };

  return { body, lang: detectLang(body), session };
}

/**
 * Runs the content filter. A blocked text is stored as a blocked post, so
 * blocked edits count toward losing follow permission just like new posts.
 */
async function moderate(deps: PublishDeps, input: PublishInput, s: Screened): Promise<Rejected | null> {
  const verdict = await deps.filter.moderate(s.body);
  if (verdict.allowed) return null;
  await deps.repo.insertPost({
    authorId: input.authorId,
    body: s.body,
    lang: s.lang,
    typingMs: s.session.activeMs,
    localDate: input.localDate,
    status: 'blocked',
    blockedReason: verdict.reason,
    session: s.session,
    issues: [],
  });
  const unlocked = await refreshFollow(deps.repo, input.authorId);
  return { kind: 'blocked', reason: verdict.reason, followUnlocked: unlocked };
}

/** Similar thoughts, first-used phrases and follow status for a stored post. */
async function extras(repo: Repository, postId: string, authorId: string, s: Screened, embedding: number[]): Promise<Published> {
  const [people, firsts, writingDays, unlocked] = await Promise.all([
    repo.countSimilarAuthors(postId, embedding, MAX_COSINE_DISTANCE),
    repo.claimPhrases(postId, authorId, extractPhrases(s.body)),
    repo.writingDays(authorId),
    refreshFollow(repo, authorId),
  ]);
  return {
    kind: 'published',
    postId,
    typingMs: s.session.activeMs,
    similar: summarizeSimilar(people),
    firstPhrases: pickFirstPhrases(firsts),
    writingDays,
    followUnlocked: unlocked,
  };
}

/**
 * The full posting flow: length, human typing, content filter, then the
 * after-posting extras (similar thoughts, first-used phrases, follow status).
 */
export async function publishPost(deps: PublishDeps, input: PublishInput): Promise<PublishResult> {
  const s = screen(input);
  if ('kind' in s) return s;
  const rejected = await moderate(deps, input, s);
  if (rejected) return rejected;

  const embedding = await deps.embedder.embed(s.body);
  const postId = await deps.repo.insertPost({
    authorId: input.authorId,
    body: s.body,
    lang: s.lang,
    typingMs: s.session.activeMs,
    localDate: input.localDate,
    status: 'published',
    embedding,
    session: s.session,
    issues: [],
  });
  return extras(deps.repo, postId, input.authorId, s, embedding);
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
  const s = screen(input, current.body);
  if ('kind' in s) return s;

  const rejected = await moderate(deps, input, s);
  if (rejected) return rejected;

  const embedding = await deps.embedder.embed(s.body);
  const updated = await deps.repo.updatePost(input.postId, input.authorId, {
    body: s.body,
    lang: s.lang,
    typingMs: s.session.activeMs,
    embedding,
    session: s.session,
  });
  // Someone may have sent the first 공감 while the filter was running.
  if (!updated) return { kind: 'locked' };
  return extras(deps.repo, input.postId, input.authorId, s, embedding);
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
