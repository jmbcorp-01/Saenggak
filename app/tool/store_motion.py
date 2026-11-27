"""App Store header and search-result videos: the real app playing on two phones beside the title.

Run after tool/store_video_test.dart (frames) and tool/store_frames.py:
    python3 tool/store_motion.py
Writes build/store/app-store/header/<lang>-header-21x9.mp4 and <lang>-search-3x2.mp4.
"""

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageFilter

sys.path.insert(0, str(Path(__file__).parent))
from store_frames import OUT, device, header  # noqa: E402

VIDEO = Path('build/store/video')
FPS = 30
LOOP = 12 * FPS  # 12 seconds
FADE = 20  # frames blended back into the start so the loop is seamless

# (size, Apple's safe area, name). Search uses the smallest allowed size to keep files small.
FORMATS = [
    ((3840, 1646), (1097, 493, 1646, 661), 'header-21x9'),
    ((1920, 1280), (418, 382, 1084, 515), 'search-3x2'),
]


def slots(size, safe):
    """Where the two phones sit; must match store_frames.header."""
    w, h = size
    sx, sy, sw, _ = safe
    pw = int(min(h * 0.55, (w - sw) / 2 * 0.75))
    return pw, [(10, sx / 2), (-10, sx + sw + (w - sx - sw) / 2)]


def phone(raw, pw, angle):
    return device(raw, pw, 'iphone').rotate(angle, expand=True, resample=Image.BICUBIC)


def render(lang, size, safe, name):
    frames = sorted((VIDEO / lang).glob('frame-*.png'))
    total = len(frames)
    # Left phone: the feed and writing. Right phone: the result and search.
    starts = [0, max(0, total - LOOP)]
    first = [Image.open(frames[s]).convert('RGB') for s in starts]
    base = header(lang, size, safe, first[0], first[1])
    w, h = size
    pw, places = slots(size, safe)
    out = OUT / 'app-store' / 'header' / f'{lang}-{name}-{w}x{h}.mp4'
    out.parent.mkdir(parents=True, exist_ok=True)
    ff = subprocess.Popen(
        ['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{w}x{h}',
         '-r', str(FPS), '-i', '-', '-c:v', 'libx264', '-profile:v', 'high', '-pix_fmt', 'yuv420p',
         '-b:v', '20M' if w > 2000 else '8M', '-movflags', '+faststart', '-an', str(out)],
        stdin=subprocess.PIPE)
    cache = {}

    def screen(i):
        if i not in cache:
            cache[i] = Image.open(frames[min(i, total - 1)]).convert('RGB')
        return cache[i]

    for f in range(LOOP):
        canvas = base.copy()
        for k, (angle, cx) in enumerate(places):
            raw = screen(starts[k] + f)
            if f >= LOOP - FADE:  # ease back to the first frame
                t = (f - (LOOP - FADE) + 1) / FADE
                raw = Image.blend(raw, screen(starts[k]), t)
            p = phone(raw, pw, angle)
            px, py = int(cx - p.width / 2), int(h * 0.16)
            canvas.paste(p, (px, py), p)
        ff.stdin.write(canvas.tobytes())
        if f % 60 == 0:
            cache = {k: v for k, v in cache.items() if k >= starts[0] + f - 1 or k >= starts[1] + f - 1}
    ff.stdin.close()
    ff.wait()
    return out


def main():
    for lang in ['ko', 'en']:
        for size, safe, name in FORMATS:
            print(render(lang, size, safe, name))


if __name__ == '__main__':
    main()
