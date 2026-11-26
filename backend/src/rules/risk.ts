/**
 * The activity risk score: how much a person's recent activity looks
 * automated, 0 to 100. At [CHALLENGE_AT] or above they are asked to pass a
 * short typing check before going on; passing it holds for a day. Most people
 * never see it.
 */
export const ACTION_KINDS = ['empathy', 'follow', 'report', 'block', 'post', 'check_failed'] as const;
export type ActionKind = (typeof ACTION_KINDS)[number];

export interface Activity {
  /** Actions of each kind in the last 10 minutes. */
  last10m: Partial<Record<ActionKind, number>>;
  /** Actions of each kind in the last hour. */
  lastHour: Partial<Record<ActionKind, number>>;
  /** Hours since the profile was made. */
  accountAgeHours: number;
  /** Of the person's last five posts, how many scored low. */
  lowScorePosts: number;
  /** Hours since the last passed check, or null if never. */
  hoursSinceCheck: number | null;
}

export const CHALLENGE_AT = 60;
/** A passed check holds this long. */
export const CHECK_VALID_HOURS = 24;

const n = (r: Partial<Record<ActionKind, number>>, k: ActionKind) => r[k] ?? 0;

export function riskScore(a: Activity): number {
  let score = 0;
  // Bursts no person reading posts would make.
  if (n(a.last10m, 'empathy') > 30) score += 40;
  if (n(a.lastHour, 'empathy') > 120) score += 30;
  if (n(a.last10m, 'follow') > 20) score += 40;
  if (n(a.lastHour, 'report') > 10) score += 30;
  if (n(a.lastHour, 'block') > 20) score += 20;
  if (n(a.lastHour, 'post') > 10) score += 20;
  // A brand-new account that goes straight to bulk activity.
  const recent = ACTION_KINDS.reduce((sum, k) => sum + n(a.last10m, k), 0);
  if (a.accountAgeHours < 1 && recent > 20) score += 20;
  // Posts that keep looking copied or automated.
  if (a.lowScorePosts >= 3) score += 60;
  // Failed checks make the next one come sooner.
  score += Math.min(3, n(a.lastHour, 'check_failed')) * 15;
  return Math.min(100, score);
}

export function needsHumanCheck(a: Activity): boolean {
  if (a.hoursSinceCheck !== null && a.hoursSinceCheck < CHECK_VALID_HOURS && n(a.lastHour, 'check_failed') === 0) {
    return false;
  }
  return riskScore(a) >= CHALLENGE_AT;
}

/**
 * Sentences for the typing check. The app shows one; the person types it.
 * Short, ordinary, and in both languages.
 */
export const CHECK_PHRASES: Record<'ko' | 'en', string[]> = {
  ko: [
    '오늘 하늘은 어제보다 조금 더 맑다',
    '천천히 걸으면 보이는 것들이 있다',
    '따뜻한 차 한 잔이 생각나는 오후',
    '작은 일에도 고마운 마음이 든다',
    '창밖으로 바람 소리가 들린다',
  ],
  en: [
    'the sky looks a little clearer today',
    'some things only show when you walk slowly',
    'an afternoon that calls for a warm cup of tea',
    'even small things make me feel grateful',
    'i can hear the wind outside the window',
  ],
};

export function isCheckPhrase(text: string): boolean {
  const t = text.trim().toLowerCase();
  return Object.values(CHECK_PHRASES).some((list) => list.includes(t));
}
