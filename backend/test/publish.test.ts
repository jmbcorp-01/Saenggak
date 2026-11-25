import { describe, expect, it } from 'vitest';
import { publishPost } from '../src/posts/publish.js';
import type { ContentFilter, ModerationVerdict } from '../src/services/ports.js';
import { humanSession, MemoryRepo } from './helpers.js';

const TEXT = '요즘은 조용한 아침에 창문을 열고 바람 소리를 듣는 시간이 하루 중 가장 좋다. 그 짧은 순간이 나를 다시 사람으로 만든다.';
const allow: ContentFilter = { moderate: async () => ({ allowed: true }) };
const block = (verdict: ModerationVerdict): ContentFilter => ({ moderate: async () => verdict });
const embedder = { embed: async () => Array(1024).fill(0.01) };

function setup(filter = allow) {
  const repo = new MemoryRepo();
  return { repo, deps: { repo, filter, embedder } };
}

describe('publishPost', () => {
  it('publishes and reports the extras', async () => {
    const { repo, deps } = setup();
    repo.similarAuthors = 4;
    const r = await publishPost(deps, { authorId: 'u1', text: TEXT, session: humanSession(TEXT), localDate: '2026-11-25' });
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

  it('gives first phrases only to the first writer', async () => {
    const { deps } = setup();
    const input = { text: TEXT, session: humanSession(TEXT), localDate: '2026-11-25' };
    const first = await publishPost(deps, { ...input, authorId: 'u1' });
    const second = await publishPost(deps, { ...input, authorId: 'u2' });
    expect(first.kind === 'published' && first.firstPhrases.length).toBeGreaterThan(0);
    expect(second.kind === 'published' && second.firstPhrases).toEqual([]);
  });

  it('rejects length before calling any service', async () => {
    const { repo, deps } = setup();
    const r = await publishPost(deps, { authorId: 'u1', text: '짧다', session: humanSession('짧다'), localDate: '2026-11-25' });
    expect(r).toEqual({ kind: 'invalid_length', verdict: 'too_short' });
    expect(repo.posts).toHaveLength(0);
  });

  it('rejects pasted text', async () => {
    const { deps } = setup();
    const r = await publishPost(deps, {
      authorId: 'u1',
      text: TEXT,
      session: { events: [{ t: 0, i: [...TEXT].length, d: 0, s: 'keyboard' }] },
      localDate: '2026-11-25',
    });
    expect(r.kind).toBe('not_human');
  });

  it('stores blocked posts and takes follow away at 3 blocks', async () => {
    const { repo, deps } = setup(block({ allowed: false, reason: 'profanity' }));
    repo.unlocked.set('u1', true);
    for (let k = 0; k < 3; k++) {
      const r = await publishPost(deps, { authorId: 'u1', text: TEXT, session: humanSession(TEXT), localDate: '2026-11-25' });
      expect(r).toMatchObject({ kind: 'blocked', reason: 'profanity' });
    }
    expect(repo.posts.every((p) => p.status === 'blocked' && p.embedding === undefined)).toBe(true);
    expect(repo.unlocked.get('u1')).toBe(false);
  });

  it('unlocks follow on the tenth writing day', async () => {
    const { repo, deps } = setup();
    for (let day = 1; day <= 10; day++) {
      await publishPost(deps, {
        authorId: 'u1',
        text: TEXT,
        session: humanSession(TEXT),
        localDate: `2026-11-${String(day).padStart(2, '0')}`,
      });
    }
    expect(repo.unlocked.get('u1')).toBe(true);
  });
});
