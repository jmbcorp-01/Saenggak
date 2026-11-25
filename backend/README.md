# Saenggak backend (AWS)

TypeScript Lambdas behind an HTTP API, deployed with CDK.

| Route | What it does |
|---|---|
| `POST /posts` | Checks length and hand typing, runs the content filter, saves the post, then returns how many people had a similar thought (shown only at 3 or more) and up to 3 phrases this post used first. |
| `PATCH /posts/{id}` | Edits your post until its first 공감, with the same checks. First-used phrases are worked out again from the new text. A blocked edit keeps the old text and counts as a blocked post. |
| `DELETE /posts/{id}` | Deletes your post with its 공감, translations and first-used phrases. |
| `GET /feed?tab=all\|following&author=&lang=ko\|en&before=` | Newest posts, with a cached Amazon Translate translation for posts in the other language. |
| `POST /posts/{id}/empathy` | Toggles 공감. Not allowed on your own post. |
| `GET /me`, `PUT /me` | Your profile with writing days and follow status. `PUT` creates it after sign-up (handle, name, bio, language, time zone); a changed name or bio goes through the content filter. |
| `GET /users/{id}` | Someone's profile, with whether you follow them. |
| `PUT /users/{id}/follow`, `DELETE /users/{id}/follow` | Follow and unfollow. Both people need follow permission. |

Two Lambdas serve these: `write` (posting, editing and `PUT /me`, which call Bedrock) and `api` (everything else).
Every route needs a Cognito access token; API Gateway checks it.

Rules the server enforces on its own, whatever the app sends:

- The writing day is today in the time zone saved on the profile, so writing days cannot be made up. Posting without a profile returns 409 `profile_required`.
- Each person gets 20 writes an hour (posts, edits and name or bio changes), counted before the content filter is called. Over that returns 429 `rate_limited`.
- If the content filter is down, the write is refused with 503 `filter_unavailable`; nothing is let through unchecked.
- A post the filter declines to judge is kept for human review and does not count toward losing follow permission.
- Any other failure returns 500 `{"error":"internal"}` and is logged.

## Pieces

- `src/rules`: the same rules as the app (length, typing check, follow permission, phrases, similarity). The server never trusts the app's numbers and recomputes typing time.
- `src/posts`: the posting and feed flows, written against the interfaces in `src/services/ports.ts`.
- `src/services`: AWS implementations.
  - Aurora PostgreSQL through the RDS Data API.
  - Titan Text Embeddings v2 for similar thoughts.
  - Claude on Amazon Bedrock for the content filter. If the filter declines to review a post, the post is held as blocked for human review.
  - Amazon Translate.
- `src/db/schema.sql`: tables, including `pgvector` embeddings and the first-use phrase table.
- `infra/stack.ts`: Cognito, Aurora Serverless v2 (Data API on, isolated subnets), two Lambdas, the HTTP API with throttling.

## Commands

```sh
npm install
npm run build     # type check
npm test          # rules, flows, handlers, and a CDK synth check

# Also run the repository's SQL against Postgres 16+ with pgvector.
# Each run creates its own schema; nothing existing is changed.
TEST_DATABASE_URL=postgresql://localhost/saenggak_test npm test
npm run deploy    # needs AWS credentials
```

After the first deploy, apply `src/db/schema.sql` once, for example with the RDS query editor or `aws rds-data execute-statement`. Enable model access for Titan Text Embeddings v2 and Claude in the Bedrock console of the deploy region.

## Before launch

- CloudFront and WAF in front of the API (bot control, rate rules) for scraping.
- Narrow the `bedrock-mantle:*` permission to the exact action and model.
- Endpoints still to add: profile photo upload, report, block a user, notifications.
