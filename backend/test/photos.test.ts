import { describe, expect, it } from 'vitest';
import { RekognitionPhotoChecker } from '../src/services/photos.js';

const face = (over: Record<string, unknown> = {}) => ({
  Confidence: 99,
  BoundingBox: { Width: 0.4, Height: 0.5 },
  Quality: { Sharpness: 80, Brightness: 70 },
  Pose: { Yaw: 5, Pitch: 3 },
  ...over,
});

function checker(faces: unknown[], labels: unknown[] = []) {
  const client = {
    send: async (cmd: { constructor: { name: string } }) =>
      cmd.constructor.name === 'DetectFacesCommand' ? { FaceDetails: faces } : { ModerationLabels: labels },
  };
  return new RekognitionPhotoChecker(client as never);
}

const img = new Uint8Array([0xff, 0xd8, 0xff]);

describe('RekognitionPhotoChecker', () => {
  it('accepts one clear face', async () => {
    expect(await checker([face()]).check(img)).toEqual({ ok: true });
  });

  it('refuses no face, several faces, and a small or blurry face', async () => {
    expect(await checker([]).check(img)).toEqual({ ok: false, problem: 'no_face' });
    expect(await checker([face({ Confidence: 40 })]).check(img)).toEqual({ ok: false, problem: 'no_face' });
    expect(await checker([face(), face()]).check(img)).toEqual({ ok: false, problem: 'many_faces' });
    expect(await checker([face({ BoundingBox: { Width: 0.1, Height: 0.1 } })]).check(img)).toEqual({
      ok: false,
      problem: 'unclear',
    });
    expect(await checker([face({ Quality: { Sharpness: 3, Brightness: 70 } })]).check(img)).toEqual({
      ok: false,
      problem: 'unclear',
    });
  });

  it('refuses inappropriate content even with a clear face', async () => {
    const labels = [{ Name: 'Graphic Male Nudity', ParentName: 'Explicit Nudity', Confidence: 95 }];
    expect(await checker([face()], labels).check(img)).toEqual({ ok: false, problem: 'inappropriate' });
  });
});
