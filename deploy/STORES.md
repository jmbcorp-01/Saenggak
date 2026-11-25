# Publishing to the App Store and Google Play

The **Mobile builds** workflow (Actions > Mobile builds > Run workflow) builds
both apps with the production settings in `app/config/production.json`. It
uploads to TestFlight and to Play's internal testing track once the secrets
below are set. Until then it still builds, and the Android bundle can be
downloaded from the run.

App ids: **`app.saenggak`** on both stores. App name: **생각** (English: Saenggak).

## Apple (App Store Connect)

1. **Create the app.** In App Store Connect, go to Apps > + > New App. Choose iOS, name 생각,
   primary language Korean, bundle ID `app.saenggak` (register it first under
   Certificates, Identifiers & Profiles > Identifiers if it is not listed), and SKU `saenggak`.
2. **API key for uploads.** In App Store Connect, go to Users and Access > Integrations >
   App Store Connect API > Team Keys > +, with access **App Manager**. Download the
   `.p8` file (it can be downloaded only once) and note the Key ID and the Issuer ID.
3. **In GitHub**, go to Settings > Secrets and variables > Actions:
   - Secrets: `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
     `APP_STORE_CONNECT_KEY` (the whole text of the `.p8` file).
   - Variables: `APPLE_TEAM_ID`, the 10-character Team ID from
     developer.apple.com > Account > Membership details.
4. Run **Mobile builds**. The build shows up in TestFlight after Apple's
   processing (about 10 to 30 minutes).

## Google Play

1. **Create the app.** In Play Console, go to Create app, name 생각, choose App and Free.
2. **Upload key** (once). Run Mobile builds with **"Only create a new Android
   upload key"** ticked. Download the `android-upload-key-...` artifact from the run.
   Add its two files as the secrets `ANDROID_KEYSTORE_BASE64` and
   `ANDROID_KEYSTORE_PASSWORD`, then delete the artifact. Keep a copy of both values
   somewhere safe, such as a password manager.
3. **First bundle by hand.** Play accepts uploads from the API only after the
   first one. Run Mobile builds, download `android-app-bundle`, and upload
   `app-release.aab` in Play Console > Testing > Internal testing > Create new release.
   Accept Play App Signing when asked.
4. **Service account for later uploads.** In Google Cloud console, create a
   service account and a JSON key for it. In Play Console > Users and permissions,
   invite its email with release permissions for this app. Put the JSON as the
   secret `PLAY_SERVICE_ACCOUNT_JSON`. Later runs then upload to internal
   testing as a draft.

## Store listing checklist

- Privacy policy: `https://saenggak.app/privacy.html`. Support: `https://saenggak.app/support.html`.
- Account deletion: in the app under Profile > Settings > 계정 삭제. On the web, use
  the same URL as support.
- Content: user-generated, with reports, blocks and moderation. The age rating
  questionnaire should say so. The app is for ages 14 and over.
- Data safety (Play) and App Privacy (Apple): email, name, photos (profile), user content (posts),
  and identifiers (user id). Data is linked to the user, not used for tracking,
  and can be deleted.
- Review notes: give the reviewers a test account (email and password) with a profile.
  Mention that posts must be typed by hand: paste is blocked by design.
