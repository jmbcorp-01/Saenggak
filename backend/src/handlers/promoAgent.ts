import { draftQuestions, pickCandidates, publishDue } from '../growth/agent.js';
import { ClaudeCopywriter } from '../services/copywriter.js';
import { AuroraGrowthRepository } from '../services/growthRepository.js';
import { publishersFrom, refreshTokens, TokenSecret } from '../services/meta.js';
import { S3PhotoStore } from '../services/photos.js';

/**
 * The promo agent, run by EventBridge Scheduler:
 *   { job: 'pick' }       07:00 in Korea: picks today's candidates and drafts captions
 *   { job: 'publish' }    hourly: posts approved items whose time has come
 *   { job: 'questions' }  Mondays: drafts questions for the next two weeks
 *   { job: 'tokens' }     Sundays: refreshes the Threads and Instagram tokens
 */
export type Job = 'pick' | 'publish' | 'questions' | 'tokens';

export async function handler(event: { job?: Job }): Promise<Record<string, unknown>> {
  const store = new AuroraGrowthRepository();
  const cards = new S3PhotoStore();
  const tokens = new TokenSecret();
  switch (event.job) {
    case 'pick':
      return { picked: await pickCandidates({ store, copywriter: new ClaudeCopywriter(), cards }) };
    case 'publish': {
      const publishers = publishersFrom(await tokens.read());
      const report = await publishDue({ store, cards, publishers, site: process.env.SITE_URL ?? '' });
      return { ...report };
    }
    case 'questions':
      return { drafted: await draftQuestions({ store, copywriter: new ClaudeCopywriter() }, new Date()) };
    case 'tokens': {
      const current = await tokens.read();
      if (publishersFrom(current).length === 0) return { refreshed: false };
      await tokens.write(await refreshTokens(current));
      return { refreshed: true };
    }
  }
  throw new Error(`unknown job ${String(event.job)}`);
}
