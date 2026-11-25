import { AnthropicBedrockMantle } from '@anthropic-ai/bedrock-sdk';
import type { ContentFilter, ModerationReason, ModerationVerdict } from './ports.js';

/**
 * Content filter on Claude through Amazon Bedrock. Allows personal thoughts,
 * feelings and reflection; blocks profanity, sexual content, crime, spam and
 * text that is not a thought at all.
 */
export const MODERATION_MODEL = process.env.MODERATION_MODEL ?? 'anthropic.claude-opus-5-5';

const SYSTEM = `You review posts for Saenggak, an app where people share their own thoughts and feelings in 40 to 200 Korean characters or 15 to 70 English words.

Allow a post when it is a personal thought, feeling, worry, memory or reflection, including sad, angry or dark ones that are expressed without abuse.

Block a post when it is mainly:
- profanity: swearing or insults aimed at people or groups
- sexual: sexual content
- crime: planning, encouraging or explaining how to commit crimes, or selling illegal goods
- spam: ads, promotions, links or contact details for business
- not_a_thought: random characters, copied lyrics or articles, or text with no personal thought

Posts may be in Korean or English. Judge the meaning, including slang and deliberate misspellings used to avoid filters.`;

const SCHEMA = {
  type: 'object',
  properties: {
    decision: { type: 'string', enum: ['allow', 'block'] },
    reason: {
      type: 'string',
      enum: ['none', 'profanity', 'sexual', 'crime', 'spam', 'not_a_thought'],
    },
  },
  required: ['decision', 'reason'],
  additionalProperties: false,
} as const;

export class ClaudeContentFilter implements ContentFilter {
  constructor(private readonly client = new AnthropicBedrockMantle()) {}

  async moderate(text: string): Promise<ModerationVerdict> {
    const response = await this.client.messages.create({
      model: MODERATION_MODEL,
      max_tokens: 1024,
      system: SYSTEM,
      output_config: { effort: 'low', format: { type: 'json_schema', schema: SCHEMA } },
      messages: [{ role: 'user', content: `<post>\n${text}\n</post>` }],
    });

    // A declined review is treated as a block and goes to human review.
    if (response.stop_reason === 'refusal') return { allowed: false, reason: 'classifier_declined' };

    const block = response.content.find((b) => b.type === 'text');
    if (!block || block.type !== 'text') throw new Error('content filter returned no text');
    const parsed = JSON.parse(block.text) as { decision: 'allow' | 'block'; reason: string };
    if (parsed.decision === 'allow') return { allowed: true };
    const reason = (parsed.reason === 'none' ? 'not_a_thought' : parsed.reason) as ModerationReason;
    return { allowed: false, reason };
  }
}
