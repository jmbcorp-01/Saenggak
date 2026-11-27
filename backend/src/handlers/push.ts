import { sendPushes } from '../push/sender.js';
import { fcmFromSecret, type FcmClient } from '../services/fcm.js';
import { AuroraPushRepository, type PushRepository } from '../services/pushRepository.js';
import { json, parseBody, safely, userId, type Event } from './http.js';

type Deps = { push: PushRepository };

const PLATFORMS = ['ios', 'android', 'web'] as const;
const isToken = (v: unknown): v is string => typeof v === 'string' && /^[\w:.-]{20,4096}$/.test(v);

/**
 * Push alerts outside the app:
 *   PUT  /me/push           { token, platform }  registers this device
 *   POST /me/push/remove    { token }            on sign-out, or when the person turns push off
 *   GET  /me/push-settings  { empathy, follow, posts }
 *   PUT  /me/push-settings  { empathy, follow, posts }
 *
 * Every minute EventBridge runs the sender ({ job: 'send' }), which sends one
 * alert per person and kind for what happened since the last run.
 */
export const pushHandler = (deps: Deps) =>
  safely(async (event: Event) => {
    const me = userId(event);
    const b = parseBody(event);
    switch (event.routeKey) {
      case 'PUT /me/push': {
        const platform = PLATFORMS.find((p) => p === b?.platform);
        if (!isToken(b?.token) || !platform) return json(400, { error: 'bad_request' });
        return (await deps.push.saveToken(me, b.token, platform))
          ? json(204, null)
          : json(409, { error: 'profile_required' });
      }

      case 'POST /me/push/remove': {
        if (!isToken(b?.token)) return json(400, { error: 'bad_request' });
        await deps.push.removeToken(me, b.token);
        return json(204, null);
      }

      case 'GET /me/push-settings': {
        const s = await deps.push.pushSettings(me);
        return s ? json(200, s) : json(409, { error: 'profile_required' });
      }

      case 'PUT /me/push-settings': {
        const s = { empathy: b?.empathy, follow: b?.follow, posts: b?.posts };
        if (!Object.values(s).every((v) => typeof v === 'boolean')) return json(400, { error: 'bad_request' });
        const settings = s as { empathy: boolean; follow: boolean; posts: boolean };
        return (await deps.push.setPushSettings(me, settings))
          ? json(200, settings)
          : json(409, { error: 'profile_required' });
      }
    }
    return json(404, { error: 'not_found' });
  });

let repo: AuroraPushRepository | undefined;
// Kept between runs so the Google access token is reused for its hour.
let client: Promise<FcmClient | null> | undefined;

export async function handler(event: Event | { job: 'send' }) {
  repo ??= new AuroraPushRepository();
  if ('job' in event) {
    client ??= fcmFromSecret();
    const fcm = await client;
    // A secret pasted after the last cold start is read on the next one.
    if (!fcm) client = undefined;
    return sendPushes(repo, fcm);
  }
  return pushHandler({ push: repo })(event);
}
