"""Adds captions and a background to the raw store screenshots.

Run after `flutter test tool/store_screenshots_test.dart`:
    python3 tool/store_frames.py
Writes build/store/<store>/<lang>/... ready to upload.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

RAW = Path('build/store/raw')
OUT = Path('build/store')
BOLD = 'assets/fonts/NotoSansKR-Bold.ttf'
REGULAR = 'assets/fonts/NotoSansKR-Regular.ttf'
BAND = (243, 239, 233)
INK = (26, 26, 26)
MUTED = (110, 104, 98)
ACCENT = (210, 69, 44)

CAPTIONS = {
    'ko': [
        ('사람이 직접 쓴 생각만', 'AI 글도, 붙여넣기도 없는 곳'),
        ('하루 한 줄, 진짜 사람의 생각', '다른 언어로 쓴 글도 번역해서 보여줘요'),
        ('한 글자씩, 내 속도로', '붙여넣기는 막고, 쓴 시간을 기록해요'),
        ('비슷한 생각을 한 사람이 있어요', '처음 쓴 표현도 알려줘요'),
        ('단어가 아닌 뜻으로 찾기', '비슷한 생각을 모아 보여줘요'),
        ('쓴 날이 쌓이는 내 기록', '꾸준히 쓰면 팔로우가 열려요'),
    ],
    'en': [
        ('Only thoughts typed by hand', 'No AI text. No pasting.'),
        ('Real people, one thought a day', 'Posts in other languages come translated'),
        ('One letter at a time', 'Pasting is blocked. Your typing time is kept.'),
        ('Someone thought it too', 'And see the phrases you wrote first'),
        ('Search by meaning', 'Find thoughts close to yours'),
        ('Your writing days add up', 'Write regularly to unlock following'),
    ],
}
NAMES = ['start', 'feed', 'compose', 'result', 'search', 'profile']
# device -> (store folder, canvas size)
DEVICES = {
    'iphone': ('app-store/iphone', (1206, 2622)),
    'ipad': ('app-store/ipad-13', (2064, 2752)),
    'android': ('google-play/phone', (1080, 1920)),
}


def fit(draw, text, font_path, size, max_width):
    while size > 10:
        font = ImageFont.truetype(font_path, size)
        if draw.textlength(text, font=font) <= max_width:
            return font
        size -= 2
    return ImageFont.truetype(font_path, size)


def rounded(img, radius):
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius, fill=255)
    return mask


def frame(raw, size, title, sub):
    w, h = size
    canvas = Image.new('RGB', size, BAND)
    draw = ImageDraw.Draw(canvas)
    unit = w / 100
    top = int(h * 0.055)
    title_font = fit(draw, title, BOLD, int(unit * 7.2), w * 0.88)
    sub_font = fit(draw, sub, REGULAR, int(unit * 4.2), w * 0.88)
    draw.text((w / 2, top), title, font=title_font, fill=INK, anchor='mt')
    tb = draw.textbbox((w / 2, top), title, font=title_font, anchor='mt')
    draw.text((w / 2, tb[3] + unit * 2.2), sub, font=sub_font, fill=MUTED, anchor='mt')
    sb = draw.textbbox((w / 2, tb[3] + unit * 2.2), sub, font=sub_font, anchor='mt')

    # The screen, slightly smaller than the canvas, running off the bottom edge.
    y = int(sb[3] + unit * 5)
    shot_w = int(w * 0.84)
    shot = raw.resize((shot_w, int(raw.height * shot_w / raw.width)), Image.LANCZOS)
    x = (w - shot_w) // 2
    radius = int(unit * 5)
    border = max(2, int(unit * 0.35))

    shadow = Image.new('L', size, 0)
    ImageDraw.Draw(shadow).rounded_rectangle((x, y + unit, x + shot_w, y + shot.height + unit), radius, fill=70)
    shadow = shadow.filter(ImageFilter.GaussianBlur(unit * 2))
    canvas.paste((120, 100, 80), (0, 0), shadow)
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((x - border, y - border, x + shot_w + border, y + shot.height + border), radius + border, fill=INK)
    canvas.paste(shot, (x, y), rounded(shot, radius))
    return canvas


def feature_graphic(lang):
    w, h = 1024, 500
    canvas = Image.new('RGB', (w, h), BAND)
    icon = Image.open('assets/icon/icon.png').convert('RGBA').resize((300, 300), Image.LANCZOS)
    canvas.paste(icon, (90, 100), rounded(icon, 66))
    draw = ImageDraw.Draw(canvas)
    name, line1, line2 = (
        ('생각', '사람이 직접 쓴 생각만', 'AI 글도, 붙여넣기도 없이')
        if lang == 'ko'
        else ('Saenggak', 'Only thoughts typed by hand', 'No AI text. No pasting.')
    )
    draw.text((450, 150), name, font=ImageFont.truetype(BOLD, 72), fill=ACCENT)
    draw.text((450, 262), line1, font=fit(draw, line1, BOLD, 40, 540), fill=INK)
    draw.text((450, 322), line2, font=fit(draw, line2, REGULAR, 30, 540), fill=MUTED)
    return canvas


def main():
    for lang, captions in CAPTIONS.items():
        for device, (folder, size) in DEVICES.items():
            for n, (name, (title, sub)) in enumerate(zip(NAMES, captions), start=1):
                raw = Image.open(RAW / f'{lang}-{device}-{n}-{name}.png').convert('RGB')
                out = OUT / folder / lang / f'{n}-{name}.png'
                out.parent.mkdir(parents=True, exist_ok=True)
                frame(raw, size, title, sub).save(out, optimize=True)
        out = OUT / 'google-play' / 'feature-graphic' / f'{lang}.png'
        out.parent.mkdir(parents=True, exist_ok=True)
        feature_graphic(lang).save(out)
    icon = Image.open('assets/icon/icon.png').convert('RGBA').resize((512, 512), Image.LANCZOS)
    icon.save(OUT / 'google-play' / 'icon-512.png')


if __name__ == '__main__':
    main()
