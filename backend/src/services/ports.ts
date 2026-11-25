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

export interface Repository {
  insertPost(post: NewPost): Promise<string>;

  /** Distinct other authors with a published post within the distance. */
  countSimilarAuthors(postId: string, embedding: number[], maxDistance: number): Promise<number>;

  /**
   * Records each phrase as first used by this post unless it already exists.
   * Returns the phrases this post was first to use.
   */
  claimPhrases(postId: string, authorId: string, phrases: Phrase[]): Promise<Phrase[]>;

  writingDays(authorId: string): Promise<number>;
  recentBlocks(authorId: string, windowDays: number): Promise<number>;
  writingDaysSinceLoss(authorId: string): Promise<number | null>;
  setFollowUnlocked(authorId: string, unlocked: boolean): Promise<void>;

  /** Adds or removes the user's empathy; returns the new state and count. */
  toggleEmpathy(postId: string, userId: string): Promise<{ empathized: boolean; count: number } | null>;

  feed(viewerId: string, opts: { following: boolean; before?: string; limit: number }): Promise<FeedPost[]>;

  cachedTranslation(postId: string, lang: string): Promise<string | null>;
  saveTranslation(postId: string, lang: string, body: string): Promise<void>;
}
