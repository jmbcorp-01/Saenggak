import type { Copywriter, DueItem, PromoStore, Publisher } from '../services/growthPorts.js';
import { addDays, koreaDay, newLinkCode } from './codes.js';
import { instagramCaption, threadsText } from './pages.js';

/**
 * The promo agent: the daily work a growth team does by hand, run on a
 * schedule. It never posts anything an admin has not approved, and it never
 * changes a writer's words; only the caption around them is drafted.
 */

export const PICKS_PER_DAY = 5;
export const QUESTION_DAYS_AHEAD = 14;

/** A plain caption when the copywriter is unavailable, so the queue still fills. */
export function fallbackCaption(lang: string): string {
  return lang === 'ko'
    ? '오늘 생각에서 많은 공감을 받은 생각입니다. 당신의 생각도 직접 써 보세요. #생각 #오늘의생각 #직접쓴글'
    : 'One of today’s most felt thoughts on Saenggak. Write your own, by hand. #saenggak #thoughts';
}

export interface PickDeps {
  store: PromoStore;
  copywriter: Copywriter;
  /** Where card images live, so a withdrawn item's card goes too. */
  cards: { remove(key: string): Promise<void> };
}

/** Takes items whose post can no longer be shown out of the queue, with their cards. */
export async function withdraw(deps: Pick<PickDeps, 'store' | 'cards'>): Promise<number> {
  const keys = await deps.store.withdrawUnshareable();
  for (const k of keys) await deps.cards.remove(k).catch((e) => console.error('card delete failed', k, e));
  return keys.length;
}

/** Every morning: picks the best shareable posts and drafts a caption for each. */
export async function pickCandidates(deps: PickDeps, limit = PICKS_PER_DAY): Promise<number> {
  await withdraw(deps);
  const picked = await deps.store.candidates(limit);
  for (const c of picked) {
    let caption: string;
    try {
      caption = (await deps.copywriter.caption({ body: c.body, lang: c.lang })).trim() || fallbackCaption(c.lang);
    } catch (e) {
      console.error('caption draft failed', e);
      caption = fallbackCaption(c.lang);
    }
    await deps.store.addItem(c, caption, newLinkCode('p'));
  }
  return picked.length;
}

export interface PublishDeps {
  store: PromoStore;
  cards: PickDeps['cards'];
  publishers: Publisher[];
  /** https://saenggak.app */
  site: string;
}

export interface PublishReport {
  posted: number;
  failed: number;
  /** Approved items left for an admin to post by hand: no channel is connected. */
  waiting: number;
}

function postFor(channel: string, item: DueItem, site: string): { text: string; imageUrl: string | null } | null {
  const link = `${site}/i/${item.linkCode}`;
  if (channel === 'instagram') {
    // Instagram posts need an image; without the card the item waits for an admin.
    if (!item.cardKey) return null;
    return { text: instagramCaption(item), imageUrl: `${site}/${item.cardKey}` };
  }
  return { text: threadsText({ ...item, link }), imageUrl: null };
}

/** Every hour: posts approved items whose time has come to each connected channel. */
export async function publishDue(deps: PublishDeps): Promise<PublishReport> {
  await withdraw(deps);
  const report: PublishReport = { posted: 0, failed: 0, waiting: 0 };
  const due = await deps.store.due(10);
  if (deps.publishers.length === 0) {
    report.waiting = due.length;
    return report;
  }
  for (const item of due) {
    const posted = { ...item.posted };
    const errors: string[] = [];
    for (const p of deps.publishers) {
      if (posted[p.channel]) continue;
      const post = postFor(p.channel, item, deps.site);
      if (!post) continue;
      try {
        posted[p.channel] = await p.publish(post);
      } catch (e) {
        console.error('publish failed', p.channel, item.id, e);
        errors.push(`${p.channel}: ${e instanceof Error ? e.message : String(e)}`.slice(0, 300));
      }
    }
    await deps.store.markPosted(item.id, posted, errors.length ? errors.join('; ') : null);
    if (errors.length) report.failed++;
    else report.posted++;
  }
  return report;
}

/** Once a week: drafts questions for the coming days that have none, for an admin to approve. */
export async function draftQuestions(deps: Pick<PickDeps, 'store' | 'copywriter'>, now: Date): Promise<number> {
  const from = addDays(koreaDay(now), 1);
  const days = await deps.store.daysWithoutQuestion(from, QUESTION_DAYS_AHEAD);
  if (days.length === 0) return 0;
  const avoid = await deps.store.recentQuestions(60);
  const drafts = (await deps.copywriter.questions(days.length, avoid))
    .filter((q) => q.ko.trim() && q.en.trim())
    .slice(0, days.length);
  await deps.store.addQuestionDrafts(drafts.map((q, i) => ({ day: days[i]!, textKo: q.ko.trim(), textEn: q.en.trim() })));
  return drafts.length;
}
