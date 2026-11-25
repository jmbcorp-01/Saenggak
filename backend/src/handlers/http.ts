import type { APIGatewayProxyEventV2WithJWTAuthorizer, APIGatewayProxyResultV2 } from 'aws-lambda';

export type Event = APIGatewayProxyEventV2WithJWTAuthorizer;

export function json(statusCode: number, body: unknown): APIGatewayProxyResultV2 {
  if (statusCode === 204) return { statusCode, headers: { 'cache-control': 'no-store' } };
  return {
    statusCode,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
    body: JSON.stringify(body),
  };
}

/** The Cognito user id. API Gateway has already verified the token. */
export function userId(event: Event): string {
  const sub = event.requestContext.authorizer.jwt.claims.sub;
  if (typeof sub !== 'string' || sub.length === 0) throw new Error('missing sub claim');
  return sub;
}

export function parseBody(event: Event): Record<string, unknown> | null {
  if (!event.body) return null;
  try {
    const raw = event.isBase64Encoded ? Buffer.from(event.body, 'base64').toString('utf8') : event.body;
    const parsed: unknown = JSON.parse(raw);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
      ? (parsed as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function isUuid(v: unknown): v is string {
  return typeof v === 'string' && UUID.test(v);
}
