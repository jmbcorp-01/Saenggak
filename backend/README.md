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
| `PUT /me/photo` | `{ jpeg: base64 }`, a square JPEG of at most 2 MB taken with the app's camera. Amazon Rekognition must find exactly one clear, frontal face and no explicit or violent content; otherwise `422 { error: 'photo_refused', problem }` with `no_face`, `many_faces`, `unclear` or `inappropriate`. Counts toward the hourly write limit. |
| `GET /users/{id}` | Someone's profile, with whether you follow them. |
| `PUT /users/{id}/follow`, `DELETE /users/{id}/follow` | Follow and unfollow. Both people need follow permission. |

Two Lambdas serve these: `write` (posting, editing, `PUT /me` and `PUT /me/photo`, which call the content filter or Rekognition) and `api` (everything else).
Every route needs a Cognito access token; API Gateway checks it.

Rules the server enforces on its own, whatever the app sends:

- The writing day is today in the time zone saved on the profile, so writing days cannot be made up. Posting without a profile returns 409 `profile_required`.
- Each person gets 20 writes an hour (posts, edits and name or bio changes), counted before the content filter is called. Over that returns 429 `rate_limited`.
- If the content filter is down, the write is refused with 503 `filter_unavailable`; nothing is let through unchecked.
- A post the filter declines to judge is kept for human review and does not count toward losing follow permission.
- First-used phrases are recorded from the first post but returned only once the app holds 10,000 published posts (`FIRST_PHRASES_MIN_POSTS`). Before that almost every phrase is new.
- Any other failure returns 500 `{"error":"internal"}` and is logged.

## Pieces

- `src/rules`: the same rules as the app (length, typing check, follow permission, phrases, similarity). The server never trusts the app's numbers and recomputes typing time.
- `src/posts`: the posting and feed flows, written against the interfaces in `src/services/ports.ts`.
- `src/services`: AWS implementations.
  - Aurora PostgreSQL through the RDS Data API.
  - Titan Text Embeddings v2 for similar thoughts.
  - Claude on Amazon Bedrock for the content filter. If the filter declines to review a post, the post is held as blocked for human review.
  - Amazon Translate.
  - Amazon Rekognition for profile photos, stored in a private S3 bucket and served by CloudFront at `/photos/*`.
- `src/db/migrations/`: the schema as numbered SQL files, applied after each deploy by the `migrate` Lambda.
- `infra/stack.ts`: Cognito, Aurora Serverless v2 (Data API on, isolated subnets), the write, api and migrate Lambdas, the HTTP API with throttling, and the web app on S3 and CloudFront.

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

Deploys run from GitHub Actions; see `../deploy/README.md`. The schema is applied automatically after each deploy.

## Before launch

- CloudFront and WAF in front of the API (bot control, rate rules) for scraping.
- Narrow the `bedrock-mantle:*` permission to the exact action and model.
- Endpoints still to add: report, block a user, notifications.
- Face Liveness (Rekognition) in the iOS and Android apps, so a photo of a screen or a printout can't pass as a live face.
