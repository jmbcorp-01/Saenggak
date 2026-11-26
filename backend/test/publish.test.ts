import { describe, expect, it } from 'vitest';
import { publishPost, WRITES_PER_HOUR } from '../src/posts/publish.js';
import type { ContentFilter, ModerationVerdict } from '../src/services/ports.js';
import { humanSession, MemoryRepo } from './helpers.js';

const TEXT = '요즘은 조용한 아침에 창문을 열고 바람 소리를 듣는 시간이 하루 중 가장 좋다. 그 짧은 순간이 나를 다시 사람으로 만든다.';
const allowProfile = async () => true;
const allow: ContentFilter = { moderate: async () => ({ allowed: true }), moderateProfile: allowProfile };
const block = (verdict: ModerationVerdict): ContentFilter => ({ moderate: async () => verdict, moderateProfile: allowProfile });
const embedder = { embed: async () => Array(1024).fill(0.01) };

function setup(filter = allow) {
  const repo = new MemoryRepo();
  return { repo, deps: { repo, filter, embedder } };
}

describe('publishPost', () => {
  it('publishes and reports the extras', async () => {
    const { repo, deps } = setup();
    repo.similarAuthors = 4;
    const r = await publishPost(deps, { authorId: 'u1', text: TEXT, session: humanSession(TEXT) });
    expect(r.kind).toBe('published');
    if (r.kind !== 'published') return;
    expect(r.similar).toEqual({ people: 4, show: true });
    expect(r.firstPhrases.length).toBeGreaterThan(0);
    expect(r.firstPhrases.length).toBeLessThanOrEqual(3);
    expect(r.writingDays).toBe(1);
    expect(r.followUnlocked).toBe(false);
    expect(repo.posts[0]?.lang).toBe('ko');
    expect(r.typingMs).toBeGreaterThan(0);
  });

  it('works out the embedding while the filter runs, not after it', async () => {
    const order: string[] = [];
    const filter: ContentFilter = {
      moderate: async () => {
        order.push('filter start');
        await new Promise((r) => setTimeout(r, 20));
        order.push('filter end');
        return { allowed: true };
      },
      moderateProfile: allowProfile,
    };
    const repo = new MemoryRepo();
    const embed = async () => {
      order.push('embed');
      return Array(1024).fill(0.01);
    };
    const r = await publishPost({ repo, filter, embedder: { embed } }, { authorId: 'u1', text: TEXT, session: humanSession(TEXT) });
    expect(r.kind).toBe('published');
    expect(order.indexOf('embed')).toBeLessThan(order.indexOf('filter end'));
  });

  it('a failed embedding does not matter when the filter blocks the post', async () => {
    const repo = new MemoryRepo();
    const embed = async (): Promise<number[]> => {
      throw new Error('embedder down');
    };
    const r = await publishPost(
      { repo, filter: block({ allowed: false, reason: 'spam' }), embedder: { embed } },
      { authorId: 'u1', text: TEXT, session: humanSession(TEXT) },
    );
    expect(r).toMatchObject({ kind: 'blocked', reason: 'spam' });
  });

  it('gives first phrases only to the first writer', async () => {
    const { deps } = setup();
    const input = { text: TEXT, session: humanSession(TEXT) };
    const first = await publishPost(deps, { ...input, authorId: 'u1' });
    const second = await publishPost(deps, { ...input, authorId: 'u2' });
    expect(first.kind === 'published' && first.firstPhrases.length).toBeGreaterThan(0);
    expect(second.kind === 'published' && second.firstPhrases).toEqual([]);
  });

  it('keeps first phrases hidden until the app holds enough posts', async () => {
    const { repo, deps } = setup();
    repo.otherPublished = 0;
    const early = await publishPost(deps, { authorId: 'u1', text: TEXT, session: humanSession(TEXT) });
    expect(early.kind === 'published' && early.firstPhrases).toEqual([]);
    // They were still recorded, so this writer keeps them once the label is shown.
    expect(repo.firsts.size).toBeGreaterThan(0);
  });

  it('rejects length before calling any service', async () => {
    const { repo, deps } = setup();
    const r = await publishPost(deps, { authorId: 'u1', text: '짧다', session: humanSession('짧다') });
    expect(r).toEqual({ kind: 'invalid_length', verdict: 'too_short' });
    expect(repo.posts).toHaveLength(0);
  });

  it('rejects pasted text', async () => {
    const { deps } = setup();
    const r = await publishPost(deps, {
      authorId: 'u1',
      text: TEXT,
      session: { events: [{ t: 0, i: [...TEXT].length, d: 0, s: 'keyboard' }] },
    });
    expect(r.kind).toBe('not_human');
  });

  it('stores blocked posts and takes follow away at 3 blocks', async () => {
    const { repo, deps } = setup(block({ allowed: false, reason: 'profanity' }));
    repo.unlocked.set('u1', true);
    for (let k = 0; k < 3; k++) {
      const r = await publishPost(deps, { authorId: 'u1', text: TEXT, session: humanSession(TEXT) });
      expect(r).toMatchObject({ kind: 'blocked', reason: 'profanity' });
    }
    expect(repo.posts.every((p) => p.status === 'blocked' && p.embedding === undefined)).toBe(true);
    expect(repo.unlocked.get('u1')).toBe(false);
  });

  it('unlocks follow on the tenth writing day', async () => {
    const { repo, deps } = setup();
    for (let day = 1; day <= 10; day++) {
      repo.today = `2026-11-${String(day).padStart(2, '0')}`;
      await publishPost(deps, { authorId: 'u1', text: TEXT, session: humanSession(TEXT) });
    }
    expect(repo.unlocked.get('u1')).toBe(true);
  });

  it('counts writing days by the server clock, whatever date the app sends', async () => {
    const { repo, deps } = setup();
    for (let day = 1; day <= 10; day++) {
      const input = { authorId: 'u1', text: TEXT, session: humanSession(TEXT), localDate: `2026-10-${day}` };
      await publishPost(deps, input);
    }
    expect(await repo.writingDays('u1')).toBe(1);
    expect(repo.unlocked.get('u1')).toBe(false);
  });

  it('needs a profile before posting', async () => {
    const { repo, deps } = setup();
    repo.requireProfile = true;
    expect(await publishPost(deps, { authorId: 'u1', text: TEXT, session: humanSession(TEXT) })).toEqual({
      kind: 'profile_required',
    });
  });

  it('stops a writer after the hourly limit, before the filter is called', async () => {
    let calls = 0;
    const { repo, deps } = setup({ moderate: async () => (calls++, { allowed: true }), moderateProfile: allowProfile });
    repo.writes.set('u1', WRITES_PER_HOUR);
    const r = await publishPost(deps, { authorId: 'u1', text: TEXT, session: humanSession(TEXT) });
    expect(r).toEqual({ kind: 'rate_limited' });
    expect(calls).toBe(0);
  });

  it('refuses to post while the filter is down', async () => {
    const down = { moderate: async () => Promise.reject(new Error('timeout')), moderateProfile: allowProfile };
    const { repo, deps } = setup(down);
    const r = await publishPost(deps, { authorId: 'u1', text: TEXT, session: humanSession(TEXT) });
    expect(r).toEqual({ kind: 'filter_unavailable' });
    expect(repo.posts).toHaveLength(0);
  });

  it('does not count a declined review as a strike', async () => {
    const { repo, deps } = setup(block({ allowed: false, reason: 'classifier_declined' }));
    repo.unlocked.set('u1', true);
    for (let k = 0; k < 3; k++) await publishPost(deps, { authorId: 'u1', text: TEXT, session: humanSession(TEXT) });
    expect(repo.posts.filter((p) => p.status === 'blocked')).toHaveLength(3);
    expect(await repo.recentBlocks('u1')).toBe(0);
  });
});
