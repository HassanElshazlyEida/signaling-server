# Voice Call (Flutter + WebRTC + WebSocket signaling)

Minimal mic-only voice call app. Each user gets a random 6-digit ID on
launch. Type another user's ID and hit Call to open a live voice connection.

## 1. Deploy the signaling server

```bash
cd signaling-server
npm install
npm start        # runs on ws://localhost:8080
```

Deploy it somewhere reachable from the internet (Render, Railway, Fly.io,
a $5 VPS, etc). Free tiers on Render/Railway work fine for this — it's just
relaying small JSON messages, not audio.

Once deployed you'll get a URL like `wss://your-app.onrender.com`.

## 2. Configure the Flutter app

Open `flutter_app/lib/main.dart` and set:

```dart
const String signalingServerUrl = 'wss://your-app.onrender.com';
```

Then scaffold the native Android project (this repo only ships the Dart
source + a manifest snippet, not the full generated Android folder):

```bash
cd flutter_app
flutter create .
flutter pub get
```

After `flutter create .` runs, merge the permissions from the provided
`android/app/src/main/AndroidManifest.xml` snippet into the one it generates
(mainly: RECORD_AUDIO, INTERNET, MODIFY_AUDIO_SETTINGS).

## 3. Run locally on two phones

```bash
flutter run
```

Install on two devices, note the ID shown on each screen, enter one phone's
ID into the other phone's "Enter ID to call" field, tap Call. First call
requires accepting the microphone permission prompt.

## 4. CI/CD (GitHub Actions)

`.github/workflows/flutter-ci.yml` builds a release APK automatically on
every push to `main` that touches `flutter_app/`. Grab the built APK from
the workflow run's "Artifacts" section, or extend the workflow to attach it
to a GitHub Release.

## Notes / limitations of this MVP

- **No TURN server** — calls only connect directly (STUN only, using
  Google's public STUN). Works fine on most home wifi/mobile networks, but
  users behind strict/symmetric NATs (some corporate or carrier networks)
  won't connect. Add a TURN server (e.g. self-hosted `coturn`) to the
  `_iceServers` map in `main.dart` to fix that.
- **No authentication** — anyone who knows a user's ID can call them. Fine
  for testing, not for production without adding auth.
- **1-to-1 calls only** — this signaling protocol is built for two-party
  calls, not group rooms.
- IDs are randomly generated per app launch (not persisted) — add local
  storage (e.g. `shared_preferences`) if you want a stable ID per install.
