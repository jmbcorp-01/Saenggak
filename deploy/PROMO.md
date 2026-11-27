# Growth without ad spend: running the promo agent

The promo agent brings people to Saenggak through Saenggak's own Instagram
and Threads accounts, public post pages and invite links. It never posts a
writer's words unless the writer turned on sharing (Settings > 공유와 초대 >
생각 공식 계정에 내 글 소개 허용), and never without an admin's approval.

## What runs on its own

| When (Korea time) | Job | What it does |
| --- | --- | --- |
| Every day 07:00 | `pick` | Takes down items whose writer turned sharing off or deleted the post, then picks up to 5 posts from the last 3 days (one per writer, well received, never reported, a writer at most once in 14 days) and drafts a caption for each with Claude. |
| Every hour at :05 | `publish` | Posts approved items whose time has come (21:00 by default) to every connected account. A channel already posted is never posted again. |
| Monday 06:00 | `questions` | Drafts daily questions for the next 14 days. None show until an admin approves them. |
| Sunday 05:00 | `tokens` | Refreshes the long-lived Instagram and Threads tokens before they expire. |

## The admin's daily routine (about 5 minutes)

In the app: Settings > 관리자 페이지.

1. **홍보 > 승인 대기**: read each picked post, edit the caption if needed, then
   승인 (approve) or 건너뛰기 (skip). Approving draws the card image and
   schedules the post for 21:00 Korea time.
2. **홍보 > 지난 것**: an item marked 직접 지워야 함 was posted and its writer
   has since turned sharing off or deleted it. Delete it on Instagram and
   Threads by hand, then tap 지웠어요. Neither API lets the agent delete it.
3. **오늘의 질문**, once a week: approve or edit the drafts.
4. **대시보드** and **유입 링크**: see sign-ups, D1/D7/D30 return rates and
   which channel brought people who stayed.

Without connected accounts the agent still picks and an admin still
approves; copy the caption and card address from 예약 and post by hand,
then tap 직접 올렸어요.

## Connecting Instagram and Threads (one time)

Both need a Meta developer app. Use Saenggak's own business accounts, never a
person's.

1. Make the Instagram account a **professional (business or creator)
   account**, and create the Threads profile from it.
2. At developers.facebook.com, create an app of type **Business**, and add
   the **Instagram API with Instagram login** and **Threads API** use cases.
3. Ask for these permissions:
   - Instagram: `instagram_business_basic`, `instagram_business_content_publish`
   - Threads: `threads_basic`, `threads_content_publish`

   While the app is in development mode it can post to accounts added as
   testers, which is enough for Saenggak's own accounts.
4. Generate a **long-lived token** for each (Instagram: in the app dashboard
   under API setup with Instagram login; Threads: through the Threads API
   token tool or the OAuth flow, then exchange it for a long-lived token).
   Note the user id each one returns.
5. In the AWS Secrets Manager console, open the secret named in the deploy
   summary as *Instagram and Threads tokens* (`SocialTokens…`), choose
   **Retrieve secret value > Edit**, and replace the placeholders:

   ```json
   {
     "threadsUserId": "…",
     "threadsToken": "…",
     "instagramUserId": "…",
     "instagramToken": "…"
   }
   ```

   Leave a pair as `REPLACE` to skip that channel. No redeploy is needed; the
   홍보 tab shows which accounts are connected.

The `tokens` job refreshes both tokens every week, so they do not expire as
long as it keeps running. If a token does expire, paste a new one the same
way.

## Links and the app stores

- Every invite link is `https://saenggak.app/i/{code}`. It records the click
  (only the code and the kind of device) and offers the App Store, Google
  Play and the web app. The web button carries the code (`/?c=CODE`), and the
  new profile screen fills it in.
- Set the GitHub Actions variable `IOS_APP_URL` to the App Store link once
  the app is listed, and `ANDROID_APP_URL` if the Play link differs from
  `https://play.google.com/store/apps/details?id=app.saenggak`. Then rerun the
  deploy.
- People installing from a store type the invite code on the profile screen
  themselves; the store does not pass it on.
- Public post pages (`/p/{id}`) exist only for posts whose writer allows
  sharing, and `/sitemap-posts.xml` lists them for search engines.

## Cost

The agent adds a few Lambda runs a day, a handful of short Claude calls and
one secret: about $5–10 a month in total at launch traffic.
