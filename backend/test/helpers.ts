import type { Phrase } from '../src/rules/phrases.js';
import type {
  FeedPost,
  FollowResult,
  NewPost,
  PostUpdate,
  Profile,
  ProfileInput,
  Repository,
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
    return this.posts.filter((p) => p.authorId === a && p.status === 'blocked').length;
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
  async profile(userId: string, viewerId: string): Promise<(Profile & { followedByMe: boolean }) | null> {
    const u = this.users.get(userId);
    if (!u) return null;
    const count = (side: 0 | 1) => [...this.follows].filter((f) => f.split('>')[side] === userId).length;
    return {
      id: userId, handle: u.handle, displayName: u.displayName, bio: u.bio, photoKey: null,
      locale: u.locale, timeZone: u.timeZone, writingDays: await this.writingDays(userId),
      followUnlocked: this.unlocked.get(userId) ?? false, followers: count(1), following: count(0),
      followedByMe: this.follows.has(`${viewerId}>${userId}`),
    };
  }
  async follow(a: string, b: string): Promise<FollowResult> {
    if (a === b) return 'self';
    if (!this.users.has(b)) return 'not_found';
    if (!this.unlocked.get(a) || !this.unlocked.get(b)) return 'not_allowed';
    this.follows.add(`${a}>${b}`);
    return 'ok';
  }
  async unfollow(a: string, b: string) {
    this.follows.delete(`${a}>${b}`);
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
  async feed() {
    return this.feedPosts;
  }
  async cachedTranslation(postId: string, lang: string) {
    return this.translations.get(`${postId}:${lang}`) ?? null;
  }
  async saveTranslation(postId: string, lang: string, body: string) {
    this.translations.set(`${postId}:${lang}`, body);
  }
}
