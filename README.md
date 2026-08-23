# Voice Call (Flutter + WebRTC + Socket.IO signaling)

Minimal mic-only voice call app. Each user gets a random 6-digit ID on
launch. Type another user's ID and hit Call to open a live voice connection.

Signaling transport is **Socket.IO** rather than a raw WebSocket. It tries a
real WebSocket first and upgrades to it automatically wherever the network
path allows one, but falls back to plain HTTP long-polling when it doesn't —
which matters if you're deploying behind a reverse proxy that blocks the
WebSocket `Upgrade` handshake (a common limitation on shared cPanel/LiteSpeed
hosting; see "Deployment notes" below). The message protocol itself
(`register` / `offer` / `answer` / `candidate` / `hangup`) is unchanged from
a raw-WebSocket setup — only the transport underneath is different.

## 1. Deploy the signaling server

```bash
cd signaling-server
npm install
npm start        # runs on http://localhost:8080, Socket.IO path /socket/socket.io/
```

Deploy it somewhere reachable from the internet (Render, Railway, Fly.io,
a $5 VPS, cPanel's Node.js Selector, etc). Free tiers on Render/Railway work
fine for this — it's just relaying small JSON messages, not audio.

Once deployed you'll have a base URL, e.g. `https://your-app.onrender.com`
or, for a cPanel Node.js Selector app mounted under a path,
`https://yourdomain.com/socket`.

### Deployment notes (cPanel / LiteSpeed / shared hosting)

If you're hosting on cPanel with a Node.js Selector app, LiteSpeed's
auto-generated reverse proxy for that app often does **not** pass the
WebSocket `Upgrade` header through — plain HTTP works, but a raw WebSocket
handshake just hangs and times out. Fixing that properly requires root/WHM
access to add a `ws://` `ProxyPass` directive to the domain's Apache-style
vhost config (see LiteSpeed's
[WebSocket Proxy docs](https://docs.litespeedtech.com/lsws/cp/cpanel/websocket-proxy/)),
which most shared-hosting accounts don't have.

Socket.IO's automatic long-polling fallback sidesteps this entirely — no
server config changes needed. This has been verified working end-to-end
(register + offer/answer/candidate relay) over the polling transport against
a cPanel Node.js Selector app with WebSocket upgrades blocked.

If your Node.js Selector app is mounted at a URL path (e.g. `/socket`
instead of its own subdomain), set the Socket.IO server's `path` option to
include that prefix — e.g. `path: '/socket/socket.io/'` — and configure the
Flutter client's `signalingSocketPath` to match exactly.

## 2. Configure the Flutter app

Open `flutter_app/lib/main.dart` and set:

```dart
const String signalingServerUrl = 'https://your-app.onrender.com'; // base URL, no path
const String signalingSocketPath = '/socket.io/'; // or '/socket/socket.io/' if mounted under a path
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

**Verified:** tested end-to-end on two physical Android devices on
different networks — one phone calls the other's ID, the call connects,
and audio flows both ways. Confirms both the Socket.IO signaling relay
(deployed on the cPanel/LiteSpeed host, see "Deployment notes" above) and
STUN-based NAT traversal work across separate networks, not just on a
shared LAN.

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
- Signaling now rides on Socket.IO (WebSocket-with-polling-fallback) instead
  of a raw WebSocket — see "Deployment notes" above for why.
