import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from 'aws-lambda';
import { isCode, platformOf } from '../growth/codes.js';
import { invitePage, langFrom, missingPage, postPage, sitemap, type StoreLinks } from '../growth/pages.js';
import type { GrowthRepository } from '../services/growthPorts.js';
import { AuroraGrowthRepository } from '../services/growthRepository.js';
import { isUuid } from './http.js';

type Deps = { growth: GrowthRepository; site: string; stores: StoreLinks };

/** Posts in the sitemap; search engines read at most 50,000 a file. */
const SITEMAP_SIZE = 5000;

const html = (statusCode: number, body: string, maxAge: number): APIGatewayProxyResultV2 => ({
  statusCode,
  headers: {
    'content-type': 'text/html; charset=utf-8',
    'cache-control': maxAge > 0 ? `public, max-age=${maxAge}` : 'no-store',
  },
  body,
});

/**
 * Pages for people who are not signed in, at the site's own addresses
 * (CloudFront sends /i/*, /p/* and /sitemap-posts.xml here under /public):
 *   GET /public/i/{code}             what Saenggak is, with the code kept for sign-up
 *   GET /public/p/{id}               one shareable post
 *   GET /public/sitemap-posts.xml    every shareable post, for search engines
 */
export const publicHandler = (deps: Deps) => async (event: APIGatewayProxyEventV2): Promise<APIGatewayProxyResultV2> => {
  const secret = process.env.ORIGIN_SECRET;
  if (secret && event.headers?.['x-origin-verify'] !== secret) return { statusCode: 403 };
  const lang = langFrom(event.headers?.['accept-language']);
  const id = event.pathParameters?.id ?? event.pathParameters?.code;
  try {
    switch (event.routeKey) {
      case 'GET /public/i/{code}': {
        if (!isCode(id)) return html(404, missingPage({ lang, site: deps.site, stores: deps.stores }), 0);
        const target = await deps.growth.resolveCode(id);
        if (!target) return html(404, missingPage({ lang, site: deps.site, stores: deps.stores }), 0);
        await deps.growth.recordClick(target.code, platformOf(event.headers?.['user-agent']));
        // Not cached: every visit is a click to count.
        return html(200, invitePage({ lang, site: deps.site, code: target.code, stores: deps.stores }), 0);
      }

      case 'GET /public/p/{id}': {
        const post = isUuid(id) ? await deps.growth.publicPost(id) : null;
        // A minute at the edge: a writer who withdraws consent is off the page soon after.
        if (!post) return html(404, missingPage({ lang, site: deps.site, stores: deps.stores }), 60);
        return html(200, postPage({ site: deps.site, post, code: 'web-post', stores: deps.stores }), 60);
      }

      case 'GET /public/sitemap-posts.xml':
        return {
          statusCode: 200,
          headers: { 'content-type': 'application/xml; charset=utf-8', 'cache-control': 'public, max-age=3600' },
          body: sitemap(deps.site, await deps.growth.publicPostIds(SITEMAP_SIZE)),
        };
    }
    return { statusCode: 404 };
  } catch (e) {
    console.error('public page failed', event.routeKey, e);
    return html(500, missingPage({ lang, site: deps.site, stores: deps.stores }), 0);
  }
};

let live: Deps | undefined;
export const handler = (event: APIGatewayProxyEventV2) =>
  publicHandler(
    (live ??= {
      growth: new AuroraGrowthRepository(),
      site: process.env.SITE_URL ?? '',
      stores: { ios: process.env.IOS_APP_URL || undefined, android: process.env.ANDROID_APP_URL || undefined },
    }),
  )(event);
