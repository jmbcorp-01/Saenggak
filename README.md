# Saenggak (생각)

A place for thoughts people typed themselves. No AI writing, no pasting, no
photos except a profile picture. Web, iOS and Android from one Flutter app.

## Layout

| Path | What it is |
| --- | --- |
| `app/` | Flutter app (web, iOS, Android) |
| `app/lib/core/` | Post rules: weighted length, typing session, paste blocking, human-typing check |
| `app/lib/screens/` | Start, feed, compose and profile screens |
| `app/lib/theme/` | Colors and type from the approved design |

The AWS backend (Cognito, API Gateway + Lambda, Aurora PostgreSQL, Bedrock
content filter, Amazon Translate) comes in a later change. Until then the app
runs on in-memory sample posts.

## Rules the app enforces

- **Length** is counted in weighted units: Hangul, kana and Han characters
  count 2, everything else 1. A post must be 80 to 400 units (about 40 to 200
  Korean characters, or 15 to 70 English words).
- **Hand typing only.** Paste is removed from the text menu and the paste
  shortcut, and any single change that inserts more than 4 characters is
  rejected unless voice input is on. Suggestions and autocorrect are off.
- **Typing session.** Each accepted change is recorded as a timestamp and
  character counts (never the keys). The post shows the active typing time;
  pauses over 30 seconds are left out.
- **Human check.** Before posting, the session is checked for too few changes
  for the length, speed above 15 characters a second, and key gaps too even to
  be a person. The server will repeat this check.

## Run

```sh
cd app
flutter pub get
flutter test
flutter run -d chrome
```
