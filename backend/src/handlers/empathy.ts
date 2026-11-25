import type { Repository } from '../services/ports.js';
import { AuroraRepository } from '../services/repository.js';
import { json, userId, type Event } from './http.js';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** POST /posts/{id}/empathy  toggles the viewer's 공감. */
export const empathyHandler = (repo: Repository) => async (event: Event) => {
  const postId = event.pathParameters?.id;
  if (!postId || !UUID.test(postId)) return json(400, { error: 'bad_request' });
  const result = await repo.toggleEmpathy(postId, userId(event));
  if (!result) return json(404, { error: 'not_found' });
  return json(200, result);
};

let live: Repository | undefined;
export const handler = (event: Event) => empathyHandler((live ??= new AuroraRepository()))(event);
