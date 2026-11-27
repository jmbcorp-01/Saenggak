"""Turns the raw store screenshots into finished App Store and Google Play images.

Run after `flutter test tool/store_screenshots_test.dart`:
    python3 tool/store_frames.py
Writes build/store/<store>/<lang>/... ready to upload.
"""

import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

RAW = Path('build/store/raw')
OUT = Path('build/store')
BOLD = 'assets/fonts/NotoSansKR-Bold.ttf'
MEDIUM = 'assets/fonts/NotoSansKR-Medium.ttf'
ICONS = os.path.join(os.environ.get('FLUTTER_ROOT', '/home/claude/sdk/flutter'),
                     'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')

CREAM = (246, 241, 233)
INK = (24, 22, 21)
RED = (210, 69, 44)
RED_DARK = (150, 38, 22)
WARM = (255, 214, 170)

# Background themes: (top colour, bottom colour, title, highlight, subtitle)
THEMES = {
    'red': (RED, RED_DARK, (255, 255, 255), WARM, (255, 228, 218)),
    'cream': ((250, 246, 239), (238, 228, 214), INK, RED, (112, 100, 90)),
    'ink': ((44, 40, 38), (14, 13, 12), (255, 255, 255), (255, 120, 92), (190, 182, 175)),
}
ORDER = ['red', 'cream', 'ink', 'red', 'cream', 'ink']

# Title lines, with the word to highlight in [brackets]; subtitle; floating card (icon, text); card side.
SLIDES = {
    'ko': [
        (['[직접 쓴] 생각만', '모이는 곳'], 'AI 글도, 붙여넣기도 없어요', (0xF030F, '하루 한 줄이면 충분해요'), 'right'),
        (['진짜 [사람]의', '하루 한 생각'], '다른 언어 글도 번역해서 보여줘요', (0xF833, '2분 18초 동안 직접 썼어요'), 'left'),
        (['한 글자씩,', '[내 속도로]'], '쓴 시간이 글과 함께 남아요', (0xF66E, '붙여넣기는 막혀 있어요'), 'right'),
        (['[비슷한 생각]을 한', '사람이 있어요'], '처음 쓴 표현도 찾아줘요', (0xF7C6, '4명이 비슷한 생각을 했어요'), 'left'),
        (['단어 말고', '[뜻]으로 찾기'], '비슷한 마음으로 쓴 글을 모아요', (0xF89F, '단어가 달라도 찾아줘요'), 'right'),
        (['쓴 날이 쌓이는', '[내 기록]'], '꾸준히 쓰면 팔로우가 열려요', (0xF06C8, '23일째 쓰고 있어요'), 'left'),
    ],
    'en': [
        (['Only thoughts', '[typed by hand]'], 'No AI text. No pasting.', (0xF030F, 'One line a day is enough'), 'right'),
        (['Real [people],', 'one thought a day'], 'Posts in other languages come translated', (0xF833, 'Typed by hand in 2m 18s'), 'left'),
        (['One letter', '[at a time]'], 'Your typing time stays with the post', (0xF66E, 'Pasting is turned off'), 'right'),
        (['Someone thought', '[it too]'], 'And see the phrases you wrote first', (0xF7C6, '4 people thought the same'), 'left'),
        (['Search by', '[meaning]'], 'Find thoughts close to yours', (0xF89F, 'Even with different words'), 'right'),
        (['Your writing', '[days add up]'], 'Write regularly to unlock following', (0xF06C8, 'Writing for 23 days'), 'left'),
    ],
}
NAMES = ['start', 'feed', 'compose', 'result', 'search', 'profile']
# device -> (store folder, canvas size, frame kind)
DEVICES = {
    'iphone': ('app-store/iphone', (1206, 2622), 'iphone'),
    'ipad': ('app-store/ipad-13', (2064, 2752), 'ipad'),
    'android': ('google-play/phone', (1080, 1920), 'android'),
}


def font(path, size):
    return ImageFont.truetype(path, max(8, int(size)))


def gradient(size, top, bottom):
    w, h = size
    col = Image.new('RGB', (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        col.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return col.resize((w, h))


def mask_rounded(size, radius):
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return m


def shadow(canvas, box, radius, blur, alpha=110, offset=(0, 0)):
    layer = Image.new('L', canvas.size, 0)
    x0, y0, x1, y1 = box
    ImageDraw.Draw(layer).rounded_rectangle(
        (x0 + offset[0], y0 + offset[1], x1 + offset[0], y1 + offset[1]), radius, fill=alpha)
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    canvas.paste((0, 0, 0), (0, 0), layer)


def watermark(canvas, colour, alpha, scale, pos):
    """The brand mark, large and faint, partly off the canvas."""
    mark = Image.open('assets/icon/foreground.png').convert('RGBA')
    size = int(canvas.width * scale)
    mark = mark.resize((size, size), Image.LANCZOS)
    a = mark.split()[3].point(lambda v: v * alpha // 255)
    canvas.paste(colour, pos, a)


def device(raw, width, kind):
    """The raw screen inside a phone or tablet body. Returns an RGBA image."""
    bezel = int(width * (0.028 if kind != 'ipad' else 0.022))
    screen_w = width - 2 * bezel
    screen = raw.resize((screen_w, int(raw.height * screen_w / raw.width)), Image.LANCZOS)
    height = screen.height + 2 * bezel
    outer_r = int(width * (0.135 if kind == 'iphone' else 0.11 if kind == 'android' else 0.06))
    inner_r = max(4, outer_r - bezel)
    body = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    d = ImageDraw.Draw(body)
    d.rounded_rectangle((0, 0, width - 1, height - 1), outer_r, fill=(18, 18, 20, 255))
    d.rounded_rectangle((2, 2, width - 3, height - 3), outer_r - 2, outline=(70, 70, 74, 255), width=max(2, bezel // 6))
    body.paste(screen, (bezel, bezel), mask_rounded(screen.size, inner_r))
    if kind == 'iphone':
        iw, ih = int(width * 0.30), int(width * 0.085)
        top = bezel + int(width * 0.028)
        d.rounded_rectangle(((width - iw) // 2, top, (width + iw) // 2, top + ih), ih // 2, fill=(0, 0, 0, 255))
    elif kind == 'android':
        r = int(width * 0.022)
        cx, cy = width // 2, bezel + int(width * 0.04)
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(0, 0, 0, 255))
    else:
        r = int(width * 0.006)
        cx, cy = width // 2, bezel // 2
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(40, 40, 44, 255))
    return body


def title_block(draw, lines, cx, y, size, colour, highlight, max_w):
    """Draws centred title lines; [bracketed] words take the highlight colour."""
    f = font(BOLD, size)
    for line in lines:
        plain = line.replace('[', '').replace(']', '')
        while draw.textlength(plain, font=f) > max_w and f.size > 10:
            f = font(BOLD, f.size - 4)
    line_h = int(f.size * 1.22)
    for line in lines:
        parts, buf, hi = [], '', False
        for ch in line:
            if ch in '[]':
                if buf:
                    parts.append((buf, hi))
                buf, hi = '', ch == '['
            else:
                buf += ch
        if buf:
            parts.append((buf, hi))
        total = sum(draw.textlength(t, font=f) for t, _ in parts)
        x = cx - total / 2
        for text, is_hi in parts:
            draw.text((x, y), text, font=f, fill=highlight if is_hi else colour)
            x += draw.textlength(text, font=f)
        y += line_h
    return y


def card(canvas, icon, text, anchor, side, unit, accent):
    """A floating white card with an icon and a short line."""
    d = ImageDraw.Draw(canvas)
    tf = font(BOLD, unit * 3.9)
    icf = ImageFont.truetype(ICONS, int(unit * 5))
    pad = int(unit * 3)
    badge = int(unit * 8.6)
    tw = d.textlength(text, font=tf)
    w = int(pad + badge + unit * 2.6 + tw + pad * 1.2)
    h = int(badge + pad * 1.6)
    x = anchor[0] - (w if side == 'left' else 0)
    x = min(max(x, int(unit * 3)), canvas.width - w - int(unit * 3))
    y = anchor[1]
    r = h // 2
    shadow(canvas, (x, y, x + w, y + h), r, unit * 2.4, alpha=90, offset=(0, int(unit * 1.2)))
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle((x, y, x + w, y + h), r, fill=(255, 255, 255))
    bx, by = x + pad, y + (h - badge) // 2
    d.ellipse((bx, by, bx + badge, by + badge), fill=accent)
    d.text((bx + badge / 2, by + badge / 2), chr(icon), font=icf, fill=(255, 255, 255), anchor='mm')
    d.text((bx + badge + unit * 2.6, y + h / 2), text, font=tf, fill=INK, anchor='lm')


def slide(raw, size, kind, theme, lines, sub, callout, side, card_at=0.42):
    w, h = size
    top, bottom, tcol, hcol, scol = THEMES[theme]
    canvas = gradient(size, top, bottom)
    unit = w / 100 if kind != 'ipad' else w / 128
    mark_col = (255, 255, 255) if theme != 'cream' else RED
    watermark(canvas, mark_col, 26 if theme != 'cream' else 22, 0.95, (int(w * 0.42), int(-w * 0.18)))
    draw = ImageDraw.Draw(canvas)

    y = int(h * 0.06)
    y = title_block(draw, lines, w / 2, y, unit * 9.6, tcol, hcol, w * 0.9)
    sf = font(MEDIUM, unit * 4.1)
    while draw.textlength(sub, font=sf) > w * 0.88:
        sf = font(MEDIUM, sf.size - 2)
    draw.text((w / 2, y + unit * 3), sub, font=sf, fill=scol, anchor='mt')
    y = int(y + unit * 3 + sf.size * 1.4 + unit * 6)

    dev_w = int(w * (0.80 if kind != 'ipad' else 0.84))
    body = device(raw, dev_w, kind)
    x = (w - dev_w) // 2
    radius = int(dev_w * 0.12)
    shadow(canvas, (x, y, x + dev_w, y + body.height), radius, unit * 4, alpha=120, offset=(0, int(unit * 2)))
    canvas.paste(body, (x, y), body)

    accent = RED if theme != 'red' else INK
    anchor_y = int(y + (h - y) * card_at)
    anchor_x = int(w * 0.94) if side == 'left' else int(w * 0.06)
    card(canvas, callout[0], callout[1], (anchor_x, anchor_y), side, unit, accent)
    return canvas


def promo(lang, size, raw):
    """Feature graphic / header: brand on the left, the feed on a tilted phone on the right."""
    w, h = size
    canvas = gradient(size, RED, RED_DARK)
    unit = h / 100
    watermark(canvas, (255, 255, 255), 22, h / w * 1.5, (int(-h * 0.35), int(h * 0.05)))
    d = ImageDraw.Draw(canvas)
    name, l1, l2 = (
        ('생각', '사람이 직접 쓴 생각만', 'AI 글도, 붙여넣기도 없이')
        if lang == 'ko' else ('Saenggak', 'Only thoughts typed by hand', 'No AI text. No pasting.')
    )
    left = int(w * 0.08)
    text_w = w * 0.5
    icon = Image.open('assets/icon/icon.png').convert('RGBA').resize((int(unit * 17), int(unit * 17)), Image.LANCZOS)
    top = int(h * 0.2)
    canvas.paste(icon, (left, top), mask_rounded(icon.size, int(unit * 4)))
    d.text((left + unit * 21, top + unit * 8.5), name, font=font(BOLD, unit * 10), fill=(255, 255, 255), anchor='lm')
    f1 = font(BOLD, unit * 11)
    while d.textlength(l1, font=f1) > text_w:
        f1 = font(BOLD, f1.size - 2)
    d.text((left, top + unit * 26), l1, font=f1, fill=(255, 255, 255))
    d.text((left, top + unit * 26 + f1.size * 1.35), l2, font=font(MEDIUM, f1.size * 0.62), fill=WARM)

    phone = device(raw, int(h * 0.62), 'iphone').rotate(-8, expand=True, resample=Image.BICUBIC)
    px, py = int(w * 0.66), int(h * 0.12)
    sh = Image.new('L', canvas.size, 0)
    sh.paste(phone.split()[3].point(lambda v: v * 120 // 255), (px + int(unit * 2), py + int(unit * 3)))
    canvas.paste((0, 0, 0), (0, 0), sh.filter(ImageFilter.GaussianBlur(unit * 3)))
    canvas.paste(phone, (px, py), phone)
    return canvas


def header(lang, size, safe, feed, compose):
    """App Store header or search art. Text stays inside Apple's safe box (x, y, w, h); phones fill the rest."""
    w, h = size
    sx, sy, sw, sh_ = safe
    canvas = gradient(size, RED, RED_DARK)
    d = ImageDraw.Draw(canvas)
    pw = int(min(h * 0.55, (w - sw) / 2 * 0.75))
    for raw, angle, cx in [(feed, 10, sx / 2), (compose, -10, sx + sw + (w - sx - sw) / 2)]:
        phone = device(raw, pw, 'iphone').rotate(angle, expand=True, resample=Image.BICUBIC)
        px, py = int(cx - phone.width / 2), int(h * 0.16)
        shade = Image.new('L', canvas.size, 0)
        shade.paste(phone.split()[3].point(lambda v: v * 110 // 255), (px, py + int(h * 0.03)))
        canvas.paste((0, 0, 0), (0, 0), shade.filter(ImageFilter.GaussianBlur(h * 0.03)))
        canvas.paste(phone, (px, py), phone)
    name, l1, l2 = (
        ('생각', '사람이 직접 쓴 생각만', 'AI 글도, 붙여넣기도 없이')
        if lang == 'ko' else ('Saenggak', 'Only thoughts typed by hand', 'No AI text. No pasting.')
    )
    cx = sx + sw / 2
    f1 = font(BOLD, sh_ * 0.2)
    while d.textlength(l1, font=f1) > sw * 0.96:
        f1 = font(BOLD, f1.size - 2)
    f2 = font(MEDIUM, f1.size * 0.62)
    icon_s = int(f1.size * 1.5)
    nf = font(BOLD, f1.size * 1.05)
    gap = f1.size * 0.55
    total = icon_s + gap + f1.size * 1.25 + f2.size * 1.3
    y = sy + (sh_ - total) / 2
    icon = Image.open('assets/icon/icon.png').convert('RGBA').resize((icon_s, icon_s), Image.LANCZOS)
    nw = icon_s + f1.size * 0.5 + d.textlength(name, font=nf)
    x0 = int(cx - nw / 2)
    canvas.paste(icon, (x0, int(y)), mask_rounded(icon.size, int(icon_s * 0.24)))
    d.text((x0 + icon_s + f1.size * 0.5, y + icon_s / 2), name, font=nf, fill=(255, 255, 255), anchor='lm')
    y += icon_s + gap
    d.text((cx, y), l1, font=f1, fill=(255, 255, 255), anchor='mt')
    d.text((cx, y + f1.size * 1.25), l2, font=f2, fill=WARM, anchor='mt')
    return canvas

def main():
    for lang, slides in SLIDES.items():
        for dev, (folder, size, kind) in DEVICES.items():
            for n, (name, (lines, sub, callout, side)) in enumerate(zip(NAMES, slides), start=1):
                raw = Image.open(RAW / f'{lang}-{dev}-{n}-{name}.png').convert('RGB')
                out = OUT / folder / lang / f'{n}-{name}.png'
                out.parent.mkdir(parents=True, exist_ok=True)
                slide(raw, size, kind, ORDER[n - 1], lines, sub, callout, side, {1: 0.6, 4: 0.7}.get(n, 0.42)).save(out, optimize=True)
        feed = Image.open(RAW / f'{lang}-iphone-2-feed.png').convert('RGB')
        for folder, size, fname in [
            ('google-play/feature-graphic', (1024, 500), f'{lang}.png'),
        ]:
            out = OUT / folder / fname
            out.parent.mkdir(parents=True, exist_ok=True)
            promo(lang, size, feed).save(out, optimize=True)
        compose = Image.open(RAW / f'{lang}-iphone-4-result.png').convert('RGB')
        # Apple's safe areas: https://developer.apple.com/app-store/asset-best-practices/
        for size, safe, fname in [
            ((5244, 2950), (1921, 660, 1402, 962), 'header-16x9'),
            ((3840, 1646), (1097, 493, 1646, 661), 'header-21x9'),
            ((3840, 2560), (836, 765, 2168, 1030), 'search-3x2'),
        ]:
            out = OUT / 'app-store' / 'header' / f'{lang}-{fname}-{size[0]}x{size[1]}.png'
            out.parent.mkdir(parents=True, exist_ok=True)
            header(lang, size, safe, feed, compose).save(out, optimize=True)
    icon = Image.open('assets/icon/icon.png').convert('RGBA').resize((512, 512), Image.LANCZOS)
    icon.save(OUT / 'google-play' / 'icon-512.png')


if __name__ == '__main__':
    main()
