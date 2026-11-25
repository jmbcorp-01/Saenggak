/**
 * Interfaces the handlers depend on, so the post flow can be tested without
 * AWS. Real implementations live next to this file.
 */
import type { TypingSession } from '../rules/humanCheck.js';
import type { Phrase } from '../rules/phrases.js';

export type ModerationVerdict =
  | { allowed: true }
  | { allowed: false; reason: ModerationReason };

export type ModerationReason =
  | 'profanity'
  | 'sexual'
  | 'crime'
  | 'spam'
  | 'not_a_thought'
  | 'classifier_declined';

export interface ContentFilter {
  moderate(text: string): Promise<ModerationVerdict>;
  /** Name and bio: only abuse is blocked, since they need not be thoughts. */
  moderateProfile(profile: { name: string; bio: string }): Promise<boolean>;
}

/** The filter service failed; the write is refused rather than let through. */
export class FilterUnavailableError extends Error {
  constructor(cause: unknown) {
    super('content filter unavailable', { cause });
  }
}

/** Why a profile photo was refused. */
export type PhotoProblem = 'no_face' | 'many_faces' | 'unclear' | 'inappropriate';
export type PhotoVerdict = { ok: true } | { ok: false; problem: PhotoProblem };

/** Checks that a photo shows one real, clear human face and nothing inappropriate. */
export interface PhotoChecker {
  check(jpeg: Uint8Array): Promise<PhotoVerdict>;
}

export interface PhotoStore {
  put(key: string, jpeg: Uint8Array): Promise<void>;
  remove(key: string): Promise<void>;
}

export interface Embedder {
  embed(text: string): Promise<number[]>;
}

export interface Translator {
  translate(text: string, from: string, to: string): Promise<string>;
}

export interface NewPost {
  authorId: string;
  body: string;
  lang: string;
  typingMs: number;
  localDate: string;
  status: 'published' | 'blocked';
  blockedReason?: ModerationReason;
  embedding?: number[];
  session: TypingSession;
  issues: string[];
}

export interface FeedPost {
  id: string;
  authorId: string;
  authorHandle: string;
  authorName: string;
  photoKey: string | null;
  body: string;
  lang: string;
  typingMs: number;
  empathyCount: number;
  empathizedByMe: boolean;
  createdAt: string;
  editedAt: string | null;
}

export interface Profile {
  id: string;
  handle: string;
  displayName: string;
  bio: string;
  photoKey: string | null;
  locale: string;
  timeZone: string;
  writingDays: number;
  followUnlocked: boolean;
  followers: number;
  following: number;
}

export interface ProfileInput {
  handle: string;
  displayName: string;
  bio: string;
  locale: string;
  timeZone: string;
}

export interface PostState {
  authorId: string;
  body: string;
  status: 'published' | 'blocked';
  empathyCount: number;
}

export interface PostUpdate {
  body: string;
  lang: string;
  /** Typing time of the edit, added to the post's existing typing time. */
  typingMs: number;
  embedding: number[];
  session: TypingSession;
}

export type FollowResult = 'ok' | 'not_found' | 'not_allowed' | 'self';

export interface FeedOptions {
  /** Only posts by people the viewer follows. */
  following: boolean;
  /** Only posts by this author. */
  authorId?: string;
  before?: string;
  limit: number;
}

export interface Repository {
  insertPost(post: NewPost): Promise<string>;

  /** Distinct other authors with a published post within the distance. */
  countSimilarAuthors(postId: string, embedding: number[], maxDistance: number): Promise<number>;

  /**
   * Records each phrase as first used by this post unless it already exists.
   * Returns the phrases this post was first to use.
   */
  claimPhrases(postId: string, authorId: string, phrases: Phrase[]): Promise<Phrase[]>;

  /** Today's date in the writer's own time zone, or null without a profile. */
  localDate(authorId: string): Promise<string | null>;

  /**
   * Records one write attempt (post, edit or profile change) unless the writer
   * already made [limit] in the last hour. False when over the limit.
   */
  recordWrite(authorId: string, limit: number): Promise<boolean>;

  /** Whether the app holds at least [n] published posts. Reads at most n rows. */
  hasPublished(n: number): Promise<boolean>;

  writingDays(authorId: string): Promise<number>;
  /** Blocked posts in the window, not counting ones the filter declined to judge. */
  recentBlocks(authorId: string, windowDays: number): Promise<number>;
  writingDaysSinceLoss(authorId: string): Promise<number | null>;
  setFollowUnlocked(authorId: string, unlocked: boolean): Promise<void>;

  /** Adds or removes the user's empathy; returns the new state and count. */
  toggleEmpathy(postId: string, userId: string): Promise<{ empathized: boolean; count: number } | null>;

  feed(viewerId: string, opts: FeedOptions): Promise<FeedPost[]>;

  postState(postId: string): Promise<PostState | null>;
  /**
   * Replaces the text if the post is still the author's, published and has no
   * 공감. Clears its translations and first-used phrases. False if not updated.
   */
  updatePost(postId: string, authorId: string, update: PostUpdate): Promise<boolean>;
  /** Removes a published post with its 공감, translations and phrases. */
  deletePost(postId: string, authorId: string): Promise<boolean>;

  /** Sets the profile photo and returns the key of the one it replaced. */
  setPhoto(userId: string, photoKey: string): Promise<{ previous: string | null } | null>;

  /** Creates or updates the signed-in user's profile. */
  saveProfile(userId: string, input: ProfileInput): Promise<'ok' | 'handle_taken'>;
  profile(userId: string, viewerId: string): Promise<(Profile & { followedByMe: boolean }) | null>;

  /** Both people need follow permission. */
  follow(followerId: string, followeeId: string): Promise<FollowResult>;
  unfollow(followerId: string, followeeId: string): Promise<void>;

  cachedTranslation(postId: string, lang: string): Promise<string | null>;
  saveTranslation(postId: string, lang: string, body: string): Promise<void>;
}
