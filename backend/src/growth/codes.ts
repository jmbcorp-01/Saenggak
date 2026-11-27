import { randomInt } from 'node:crypto';
import type { Platform } from '../services/growthPorts.js';

/** No 0/O or 1/I/L, so a code read aloud or typed from a screenshot comes out right. */
const INVITE_LETTERS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const LINK_LETTERS = 'abcdefghjkmnpqrstuvwxyz23456789';

const pick = (letters: string, n: number) => Array.from({ length: n }, () => letters[randomInt(letters.length)]).join('');

/** A person's invite code: 8 capitals and digits. */
export const newInviteCode = () => pick(INVITE_LETTERS, 8);

/** A link code for a promo post or campaign, with a short channel prefix such as "ig". */
export const newLinkCode = (prefix: string) => `${prefix}-${pick(LINK_LETTERS, 6)}`;

/** Invite codes are capitals; link codes are lower case with a dash. Both are matched without case. */
export const CODE = /^[A-Za-z0-9][A-Za-z0-9-]{2,31}$/;
export const isCode = (v: unknown): v is string => typeof v === 'string' && CODE.test(v);

/** Admin-made link codes: lower case, digits and dashes. */
export const LINK_CODE = /^[a-z0-9][a-z0-9-]{2,31}$/;
export const CHANNELS = ['instagram', 'threads', 'x', 'youtube', 'tiktok', 'community', 'press', 'web', 'event', 'other'] as const;
export const isChannel = (v: unknown): v is (typeof CHANNELS)[number] => CHANNELS.includes(v as (typeof CHANNELS)[number]);

export function platformOf(userAgent: string | undefined): Platform {
  const ua = userAgent ?? '';
  if (/iPhone|iPad|iPod/i.test(ua)) return 'ios';
  if (/Android/i.test(ua)) return 'android';
  return 'web';
}

/** 21:00 in Korea, when people read the most, as an instant: the next one after [now]. */
export function nextEveningSlot(now: Date): Date {
  // Korea has no daylight saving: 21:00 KST is always 12:00 UTC.
  const slot = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 12, 0, 0));
  if (slot.getTime() <= now.getTime()) slot.setUTCDate(slot.getUTCDate() + 1);
  return slot;
}

/** Today's date in Korea, YYYY-MM-DD. */
export function koreaDay(now: Date): string {
  return new Date(now.getTime() + 9 * 3600_000).toISOString().slice(0, 10);
}

export function addDays(day: string, n: number): string {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}
