import type { Phrase } from '../src/rules/phrases.js';
import type { FeedPost, NewPost, Repository } from '../src/services/ports.js';

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

/** Fake repository kept in memory. */
export class MemoryRepo implements Repository {
  posts: (NewPost & { id: string })[] = [];
  firsts = new Map<string, string>();
  unlocked = new Map<string, boolean>();
  similarAuthors = 0;
  translations = new Map<string, string>();
  feedPosts: FeedPost[] = [];
  empathies = new Set<string>();

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
