/**
 * Interfaces for growth without ad spend: sharing consent, invite links,
 * where people came from, the admin dashboard, and the promo agent.
 */

export interface SharingSettings {
  /** Saenggak's own accounts and public pages may show this person's posts. */
  shareOk: boolean;
  /** Shown without their name. */
  anonymous: boolean;
}

export type Platform = 'ios' | 'android' | 'web';

/** What a link or invite code points at. */
export interface LinkTarget {
  code: string;
  /** 'invite' for a person's own code, else the link code's channel. */
  channel: string;
  referrerId: string | null;
}

export type SourceResult = 'ok' | 'unknown_code' | 'too_late' | 'already' | 'self' | 'profile_required';

export interface PublicPost {
  id: string;
  body: string;
  lang: string;
  /** Null when the writer chose to be shown without their name. */
  authorName: string | null;
  typingMs: number;
  empathyCount: number;
  createdAt: string;
}

export interface Question {
  id: string;
  day: string;
  textKo: string;
  textEn: string;
  status: 'draft' | 'approved';
}

/** What the reader-facing routes need. */
export interface GrowthRepository {
  /** Null without a profile. */
  sharing(userId: string): Promise<SharingSettings | null>;
  setSharing(userId: string, settings: SharingSettings): Promise<boolean>;
  /** Only the writer's own published post. */
  setPostExcluded(userId: string, postId: string, excluded: boolean): Promise<boolean>;
  /** The person's invite code, made on first use. Null without a profile. */
  inviteCode(userId: string): Promise<string | null>;
  resolveCode(code: string): Promise<LinkTarget | null>;
  recordClick(code: string, platform: Platform): Promise<void>;
  /** Records where the person came from, once, within a day of making their profile. */
  recordSource(userId: string, code: string): Promise<SourceResult>;
  /** The approved question for the person's own calendar day. */
  todayQuestion(userId: string): Promise<Question | null>;
  /** A published post whose writer allows sharing and did not exclude it. */
  publicPost(postId: string): Promise<PublicPost | null>;
  /** Shareable posts for the sitemap, newest first. */
  publicPostIds(limit: number): Promise<{ id: string; at: string }[]>;
}

export interface DashboardDay {
  /** Calendar day in Korea, YYYY-MM-DD. */
  day: string;
  signups: number;
  posts: number;
  empathies: number;
  /** People who posted or gave 공감 that day. */
  activePeople: number;
}

export interface Retention {
  /** Share of the cohort active on or after day N, 0 to 1; null with no cohort yet. */
  rate: number | null;
  /** People who joined at least N days ago, in the last 90 days. */
  cohort: number;
}

export interface SourceStat {
  channel: string;
  signups: number;
  /** Of those, people still active 7 or more days after joining. */
  active7: number;
}

export interface Dashboard {
  days: DashboardDay[];
  retention: { d1: Retention; d7: Retention; d30: Retention };
  sources: SourceStat[];
}

export interface AuditEntry {
  id: string;
  adminHandle: string | null;
  action: string;
  targetId: string;
  note: string;
  at: string;
}

export type PromoStatus = 'pending' | 'approved' | 'skipped' | 'posted' | 'failed' | 'withdrawn' | 'takedown';

export interface PromoItem {
  id: string;
  postId: string;
  status: PromoStatus;
  caption: string;
  score: number;
  linkCode: string;
  cardKey: string | null;
  scheduledFor: string | null;
  posted: Record<string, string>;
  error: string | null;
  createdAt: string;
  /** Null once the post is gone. */
  post: {
    body: string;
    lang: string;
    authorHandle: string;
    /** Null when the writer chose to be shown without their name. */
    authorName: string | null;
    empathyCount: number;
    typingMs: number;
  } | null;
  clicks: number;
  signups: number;
}

export interface PromoDecision {
  approve: boolean;
  caption?: string;
  /** The card image, already stored, for an approval. */
  cardKey?: string;
  /** When to post an approved item; the next evening slot if left out. */
  scheduledFor?: string;
}

export interface LinkStat {
  code: string;
  channel: string;
  label: string;
  clicks: number;
  signups: number;
  active7: number;
  createdAt: string;
}

/** What the admin pages read and change for growth. */
export interface GrowthAdmin {
  dashboard(days: number): Promise<Dashboard>;
  audit(limit: number, before?: string): Promise<AuditEntry[]>;
  promoItems(statuses: PromoStatus[], limit: number): Promise<PromoItem[]>;
  /** Only pending or approved items can be decided again. False otherwise. */
  decidePromo(itemId: string, adminId: string, decision: PromoDecision): Promise<boolean>;
  /** An item an admin posted by hand, or took down by hand. */
  markPromo(itemId: string, adminId: string, status: 'posted' | 'withdrawn'): Promise<boolean>;
  linkStats(limit: number): Promise<LinkStat[]>;
  createLinkCode(adminId: string, code: string, channel: string, label: string): Promise<'ok' | 'taken'>;
  questions(fromDay: string, limit: number): Promise<Question[]>;
  saveQuestion(adminId: string, q: { day: string; textKo: string; textEn: string; approve: boolean }): Promise<Question>;
}

export interface PromoCandidate {
  postId: string;
  body: string;
  lang: string;
  score: number;
}

/** An approved item whose time has come, with what each channel needs. */
export interface DueItem {
  id: string;
  caption: string;
  cardKey: string | null;
  body: string;
  lang: string;
  authorName: string | null;
  linkCode: string;
  /** Channels it already went to, so a retry does not post twice. */
  posted: Record<string, string>;
}

/** What the promo agent reads and writes. */
export interface PromoStore {
  /** Recent shareable posts not yet picked, best first, one per writer. */
  candidates(limit: number): Promise<PromoCandidate[]>;
  addItem(c: PromoCandidate, caption: string, linkCode: string): Promise<void>;
  due(limit: number): Promise<DueItem[]>;
  markPosted(itemId: string, posted: Record<string, string>, error: string | null): Promise<void>;
  /**
   * Items whose post can no longer be shown (deleted, excluded, consent
   * withdrawn, writer suspended): pending or approved ones are withdrawn,
   * posted ones are marked for takedown. Returns the card images to delete.
   */
  withdrawUnshareable(): Promise<string[]>;
  /** Days from [from] on, [count] of them, that have no question yet. */
  daysWithoutQuestion(from: string, count: number): Promise<string[]>;
  recentQuestions(limit: number): Promise<string[]>;
  addQuestionDrafts(drafts: { day: string; textKo: string; textEn: string }[]): Promise<void>;
}

/** Writes the short text around a featured post, and question drafts. */
export interface Copywriter {
  caption(post: { body: string; lang: string }): Promise<string>;
  questions(count: number, avoid: string[]): Promise<{ ko: string; en: string }[]>;
}

/** One of Saenggak's own social accounts. */
export interface Publisher {
  channel: string;
  /** Returns the id of the new post there. */
  publish(post: { text: string; imageUrl: string | null }): Promise<string>;
}
