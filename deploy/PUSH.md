# Push alerts

Saenggak sends push alerts for three things:

- someone relates to (공감) your post
- someone follows you
- someone whose bell you turned on posts something new

Alerts reach Android, iOS and web browsers through Firebase Cloud
Messaging, which is free. Everything is in place in the code, but nothing is
sent until the steps below are done. Until then the app works as before: the
alerts stay in the notifications tab.

## How it works

- The app asks for permission once on a phone. On the web it asks only when
  the person taps **알림 켜기** in the notifications tab, because browsers want
  a tap first. The device's token is saved on the server (`push_tokens`), and
  removed again on sign-out.
- Every minute the `push` Lambda looks at what is new for each person with a
  device and sends **one alert per person and kind**. For example, ten 공감
  in a minute arrive as "하루님 외 9명이 공감했어요", not as ten alerts.
- People choose which kinds they get in Settings > 푸시 알림. Blocked people
  never trigger an alert.
- Tapping an alert opens the post, the person, or the notifications tab.

## One-time setup (about 20 minutes)

### 1. Create the Firebase project

1. At console.firebase.google.com, choose **Add project** and name it
   `saenggak`. Google Analytics is not needed; turn it off.
2. In **Project settings > General**, add three apps:
   - **Android**, package name `app.saenggak`
   - **iOS**, bundle ID `app.saenggak`
   - **Web**, nickname `saenggak web` (skip Firebase Hosting)

   You can skip the "download config file" and "add SDK" steps. The app takes
   the values from `app/config/production.json` instead.

### 2. Copy the app settings into `app/config/production.json`

These values are public identifiers, not secrets, so they can live in the
repository.

| Key | Where to find it |
| --- | --- |
| `FIREBASE_PROJECT_ID` | Project settings > General > Project ID |
| `FIREBASE_SENDER_ID` | Project settings > Cloud Messaging > Sender ID |
| `FIREBASE_ANDROID_API_KEY`, `FIREBASE_ANDROID_APP_ID` | the Android app's `google-services.json`: `current_key` and `mobilesdk_app_id` |
| `FIREBASE_IOS_API_KEY`, `FIREBASE_IOS_APP_ID` | the iOS app's `GoogleService-Info.plist`: `API_KEY` and `GOOGLE_APP_ID` |
| `FIREBASE_WEB_API_KEY`, `FIREBASE_WEB_APP_ID` | the web app's config snippet: `apiKey` and `appId` |
| `FIREBASE_VAPID_KEY` | Project settings > Cloud Messaging > Web Push certificates > **Generate key pair**, then copy the key |

Each platform works on its own once its keys are filled in. The web app also
needs the VAPID key.

### 3. Connect Apple's push service (for iPhones)

1. At developer.apple.com, go to **Certificates, Identifiers & Profiles >
   Keys**, then **+**. Tick **Apple Push Notifications service (APNs)**,
   continue, and download the `.p8` file. Note the **Key ID**. You can
   download the file only once.
2. In Firebase, go to **Project settings > Cloud Messaging > Apple app
   configuration**. Upload the `.p8` under **APNs authentication key**, with
   the Key ID and your Team ID.

3. In **Identifiers**, open `app.saenggak` and check that **Push
   Notifications** is ticked. Save if you changed it.

The iOS build now carries the push entitlement. The automatic signing in the
Mobile builds workflow should turn on Push Notifications for the App ID by
itself. If the iOS build fails at signing with a push or `aps-environment`
error, do step 3 and run the build again.

### 4. Let the server send

1. In Firebase, go to **Project settings > Service accounts > Generate new
   private key**. This downloads a JSON file. Keep it private: it can send
   alerts as Saenggak.
2. In the AWS Secrets Manager console, open the secret that the deploy
   summary names as *Firebase service account for push alerts*
   (`FirebaseServiceAccount…`). Choose **Retrieve secret value > Edit**,
   switch to **Plaintext**, and paste the whole JSON file over the
   placeholder.

You don't need to redeploy for this step. The sender picks up the key within
a few minutes.

### 5. Ship it

- **Web**: push the `production.json` change to `main`. The deploy writes the
  web settings into `config.json` and `firebase-config.js`.
- **Phones**: run Actions > Mobile builds. Alerts work in TestFlight and Play
  internal testing builds, and in store releases built after this change.

## Checking it works

1. Sign in on a phone and allow alerts.
2. From another account, relate to one of that person's posts.
3. The alert should arrive within about a minute.

The `push` Lambda's log shows each run's
`{ batches, sent, failed, removed }`. `removed` counts devices that
uninstalled the app; their tokens are deleted.

## Cost

The sender runs about 43,000 times a month, which is within Lambda's free
tier. Firebase Cloud Messaging is free.
