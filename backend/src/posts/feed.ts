import type { FeedPost, Repository, Translator } from '../services/ports.js';

export const SUPPORTED_LANGS = ['ko', 'en'] as const;
export type Lang = (typeof SUPPORTED_LANGS)[number];

export function isLang(v: unknown): v is Lang {
  return typeof v === 'string' && (SUPPORTED_LANGS as readonly string[]).includes(v);
}

export interface TranslatedPost extends FeedPost {
  /** Present when the post was written in another language than the viewer's. */
  translation: { lang: Lang; body: string } | null;
}

/**
 * Adds a translation to every post written in another language. Translations
 * are cached per post and language, so each post is translated once. A failed
 * translation leaves the original text alone instead of failing the feed.
 */
export async function translateFeed(
  deps: { repo: Repository; translator: Translator },
  posts: FeedPost[],
  viewerLang: Lang,
): Promise<TranslatedPost[]> {
  return Promise.all(
    posts.map(async (post): Promise<TranslatedPost> => {
      if (post.lang === viewerLang) return { ...post, translation: null };
      try {
        let body = await deps.repo.cachedTranslation(post.id, viewerLang);
        if (body === null) {
          body = await deps.translator.translate(post.body, post.lang, viewerLang);
          await deps.repo.saveTranslation(post.id, viewerLang, body);
        }
        return { ...post, translation: { lang: viewerLang, body } };
      } catch {
        return { ...post, translation: null };
      }
    }),
  );
}
