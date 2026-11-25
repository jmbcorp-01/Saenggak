import { randomUUID } from 'node:crypto';
import type { PhotoChecker, PhotoProblem, PhotoStore, Repository } from '../services/ports.js';
import { WRITES_PER_HOUR } from './publish.js';

export interface PhotoDeps {
  repo: Repository;
  photoChecker: PhotoChecker;
  photoStore: PhotoStore;
}

/** The app sends a 512px JPEG; anything near Rekognition's 5 MB limit is not one. */
export const MAX_PHOTO_BYTES = 2 * 1024 * 1024;

export type PhotoResult =
  | { kind: 'saved'; photoKey: string }
  | { kind: 'bad_image' }
  | { kind: 'profile_required' }
  | { kind: 'rate_limited' }
  | { kind: 'refused'; problem: PhotoProblem };

function isJpeg(b: Uint8Array): boolean {
  return b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff;
}

/**
 * Replaces the profile photo after checking it shows one clear human face.
 * The app only offers the camera (no gallery), and the server checks the face.
 */
export async function savePhoto(deps: PhotoDeps, userId: string, base64: unknown): Promise<PhotoResult> {
  if (typeof base64 !== 'string' || base64.length > (MAX_PHOTO_BYTES * 4) / 3 + 4) return { kind: 'bad_image' };
  const jpeg = new Uint8Array(Buffer.from(base64, 'base64'));
  if (!isJpeg(jpeg) || jpeg.length > MAX_PHOTO_BYTES) return { kind: 'bad_image' };

  if (!(await deps.repo.profile(userId, userId))) return { kind: 'profile_required' };
  if (!(await deps.repo.recordWrite(userId, WRITES_PER_HOUR))) return { kind: 'rate_limited' };

  const verdict = await deps.photoChecker.check(jpeg);
  if (!verdict.ok) return { kind: 'refused', problem: verdict.problem };

  const key = `photos/${userId}/${randomUUID()}.jpg`;
  await deps.photoStore.put(key, jpeg);
  const set = await deps.repo.setPhoto(userId, key);
  if (!set) {
    await deps.photoStore.remove(key);
    return { kind: 'profile_required' };
  }
  if (set.previous) await deps.photoStore.remove(set.previous).catch(() => undefined);
  return { kind: 'saved', photoKey: key };
}
