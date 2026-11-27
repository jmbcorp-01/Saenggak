import { compose, type PushBatch, type PushMessage } from './messages.js';

export interface PushToken {
  token: string;
  platform: 'ios' | 'android' | 'web';
}

export interface PushStore {
  /** New events for everyone with a device, grouped by person and kind, and
   *  moves each person's mark to now so nothing goes out twice. */
  takeBatches(): Promise<PushBatch[]>;
  tokens(userIds: string[]): Promise<Map<string, PushToken[]>>;
  /** Unread notifications per person, for the number on the app icon. */
  unread(userIds: string[]): Promise<Map<string, number>>;
  removeTokens(tokens: string[]): Promise<void>;
}

/** Sends one message to one device. 'gone' means the token is no longer valid. */
export interface PushClient {
  send(token: PushToken, message: PushMessage): Promise<'sent' | 'gone'>;
}

export interface PushReport {
  batches: number;
  sent: number;
  failed: number;
  removed: number;
}

/** Runs every minute: one alert per person and kind, to each of their devices. */
export async function sendPushes(store: PushStore, client: PushClient | null): Promise<PushReport> {
  const report: PushReport = { batches: 0, sent: 0, failed: 0, removed: 0 };
  // Without Firebase set up the mark still moves, so turning it on later
  // does not flood people with old events.
  const batches = await store.takeBatches();
  report.batches = batches.length;
  if (!client || batches.length === 0) return report;
  const people = [...new Set(batches.map((b) => b.userId))];
  const [devices, unread] = await Promise.all([store.tokens(people), store.unread(people)]);
  const gone: string[] = [];
  await Promise.all(
    batches.flatMap((b) =>
      (devices.get(b.userId) ?? []).map(async (t) => {
        try {
          if ((await client.send(t, compose(b, unread.get(b.userId)))) === 'gone') gone.push(t.token);
          else report.sent++;
        } catch (e) {
          report.failed++;
          console.error('push failed', t.platform, e);
        }
      }),
    ),
  );
  if (gone.length > 0) await store.removeTokens([...new Set(gone)]);
  report.removed = new Set(gone).size;
  return report;
}
