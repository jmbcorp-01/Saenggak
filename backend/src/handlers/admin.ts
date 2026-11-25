import type { AdminRepository, PhotoStore } from '../services/ports.js';
import { AuroraAdminRepository } from '../services/adminRepository.js';
import { photoUrl, S3PhotoStore } from '../services/photos.js';
import { isUuid, json, parseBody, safely, userId, type Event } from './http.js';

const PAGE_SIZE = 30;
export const ADMIN_GROUP = 'admins';

type Deps = { admin: AdminRepository; photoStore: PhotoStore };

/**
 * Whether the signed-in person is in the Cognito admins group. API Gateway
 * passes list claims as text like "[admins other]", so both forms are read.
 */
export function isAdmin(event: Event): boolean {
  const raw: unknown = event.requestContext.authorizer.jwt.claims['cognito:groups'];
  const groups = Array.isArray(raw)
    ? raw.map(String)
    : typeof raw === 'string'
      ? raw.replace(/^\[|\]$/g, '').split(/[\s,]+/)
      : [];
  return groups.includes(ADMIN_GROUP);
}

const note = (v: unknown) => (typeof v === 'string' ? v.trim().slice(0, 500) : '');

/**
 * The admin pages. Only people in the admins group get past the first line.
 *   GET    /admin/stats
 *   GET    /admin/review?before=<createdAt>      blocked posts awaiting review
 *   POST   /admin/posts/{id}/review              { decision: 'publish' | 'keep_blocked' }
 *   POST   /admin/posts/{id}/remove              { note }
 *   GET    /admin/users?q=<handle or name>
 *   PUT    /admin/users/{id}/suspension          { suspended, reason }
 *   DELETE /admin/users/{id}/photo
 */
export const adminHandler = (deps: Deps) =>
  safely(async (event: Event) => {
    if (!isAdmin(event)) return json(403, { error: 'forbidden' });
    const me = userId(event);
    const id = event.pathParameters?.id;
    const { admin } = deps;

    switch (event.routeKey) {
      case 'GET /admin/stats':
        return json(200, await admin.stats());

      case 'GET /admin/review': {
        const before = event.queryStringParameters?.before;
        const items = await admin.reviewQueue(PAGE_SIZE, before && !Number.isNaN(Date.parse(before)) ? before : undefined);
        const last = items.at(-1);
        return json(200, { items, next: items.length === PAGE_SIZE && last ? last.createdAt : null });
      }

      case 'POST /admin/posts/{id}/review': {
        const decision = parseBody(event)?.decision;
        if (!isUuid(id) || (decision !== 'publish' && decision !== 'keep_blocked')) {
          return json(400, { error: 'bad_request' });
        }
        return (await admin.reviewPost(id, me, decision)) ? json(204, null) : json(404, { error: 'not_found' });
      }

      case 'POST /admin/posts/{id}/remove': {
        if (!isUuid(id)) return json(400, { error: 'bad_request' });
        const done = await admin.removePost(id, me, note(parseBody(event)?.note));
        return done ? json(204, null) : json(404, { error: 'not_found' });
      }

      case 'GET /admin/users': {
        const q = (event.queryStringParameters?.q ?? '').trim().toLowerCase().replace(/^@/, '').slice(0, 40);
        const users = await admin.searchUsers(q, PAGE_SIZE);
        return json(200, { items: users.map((u) => ({ ...u, photoUrl: photoUrl(u.photoKey) })) });
      }

      case 'PUT /admin/users/{id}/suspension': {
        const b = parseBody(event);
        if (!isUuid(id) || typeof b?.suspended !== 'boolean') return json(400, { error: 'bad_request' });
        if (id === me && b.suspended) return json(400, { error: 'self' });
        const done = await admin.setSuspended(id, me, b.suspended, note(b.reason));
        return done ? json(200, { suspended: b.suspended }) : json(404, { error: 'not_found' });
      }

      case 'DELETE /admin/users/{id}/photo': {
        if (!isUuid(id)) return json(400, { error: 'bad_request' });
        const result = await admin.removePhoto(id, me);
        if (!result) return json(404, { error: 'not_found' });
        if (result.previous) await deps.photoStore.remove(result.previous);
        return json(204, null);
      }
    }
    return json(404, { error: 'not_found' });
  });

let live: Deps | undefined;
export const handler = (event: Event) =>
  adminHandler((live ??= { admin: new AuroraAdminRepository(), photoStore: new S3PhotoStore() }))(event);
