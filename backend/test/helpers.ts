import type { Phrase } from '../src/rules/phrases.js';
import type { ActionKind, Activity } from '../src/rules/risk.js';
import type {
  FeedOptions,
  FeedPost,
  FollowResult,
  NewPost,
  NewReport,
  Notification,
  PostUpdate,
  Profile,
  ProfileInput,
  Repository,
  SocialRepository,
  ThoughtScores,
} from '../src/services/ports.js';

/** One keystroke per character at uneven, human-like intervals. */
export function humanSession(text: string) {
  let t = 0;
  let seed = 7;
  const events = [...text].map(() => {
    seed = (seed * 9301 + 49297) % 233280;
    t += 120 + Math.floor((seed / 233280) * 300);
    return { t, i: 1, d: 0, s: 'keyboard' };
  });
  return { events, rejectedPastes: 0 };
}

/** Deletes [oldText] then types [newText], as an edit that rewrites the post. */
export function editSession(oldText: string, newText: string) {
  const typed = humanSession(newText);
  return { ...typed, events: [{ t: 0, i: 0, d: [...oldText].length, s: 'keyboard' }, ...typed.events] };
}

/** Fake repository kept in memory. */
export class MemoryRepo implements Repository {
  posts: (NewPost & { id: string })[] = [];
  firsts = new Map<string, string>();
  unlocked = new Map<string, boolean>();
  similarAuthors = 0;
  translations = new Map<string, string>();
  feedPosts: FeedPost[] = [];
  empathies = new Set<string>();
  users = new Map<string, ProfileInput>();
  follows = new Set<string>();
  /** The writer's day the server would work out from their time zone. */
  today = '2026-11-25';
  /** When true, writers without a saved profile are refused, as in the database. */
  requireProfile = false;
  writes = new Map<string, number>();
  photos = new Map<string, string>();
  suspended = new Set<string>();

  async deleteAccount(userId: string) {
    if (!this.users.has(userId)) return false as const;
    const photoKey = this.photos.get(userId) ?? null;
    this.users.delete(userId);
    this.photos.delete(userId);
    this.posts = this.posts.filter((p) => p.authorId !== userId);
    return { photoKey };
  }

  async isSuspended(userId: string) {
    return this.suspended.has(userId);
  }

  async setPhoto(userId: string, key: string) {
    if (!this.users.has(userId)) return null;
    const previous = this.photos.get(userId) ?? null;
    this.photos.set(userId, key);
    return { previous };
  }
  /** Published posts the app is pretended to hold besides these ones. */
  otherPublished = 1_000_000;

  async hasPublished(n: number) {
    return this.otherPublished + this.posts.filter((p) => p.status === 'published').length >= n;
  }

  async localDate(a: string) {
    return this.requireProfile && !this.users.has(a) ? null : this.today;
  }
  async recordWrite(a: string, limit: number) {
    const n = this.writes.get(a) ?? 0;
    if (n >= limit) return false;
    this.writes.set(a, n + 1);
    return true;
  }

  async insertPost(p: NewPost) {
    const id = `00000000-0000-4000-8000-${String(this.posts.length + 1).padStart(12, '0')}`;
    this.posts.push({ ...p, id });
    return id;
  }
  async countSimilarAuthors() {
    return this.similarAuthors;
  }
  async claimPhrases(postId: string, _a: string, phrases: Phrase[]) {
    return phrases.filter((p) => {
      if (this.firsts.has(p.key)) return false;
      this.firsts.set(p.key, postId);
      return true;
    });
  }
  async writingDays(a: string) {
    return new Set(this.posts.filter((p) => p.authorId === a && p.status === 'published').map((p) => p.localDate)).size;
  }
  async recentBlocks(a: string) {
    return this.posts.filter((p) => p.authorId === a && p.status === 'blocked' && p.blockedReason !== 'classifier_declined')
      .length;
  }
  async writingDaysSinceLoss() {
    return null;
  }
  async setFollowUnlocked(a: string, u: boolean) {
    this.unlocked.set(a, u);
  }
  async postState(postId: string) {
    const p = this.posts.find((x) => x.id === postId);
    if (!p) return null;
    const empathyCount = [...this.empathies].filter((e) => e.startsWith(`${postId}:`)).length;
    return { authorId: p.authorId, body: p.body, status: p.status, empathyCount };
  }
  async updatePost(postId: string, authorId: string, u: PostUpdate) {
    const p = this.posts.find((x) => x.id === postId && x.authorId === authorId && x.status === 'published');
    if (!p || [...this.empathies].some((e) => e.startsWith(`${postId}:`))) return false;
    Object.assign(p, { body: u.body, lang: u.lang, typingMs: p.typingMs + u.typingMs, embedding: u.embedding, session: u.session });
    for (const [k, v] of this.firsts) if (v === postId) this.firsts.delete(k);
    return true;
  }
  async deletePost(postId: string, authorId: string) {
    const i = this.posts.findIndex((x) => x.id === postId && x.authorId === authorId && x.status === 'published');
    if (i < 0) return false;
    this.posts.splice(i, 1);
    for (const [k, v] of this.firsts) if (v === postId) this.firsts.delete(k);
    return true;
  }
  async saveProfile(userId: string, input: ProfileInput) {
    for (const [id, u] of this.users) if (id !== userId && u.handle === input.handle) return 'handle_taken' as const;
    this.users.set(userId, input);
    return 'ok' as const;
  }
  async profile(userId: string, viewerId: string): Promise<(Profile & { followedByMe: boolean; alertsByMe?: boolean }) | null> {
    const u = this.users.get(userId);
    if (!u) return null;
    const count = (side: 0 | 1) => [...this.follows].filter((f) => f.split('>')[side] === userId).length;
    return {
      id: userId, handle: u.handle, displayName: u.displayName, bio: u.bio, photoKey: this.photos.get(userId) ?? null,
      locale: u.locale, timeZone: u.timeZone, writingDays: await this.writingDays(userId),
      followUnlocked: this.unlocked.get(userId) ?? false, followers: count(1), following: count(0),
      followedByMe: this.follows.has(`${viewerId}>${userId}`),
      alertsByMe: this.alerts.has(`${viewerId}>${userId}`),
    };
  }
  async follow(a: string, b: string): Promise<FollowResult> {
    if (a === b) return 'self';
    if (!this.users.has(b)) return 'not_found';
    if (!this.unlocked.get(a) || !this.unlocked.get(b)) return 'not_allowed';
    this.follows.add(`${a}>${b}`);
    return 'ok';
  }
  alerts = new Set<string>();
  async setPostAlerts(a: string, b: string, on: boolean) {
    if (!this.follows.has(`${a}>${b}`)) return false;
    if (on) this.alerts.add(`${a}>${b}`);
    else this.alerts.delete(`${a}>${b}`);
    return true;
  }
  async unfollow(a: string, b: string) {
    this.follows.delete(`${a}>${b}`);
    this.alerts.delete(`${a}>${b}`);
  }
  async toggleEmpathy(postId: string, userId: string) {
    const post = this.posts.find((p) => p.id === postId && p.status === 'published');
    if (!post || post.authorId === userId) return null;
    const k = `${postId}:${userId}`;
    const empathized = !this.empathies.has(k);
    if (empathized) this.empathies.add(k);
    else this.empathies.delete(k);
    return { empathized, count: [...this.empathies].filter((e) => e.startsWith(`${postId}:`)).length };
  }
  feedCalls: FeedOptions[] = [];
  async feed(_v: string, opts: FeedOptions) {
    this.feedCalls.push(opts);
    return this.feedPosts;
  }
  scores = new Map<string, ThoughtScores>();
  async setThoughtScores(postId: string, sc: ThoughtScores) {
    this.scores.set(postId, sc);
  }
  /** What activity() reports; tests set it to simulate bursts. */
  recentActivity: Activity = { last10m: {}, lastHour: {}, accountAgeHours: 100, lowScorePosts: 0, hoursSinceCheck: null };
  actions: { userId: string; kind: ActionKind }[] = [];
  humanChecked = new Set<string>();
  async activity() {
    return this.recentActivity;
  }
  async recordAction(userId: string, kind: ActionKind) {
    this.actions.push({ userId, kind });
  }
  async setHumanChecked(userId: string) {
    this.humanChecked.add(userId);
    this.recentActivity = { ...this.recentActivity, hoursSinceCheck: 0, lastHour: { ...this.recentActivity.lastHour, check_failed: 0 } };
  }
  async post(_v: string, postId: string) {
    return this.feedPosts.find((p) => p.id === postId) ?? null;
  }
  bookmarks = new Set<string>();
  async setBookmark(userId: string, postId: string, saved: boolean) {
    if (!this.feedPosts.some((p) => p.id === postId)) return false;
    if (saved) this.bookmarks.add(`${userId}:${postId}`);
    else this.bookmarks.delete(`${userId}:${postId}`);
    return true;
  }
  async findUsers(_v: string, query: string) {
    return [...this.users.entries()]
      .filter(([, u]) => u.handle.includes(query) || u.displayName.includes(query))
      .map(([id, u]) => ({ id, handle: u.handle, displayName: u.displayName, bio: u.bio, photoKey: null }));
  }
  searchCalls: number[][] = [];
  async searchPosts(_v: string, embedding: number[]) {
    this.searchCalls.push(embedding);
    return this.feedPosts;
  }
  async exportData(userId: string) {
    const u = this.users.get(userId);
    return u ? { profile: u, posts: this.posts.filter((p) => p.authorId === userId) } : null;
  }
  async cachedTranslation(postId: string, lang: string) {
    return this.translations.get(`${postId}:${lang}`) ?? null;
  }
  async saveTranslation(postId: string, lang: string, body: string) {
    this.translations.set(`${postId}:${lang}`, body);
  }
}

/** Fake reports, blocks and notifications. */
export class MemorySocial implements SocialRepository {
  reports: (NewReport & { reporterId: string })[] = [];
  blocks = new Set<string>();
  seen = 0;
  items: Notification[] = [];

  async report(reporterId: string, r: NewReport) {
    if (reporterId === r.userId) return 'self' as const;
    this.reports.push({ ...r, reporterId });
    return 'ok' as const;
  }
  async block(a: string, b: string) {
    if (a === b) return 'self' as const;
    this.blocks.add(`${a}>${b}`);
    return 'ok' as const;
  }
  async unblock(a: string, b: string) {
    this.blocks.delete(`${a}>${b}`);
  }
  async blocked(a: string) {
    return [...this.blocks].filter((k) => k.startsWith(`${a}>`)).map((k) => ({ id: k.split('>')[1]!, handle: 'h', displayName: 'n' }));
  }
  async notifications() {
    return { items: this.items, unread: this.items.length - this.seen };
  }
  async markNotificationsSeen() {
    this.seen = this.items.length;
  }
}
