/**
 * Server-side check that a post was typed by a person. Same rules as
 * app/lib/core/human_check.dart, run again here because the app can be
 * bypassed. The session holds timings and character counts only.
 */
export type InputSource = 'keyboard' | 'voice';

export interface TypingEvent {
  /** Milliseconds since the session started. */
  t: number;
  /** Characters inserted. */
  i: number;
  /** Characters deleted. */
  d: number;
  s: InputSource;
}

export interface TypingSession {
  events: TypingEvent[];
  rejectedPastes: number;
  activeMs: number;
}

export type HumanCheckIssue =
  | 'invalid_session'
  | 'too_few_events'
  | 'too_fast'
  | 'too_regular'
  | 'text_mismatch';

export const MIN_EVENTS_PER_10_CHARS = 4;
export const MAX_CHARS_PER_SECOND = 15;
export const MIN_INTERVAL_VARIATION = 0.15;
export const MIN_INTERVALS_FOR_RHYTHM = 20;
export const MAX_KEYBOARD_CHUNK = 4;
export const IDLE_CUTOFF_MS = 30_000;
// A 400-unit post typed with corrections stays well under this; the cap keeps
// the stored session inside the Data API's request size.
const MAX_EVENTS = 4_000;

/** Parses untrusted JSON from the client into a session, or null. */
export function parseSession(raw: unknown): TypingSession | null {
  if (typeof raw !== 'object' || raw === null) return null;
  const r = raw as Record<string, unknown>;
  if (!Array.isArray(r.events) || r.events.length > MAX_EVENTS) return null;
  const events: TypingEvent[] = [];
  let last = -1;
  for (const e of r.events) {
    if (typeof e !== 'object' || e === null) return null;
    const { t, i, d, s } = e as Record<string, unknown>;
    if (
      !Number.isInteger(t) || !Number.isInteger(i) || !Number.isInteger(d) ||
      (t as number) < last || (i as number) < 0 || (d as number) < 0 ||
      (s !== 'keyboard' && s !== 'voice')
    ) {
      return null;
    }
    last = t as number;
    events.push({ t: t as number, i: i as number, d: d as number, s });
  }
  const rejectedPastes = Number.isInteger(r.rejectedPastes) ? (r.rejectedPastes as number) : 0;
  return { events, rejectedPastes, activeMs: activeDurationMs(events) };
}

/** Typing time recomputed on the server, never trusted from the client. */
export function activeDurationMs(events: TypingEvent[]): number {
  let ms = 0;
  for (let k = 1; k < events.length; k++) {
    const gap = events[k]!.t - events[k - 1]!.t;
    if (gap <= IDLE_CUTOFF_MS) ms += gap;
  }
  return ms;
}

export function evaluate(session: TypingSession, textLength: number): HumanCheckIssue[] {
  const issues: HumanCheckIssue[] = [];
  const kb = session.events.filter((e) => e.s === 'keyboard');
  const kbChars = kb.reduce((sum, e) => sum + e.i, 0);

  // A keyboard change larger than the app allows means the app was bypassed.
  if (kb.some((e) => e.i > MAX_KEYBOARD_CHUNK)) issues.push('invalid_session');

  // Net characters from the session must match the submitted text.
  const net = session.events.reduce((sum, e) => sum + e.i - e.d, 0);
  if (net !== textLength) issues.push('text_mismatch');

  if (kbChars > 0 && (kb.length * 10) / kbChars < MIN_EVENTS_PER_10_CHARS) {
    issues.push('too_few_events');
  }

  if (kb.length >= 2 && kbChars >= 20) {
    const span = kb[kb.length - 1]!.t - kb[0]!.t;
    const cps = span === 0 ? Infinity : (kbChars * 1000) / span;
    if (cps > MAX_CHARS_PER_SECOND) issues.push('too_fast');
  }

  const intervals: number[] = [];
  for (let k = 1; k < session.events.length; k++) {
    const a = session.events[k - 1]!;
    const b = session.events[k]!;
    if (a.s === 'keyboard' && b.s === 'keyboard' && b.i > 0) intervals.push(b.t - a.t);
  }
  if (intervals.length >= MIN_INTERVALS_FOR_RHYTHM) {
    const mean = intervals.reduce((x, y) => x + y, 0) / intervals.length;
    const variance = intervals.reduce((x, v) => x + (v - mean) ** 2, 0) / intervals.length;
    const cv = mean === 0 ? 0 : Math.sqrt(variance) / mean;
    if (cv < MIN_INTERVAL_VARIATION) issues.push('too_regular');
  }

  return issues;
}
