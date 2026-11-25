/** Follow permission rules from the spec. */

/** Writing days (not consecutive) needed to unlock following. */
export const DAYS_TO_FOLLOW = 10;

/** Blocked posts within the window that take the permission away. */
export const BLOCKS_TO_LOSE = 3;
export const BLOCK_WINDOW_DAYS = 30;

export interface FollowInputs {
  /** Distinct days with at least one published post. */
  writingDays: number;
  /** Blocked posts in the last BLOCK_WINDOW_DAYS days. */
  recentBlocks: number;
  /** Writing days since the permission was last lost, or null if never lost. */
  daysSinceLoss: number | null;
}

/**
 * Whether the writer may follow and be followed. Losing the permission hides
 * existing follows; writing on another 10 days brings it back.
 */
export function followUnlocked({ writingDays, recentBlocks, daysSinceLoss }: FollowInputs): boolean {
  if (recentBlocks >= BLOCKS_TO_LOSE) return false;
  if (daysSinceLoss !== null) return daysSinceLoss >= DAYS_TO_FOLLOW;
  return writingDays >= DAYS_TO_FOLLOW;
}
