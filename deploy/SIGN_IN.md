# Google and Apple sign-in

The app signs people in with Google and Apple through Cognito's sign-in pages
at `auth.saenggak.app`. The code is in place; each part turns on when its
settings in `backend/infra/site.ts` (`SIGN_IN`) are filled in.

A first Google or Apple sign-in is joined to the email account with the same
address (one is made if there is none), so a person keeps one profile however
they sign in. Cognito turns that very first try away once; the app tries again
on its own.

## 1. Sign-in address

1. ACM, us-east-1: request a public certificate for `auth.saenggak.app` with DNS
   validation. Add the CNAME it shows in Cloudflare (proxy off).
2. Once issued, put its ARN in `SIGN_IN.authCertificateArn` and deploy.
3. In Cloudflare, add a CNAME `auth` pointing at the stack output
   `AuthDomainTarget` (proxy off).

## 2. Google

Google Cloud console, a project for Saenggak:

1. OAuth consent screen: external, app name 생각, support email
   support@saenggak.app, app domain https://saenggak.app, privacy policy
   https://saenggak.app/privacy.html, terms https://saenggak.app/terms.html,
   authorized domain `saenggak.app`. Scopes: `openid`, `email`. Publish it.
2. Credentials > OAuth client ID > Web application.
   - Authorized JavaScript origin: `https://auth.saenggak.app`
   - Authorized redirect URI: `https://auth.saenggak.app/oauth2/idpresponse`
3. Put the client ID in `SIGN_IN.google.clientId`. Put the client secret in
   Secrets Manager (us-east-1) as plain text named `saenggak/google-client-secret`.

## 3. Apple

Apple Developer, Certificates, Identifiers & Profiles:

1. Identifiers > App IDs: `app.saenggak`, with Sign in with Apple ticked.
2. Identifiers > Services IDs: `app.saenggak.signin`, Sign in with Apple ticked,
   configured with primary App ID `app.saenggak`, domain `auth.saenggak.app`,
   return URL `https://auth.saenggak.app/oauth2/idpresponse`.
3. Keys: a new key with Sign in with Apple (primary App ID `app.saenggak`).
   Download the .p8 once.
4. Put the Team ID and Key ID in `SIGN_IN.apple`. Put the whole .p8 file's text
   in Secrets Manager (us-east-1) as plain text named `saenggak/apple-private-key`.

## 4. The app

The web app learns about the providers from `config.json`, which the deploy
writes. Store builds read `AUTH_DOMAIN` and `SIGN_IN_WITH` (for example
`google,apple`) from `app/config/production.json`.
