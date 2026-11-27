import { DetectFacesCommand, DetectModerationLabelsCommand, RekognitionClient } from '@aws-sdk/client-rekognition';
import { DeleteObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import type { PhotoChecker, PhotoStore, PhotoVerdict } from './ports.js';

/** Moderation categories that may not appear in a profile photo (top level or parent). */
const BLOCKED_LABELS = new Set([
  'Explicit',
  'Explicit Nudity',
  'Non-Explicit Nudity of Intimate parts and Kissing',
  'Swimwear or Underwear',
  'Violence',
  'Visually Disturbing',
  'Hate Symbols',
  'Rude Gestures',
  'Drugs & Tobacco',
]);

/** How sure Rekognition must be that something is a face. */
const FACE_CONFIDENCE = 90;
/** The face must fill at least this share of the photo, so it is a portrait, not a crowd shot. */
const MIN_FACE_AREA = 0.05;
const MIN_SHARPNESS = 15;
const MIN_BRIGHTNESS = 15;
const MAX_YAW = 45;
const MAX_PITCH = 35;

/**
 * Profile photos must show exactly one clear human face, roughly facing the
 * camera, and nothing in the moderation categories above. Amazon Rekognition
 * does both checks.
 */
export class RekognitionPhotoChecker implements PhotoChecker {
  constructor(private readonly client = new RekognitionClient({})) {}

  async check(jpeg: Uint8Array): Promise<PhotoVerdict> {
    const image = { Bytes: jpeg };
    const [faces, moderation] = await Promise.all([
      this.client.send(new DetectFacesCommand({ Image: image, Attributes: ['DEFAULT'] })),
      this.client.send(new DetectModerationLabelsCommand({ Image: image, MinConfidence: 70 })),
    ]);

    const blocked = (moderation.ModerationLabels ?? []).some(
      (l) => BLOCKED_LABELS.has(l.Name ?? '') || BLOCKED_LABELS.has(l.ParentName ?? ''),
    );
    if (blocked) return { ok: false, problem: 'inappropriate' };

    const found = (faces.FaceDetails ?? []).filter((f) => (f.Confidence ?? 0) >= FACE_CONFIDENCE);
    if (found.length === 0) return { ok: false, problem: 'no_face' };
    if (found.length > 1) return { ok: false, problem: 'many_faces' };

    const face = found[0]!;
    const box = face.BoundingBox ?? {};
    const area = (box.Width ?? 0) * (box.Height ?? 0);
    const clear =
      area >= MIN_FACE_AREA &&
      (face.Quality?.Sharpness ?? 0) >= MIN_SHARPNESS &&
      (face.Quality?.Brightness ?? 0) >= MIN_BRIGHTNESS &&
      Math.abs(face.Pose?.Yaw ?? 0) <= MAX_YAW &&
      Math.abs(face.Pose?.Pitch ?? 0) <= MAX_PITCH;
    return clear ? { ok: true } : { ok: false, problem: 'unclear' };
  }
}

export class S3PhotoStore implements PhotoStore {
  constructor(
    private readonly bucket = process.env.PHOTO_BUCKET!,
    private readonly client = new S3Client({}),
  ) {}

  async put(key: string, bytes: Uint8Array, contentType = 'image/jpeg'): Promise<void> {
    await this.client.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: key,
        Body: bytes,
        ContentType: contentType,
        // Each photo gets a new key, so it can be cached forever.
        CacheControl: 'public, max-age=31536000, immutable',
      }),
    );
  }

  async remove(key: string): Promise<void> {
    await this.client.send(new DeleteObjectCommand({ Bucket: this.bucket, Key: key }));
  }
}

/** Public address of a stored photo, or null. */
export function photoUrl(key: string | null | undefined): string | null {
  const base = process.env.PHOTO_BASE_URL;
  return key && base ? `${base.replace(/\/$/, '')}/${key}` : null;
}
