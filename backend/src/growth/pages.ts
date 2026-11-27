import type { PublicPost } from '../services/growthPorts.js';

/**
 * The few pages served to people who are not signed in: the invite landing
 * page behind every shared link, one page per shareable post, and their
 * sitemap. Plain HTML with the site's colours; no script.
 */

export type PageLang = 'ko' | 'en';

const esc = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

export function langFrom(acceptLanguage: string | undefined): PageLang {
  return /^\s*ko\b/i.test(acceptLanguage ?? '') ? 'ko' : 'en';
}

export interface StoreLinks {
  ios?: string;
  android?: string;
}

const STYLE = `:root{--ink:#151515;--muted:#6b6b6b;--line:#ebebeb;--bg:#fff;--accent:#b8361f}
@media (prefers-color-scheme:dark){:root{--ink:#ececec;--muted:#a3a3a3;--line:#2a2a2a;--bg:#121212;--accent:#f08a74}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:17px/1.75 "Noto Sans KR","Apple SD Gothic Neo",system-ui,sans-serif}
main{max-width:560px;margin:0 auto;padding:56px 20px 72px}
.brand{font-weight:700;letter-spacing:-.5px;font-size:20px;color:var(--ink);text-decoration:none}
.thought{margin:40px 0 12px;font-size:21px;line-height:1.8;white-space:pre-wrap;word-break:keep-all}
.meta{color:var(--muted);font-size:14px}
.lead{margin:36px 0 8px;font-size:22px;font-weight:700;letter-spacing:-.4px;word-break:keep-all}
.btns{display:flex;flex-direction:column;gap:10px;margin-top:28px}
.btn{display:block;text-align:center;padding:14px 16px;border-radius:12px;border:1px solid var(--line);color:var(--ink);text-decoration:none;font-weight:600}
.btn.primary{background:var(--accent);border-color:var(--accent);color:#fff}
.code{margin-top:28px;padding:14px 16px;border:1px dashed var(--line);border-radius:12px;font-size:15px}
.code b{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:18px;letter-spacing:1px}
footer{margin-top:56px;color:var(--muted);font-size:13px}footer a{color:var(--muted)}`;

function page(o: { lang: PageLang; title: string; description: string; url: string; body: string; image?: string }) {
  const image = o.image ? `<meta property="og:image" content="${esc(o.image)}">` : '';
  return `<!doctype html><html lang="${o.lang}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(o.title)}</title><meta name="description" content="${esc(o.description)}">
<link rel="canonical" href="${esc(o.url)}"><link rel="icon" href="/favicon.png">
<meta property="og:type" content="article"><meta property="og:site_name" content="생각 Saenggak">
<meta property="og:title" content="${esc(o.title)}"><meta property="og:description" content="${esc(o.description)}">
<meta property="og:url" content="${esc(o.url)}">${image}<meta name="twitter:card" content="summary">
<style>${STYLE}</style></head><body><main>${o.body}</main></body></html>`;
}

const T = {
  ko: {
    lead: '사람이 직접 쓴 생각만 모이는 곳',
    sub: 'AI 글도, 붙여넣기도 없습니다. 하루 한 줄, 내 손으로 쓴 생각을 남겨 보세요.',
    web: '웹에서 시작하기',
    ios: 'App Store에서 받기',
    android: 'Google Play에서 받기',
    code: (c: string) => `앱에서 가입할 때 초대 코드 <b>${esc(c)}</b> 를 넣어 주세요.`,
    by: (name: string | null) => (name ? `${name}님의 생각` : '어느 생각러의 생각'),
    typed: (min: number) => `직접 타이핑 ${min}분`,
    empathy: (n: number) => `공감 ${n}`,
    cta: '나도 생각 쓰기',
    privacy: '개인정보 처리방침',
    missing: '이 생각은 더 이상 볼 수 없습니다.',
  },
  en: {
    lead: 'Only thoughts people typed themselves',
    sub: 'No AI writing, no pasting. Leave one thought a day, in your own words.',
    web: 'Start on the web',
    ios: 'Get it on the App Store',
    android: 'Get it on Google Play',
    code: (c: string) => `When you sign up in the app, enter invite code <b>${esc(c)}</b>.`,
    by: (name: string | null) => (name ? `A thought by ${name}` : 'A thought from Saenggak'),
    typed: (min: number) => `Typed by hand in ${min} min`,
    empathy: (n: number) => `${n} 공감`,
    cta: 'Write your own',
    privacy: 'Privacy',
    missing: 'This thought is no longer available.',
  },
} as const;

function startButtons(lang: PageLang, site: string, code: string | null, stores: StoreLinks) {
  const t = T[lang];
  const web = `${site}/${code ? `?c=${encodeURIComponent(code)}` : ''}`;
  return `<div class="btns">
<a class="btn primary" href="${esc(web)}">${t.web}</a>
${stores.ios ? `<a class="btn" href="${esc(stores.ios)}">${t.ios}</a>` : ''}
${stores.android ? `<a class="btn" href="${esc(stores.android)}">${t.android}</a>` : ''}
</div>${code && (stores.ios || stores.android) ? `<p class="code">${t.code(code)}</p>` : ''}`;
}

const footer = (lang: PageLang, site: string) =>
  `<footer>© 생각 Saenggak · <a href="${esc(site)}${lang === 'en' ? '/en' : ''}/privacy.html">${T[lang].privacy}</a></footer>`;

/** Behind every shared link: what Saenggak is, and the ways in, keeping the code. */
export function invitePage(o: { lang: PageLang; site: string; code: string; stores: StoreLinks }) {
  const t = T[o.lang];
  return page({
    lang: o.lang,
    title: o.lang === 'ko' ? '생각 — 직접 쓴 생각만' : 'Saenggak — only hand-typed thoughts',
    description: t.sub,
    url: `${o.site}/i/${encodeURIComponent(o.code)}`,
    body: `<a class="brand" href="${esc(o.site)}">생각</a><p class="lead">${t.lead}</p><p class="meta">${t.sub}</p>
${startButtons(o.lang, o.site, o.code, o.stores)}${footer(o.lang, o.site)}`,
  });
}

/** A shareable post on its own page, for search and for links shared outside the app. */
export function postPage(o: { site: string; post: PublicPost; code: string; stores: StoreLinks }) {
  const lang: PageLang = o.post.lang === 'ko' ? 'ko' : 'en';
  const t = T[lang];
  const p = o.post;
  const minutes = Math.max(1, Math.round(p.typingMs / 60000));
  const excerpt = [...p.body].slice(0, 80).join('');
  return page({
    lang,
    title: `${t.by(p.authorName)} · 생각`,
    description: excerpt,
    url: `${o.site}/p/${p.id}`,
    body: `<a class="brand" href="${esc(o.site)}">생각</a>
<p class="thought">${esc(p.body)}</p>
<p class="meta">${esc(t.by(p.authorName))} · ${t.typed(minutes)} · ${t.empathy(p.empathyCount)} · ${esc(p.createdAt.slice(0, 10))}</p>
<p class="lead">${t.cta}</p><p class="meta">${t.sub}</p>
${startButtons(lang, o.site, o.code, o.stores)}${footer(lang, o.site)}`,
  });
}

export function missingPage(o: { lang: PageLang; site: string; stores: StoreLinks }) {
  const t = T[o.lang];
  return page({
    lang: o.lang,
    title: '생각',
    description: t.sub,
    url: o.site,
    body: `<a class="brand" href="${esc(o.site)}">생각</a><p class="lead">${t.missing}</p><p class="meta">${t.sub}</p>
${startButtons(o.lang, o.site, null, o.stores)}${footer(o.lang, o.site)}`,
  });
}

export function sitemap(site: string, posts: { id: string; at: string }[]): string {
  const urls = posts
    .map((p) => `<url><loc>${esc(`${site}/p/${p.id}`)}</loc><lastmod>${esc(p.at.slice(0, 10))}</lastmod></url>`)
    .join('');
  return `<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${urls}</urlset>`;
}

/** The text of a Threads post: the thought as written, who wrote it, the caption and the link. */
export function threadsText(o: { body: string; lang: string; authorName: string | null; caption: string; link: string }) {
  const t = T[o.lang === 'ko' ? 'ko' : 'en'];
  const by = t.by(o.authorName);
  const text = `${o.body}\n\n— ${by}\n\n${o.caption}\n${o.link}`;
  // Threads allows 500 characters; the caption gives way first.
  if ([...text].length <= 500) return text;
  return `${o.body}\n\n— ${by}\n${o.link}`;
}

/** An Instagram caption: links there are not clickable, so it points to the profile link. */
export function instagramCaption(o: { lang: string; authorName: string | null; caption: string }) {
  const ko = o.lang === 'ko';
  const by = T[ko ? 'ko' : 'en'].by(o.authorName);
  return `${by}\n\n${o.caption}\n\n${ko ? '프로필 링크에서 나도 써 보기' : 'Write your own: link in profile'}`;
}
