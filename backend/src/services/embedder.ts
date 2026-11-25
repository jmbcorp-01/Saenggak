import { BedrockRuntimeClient, InvokeModelCommand } from '@aws-sdk/client-bedrock-runtime';
import type { Embedder } from './ports.js';

/** Multilingual embeddings, so Korean and English posts can match. */
export const EMBEDDING_MODEL = process.env.EMBEDDING_MODEL ?? 'amazon.titan-embed-text-v2:0';
export const EMBEDDING_DIMENSIONS = 1024;

export class TitanEmbedder implements Embedder {
  constructor(private readonly client = new BedrockRuntimeClient({})) {}

  async embed(text: string): Promise<number[]> {
    const out = await this.client.send(
      new InvokeModelCommand({
        modelId: EMBEDDING_MODEL,
        contentType: 'application/json',
        accept: 'application/json',
        body: JSON.stringify({ inputText: text, dimensions: EMBEDDING_DIMENSIONS, normalize: true }),
      }),
    );
    const parsed = JSON.parse(new TextDecoder().decode(out.body)) as { embedding: number[] };
    if (parsed.embedding?.length !== EMBEDDING_DIMENSIONS) throw new Error('unexpected embedding size');
    return parsed.embedding;
  }
}
