/**
 * "비슷한 생각을 한 사람 수": how many other people wrote a post close in meaning.
 */

/** Cosine similarity at or above this counts as a similar thought. */
export const SIMILARITY_THRESHOLD = 0.82;

/** Below this many people the app shows "아직 비슷한 생각이 없어요". */
export const MIN_PEOPLE_SHOWN = 3;

export interface SimilarSummary {
  /** Distinct other writers above the threshold. */
  people: number;
  /** Whether the number is large enough to show. */
  show: boolean;
}

export function summarizeSimilar(people: number): SimilarSummary {
  return { people, show: people >= MIN_PEOPLE_SHOWN };
}

/** pgvector cosine distance (<=>) equivalent of the similarity threshold. */
export const MAX_COSINE_DISTANCE = 1 - SIMILARITY_THRESHOLD;

export function cosineSimilarity(a: number[], b: number[]): number {
  if (a.length !== b.length || a.length === 0) throw new Error('dimension mismatch');
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let k = 0; k < a.length; k++) {
    dot += a[k]! * b[k]!;
    na += a[k]! ** 2;
    nb += b[k]! ** 2;
  }
  return na === 0 || nb === 0 ? 0 : dot / Math.sqrt(na * nb);
}
