/**
 * Interfaces the handlers depend on, so the post flow can be tested without
 * AWS. Real implementations live next to this file.
 */
import type { TypingSession } from '../rules/humanCheck.js';
import type { Phrase } from '../rules/phrases.js';
import type { ActionKind, Activity } from '../rules/risk.js';
import type { TextSignals } from '../rules/thoughtScore.js';

export type ModerationVerdict =
  | { allowed: true; signals?: TextSignals }
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
  /** JPEG unless [contentType] says otherwise (promo cards are PNG). */
  put(key: string, bytes: Uint8Array, contentType?: string): Promise<void>;
  remove(key: string): Promise<void>;
}

/** The sign-in accounts (Cognito). */
export interface UserDirectory {
  deleteUser(userId: string): Promise<void>;
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
  bookmarkedByMe: boolean;
  createdAt: string;
  editedAt: string | null;
  /** The reader's own post, kept out of sharing. */
  shareExcluded?: boolean;
}

/** A person found by search. */
export interface UserHit {
  id: string;
  handle: string;
  displayName: string;
  bio: string;
  photoKey: string | null;
}

export interface ThoughtScores {
  process: number;
  content: number;
  thought: number;
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
  /** Only posts the viewer saved, newest saved first. */
  saved?: boolean;
  /**
   * The 추천 order: thought score, 공감 and the reader's taste, fading with
   * age. Paged by [offset] instead of [before].
   */
  ranked?: boolean;
  offset?: number;
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

  /**
   * Erases the person and everything they made: posts, 공감 given and
   * received, follows, phrases and logs. Returns their photo key so the file
   * can be removed too, or false if there was no such person.
   */
  deleteAccount(userId: string): Promise<{ photoKey: string | null } | false>;

  /** Suspended people can read but not write. */
  isSuspended(userId: string): Promise<boolean>;

  /** Sets the profile photo and returns the key of the one it replaced. */
  setPhoto(userId: string, photoKey: string): Promise<{ previous: string | null } | null>;

  /** Creates or updates the signed-in user's profile. */
  saveProfile(userId: string, input: ProfileInput): Promise<'ok' | 'handle_taken'>;
  profile(
    userId: string,
    viewerId: string,
  ): Promise<(Profile & { followedByMe: boolean; blockedByMe?: boolean; alertsByMe?: boolean }) | null>;

  /** Both people need follow permission. */
  follow(followerId: string, followeeId: string): Promise<FollowResult>;
  unfollow(followerId: string, followeeId: string): Promise<void>;

  /**
   * Turns alerts for the followee's new posts on or off. Only for someone the
   * follower follows; false otherwise.
   */
  setPostAlerts(followerId: string, followeeId: string, on: boolean): Promise<boolean>;

  /** Stored translations into [lang] of any of [postIds], by post id, in one query. */
  cachedTranslations(postIds: string[], lang: string): Promise<Map<string, string>>;
  saveTranslation(postId: string, lang: string, body: string): Promise<void>;

  /** Stores a published post's thought score. */
  setThoughtScores(postId: string, scores: ThoughtScores): Promise<void>;

  /** Recent activity for the risk score. */
  activity(userId: string): Promise<Activity>;
  recordAction(userId: string, kind: ActionKind): Promise<void>;
  setHumanChecked(userId: string): Promise<void>;

  /** One published post as the viewer would see it in the feed, or null. */
  post(viewerId: string, postId: string): Promise<FeedPost | null>;
  /** Saves or unsaves a published post. False if there is no such post. */
  setBookmark(userId: string, postId: string, saved: boolean): Promise<boolean>;

  /** People whose handle or name matches, not suspended and not blocked either way. */
  findUsers(viewerId: string, query: string, limit: number): Promise<UserHit[]>;
  /** Published posts closest in meaning to the embedding. */
  searchPosts(viewerId: string, embedding: number[], maxDistance: number, limit: number): Promise<FeedPost[]>;

  /** Everything stored about the person, for them to keep. Null without a profile. */
  exportData(userId: string): Promise<Record<string, unknown> | null>;
}

export interface AdminStats {
  users: number;
  usersToday: number;
  posts: number;
  postsToday: number;
  /** Blocked posts no admin has looked at yet. */
  pendingReview: number;
  suspended: number;
  openReports: number;
}

export interface ReviewItem {
  id: string;
  authorId: string;
  authorHandle: string;
  authorName: string;
  body: string;
  blockedReason: string | null;
  /** What the typing check noticed, if anything. */
  issues: string[];
  typingMs: number;
  createdAt: string;
}

export interface AdminUser {
  id: string;
  handle: string;
  displayName: string;
  bio: string;
  photoKey: string | null;
  createdAt: string;
  posts: number;
  /** Blocked posts in the last 30 days. */
  recentBlocks: number;
  suspendedAt: string | null;
  suspendedReason: string | null;
}

export type ReviewDecision = 'publish' | 'keep_blocked';

/** What the admin pages read and change. Every change is logged with the admin's id. */
export interface AdminRepository extends ReportAdmin {
  stats(): Promise<AdminStats>;
  /** Blocked posts not yet reviewed, newest first. */
  reviewQueue(limit: number, before?: string): Promise<ReviewItem[]>;
  /** False if the post is not a blocked post awaiting review. */
  reviewPost(postId: string, adminId: string, decision: ReviewDecision): Promise<boolean>;
  /** Takes a published post down. False if there is no such post. */
  removePost(postId: string, adminId: string, note: string): Promise<boolean>;
  /** Matches handle or name; empty [query] lists the newest people. */
  searchUsers(query: string, limit: number): Promise<AdminUser[]>;
  setSuspended(userId: string, adminId: string, suspended: boolean, reason: string): Promise<boolean>;
  /** Clears the profile photo and returns its key, or false if there is no such user. */
  removePhoto(userId: string, adminId: string): Promise<{ previous: string | null } | false>;
}

export const REPORT_REASONS = ['ai_or_copied', 'abuse', 'sexual', 'spam', 'self_harm', 'impersonation', 'other'] as const;
export type ReportReason = (typeof REPORT_REASONS)[number];

export interface NewReport {
  userId: string;
  postId?: string;
  reason: ReportReason;
  note: string;
}

export interface Notification {
  /** 'post': someone whose bell the reader turned on wrote a new post. */
  kind: 'empathy' | 'follow' | 'post';
  at: string;
  actorId: string;
  actorHandle: string;
  actorName: string;
  actorPhotoKey: string | null;
  postId: string | null;
  /** The start of the post that got 공감. */
  excerpt: string | null;
}

export interface BlockedUser {
  id: string;
  handle: string;
  displayName: string;
}

export interface OpenReport {
  id: string;
  reason: string;
  note: string;
  createdAt: string;
  reporterHandle: string;
  userId: string;
  userHandle: string;
  userName: string;
  postId: string | null;
  postBody: string | null;
  /** Open reports about the same person, this one included. */
  reportsOnUser: number;
}

/** Reports, blocks and notifications. */
export interface SocialRepository {
  /** 'not_found' when the person or post does not exist; 'self' for one's own. */
  report(reporterId: string, report: NewReport): Promise<'ok' | 'not_found' | 'self'>;
  /** Also ends follows both ways. */
  block(blockerId: string, blockedId: string): Promise<'ok' | 'not_found' | 'self'>;
  unblock(blockerId: string, blockedId: string): Promise<void>;
  blocked(userId: string): Promise<BlockedUser[]>;
  notifications(userId: string, limit: number, before?: string): Promise<{ items: Notification[]; unread: number }>;
  markNotificationsSeen(userId: string): Promise<void>;
}

export interface ReportAdmin {
  openReports(limit: number): Promise<OpenReport[]>;
  resolveReport(reportId: string, adminId: string, note: string): Promise<boolean>;
}
