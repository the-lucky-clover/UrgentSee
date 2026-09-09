# UrgentSee ⚡

**Cross-platform urgent messaging that bypasses Do Not Disturb.**

Send time-critical messages that literally override silent mode on your contacts' phones. Think "Find My" meets iMessage, but the notification *will* be seen.

---

## What Is This?

UrgentSee is a 3-part system:

| Piece | Tech | What It Does |
|-------|------|--------------|
| `urgentsee-edge/` | TypeScript (Cloudflare Workers) | Backend API, push dispatch, rate limiting |
| `UrgentSee/` | SwiftUI (iOS 16.2+) | iPhone app + Live Activity lock screen widget |
| `android/` | Kotlin + Jetpack Compose | Android app + home screen widget |

Messages are **end-to-end encrypted** (X25519 key exchange + ChaCha20-Poly1305). The server never sees plaintext. Both platforms speak the same wire format, so iOS users can message Android users and vice versa.

---

## The Core Flow

```
1. Alice opens app → generates X25519 key pair → registers with backend
2. Alice sends to Bob → app encrypts with Bob's public key → hits /v1/rush/dispatch
3. Backend checks trust circle + rate limit → sends APNs/FCM push → Bob's phone screams
4. Bob unlocks phone → app decrypts → reverse ACK push goes back to Alice
5. Alice gets "🟢 Bob saw your message" notification
```

**Trust Circle**: You can only message people in your trust circle. Add via pairing code, accept/invite flow, or block/remove.

---

## Backend API (urgentsee-edge)

### Setup
```bash
cd urgentsee-edge
npm install
wrangler secret put JWT_SECRET    # set a strong random value
wrangler d1 execute urgentsee-db --file=us_schema.sql --remote
wrangler deploy
```

### Run locally
```bash
cd urgentsee-edge
npm run dev          # wrangler dev
npm test             # vitest run (103 tests, all passing)
npm run typecheck    # tsc --noEmit
```

### Environment Variables (Secrets)
| Variable | Where | Purpose |
|----------|-------|---------|
| `JWT_SECRET` | `wrangler secret put JWT_SECRET` | HMAC-SHA256 signing key |
| `APNS_AUTH_KEY` | `wrangler secret put APNS_AUTH_KEY` | ES256 .p8 key for APNs |
| `APNS_KEY_ID` | wrangler.toml or secret | Apple Key ID |
| `APNS_TEAM_ID` | wrangler.toml or secret | Apple Developer Team ID |
| `APNS_ENV` | wrangler.toml | `development` or `production` |
| `APNS_TOPIC` | wrangler.toml | Bundle ID (default: `com.urgentsee.UrgentSee`) |

### API Endpoints
All endpoints require `Authorization: Bearer <JWT>` header.

| Method | Path | Description |
|--------|------|-------------|
| POST | `/v1/device/register` | Register device, get JWT + userId |
| POST | `/v1/pairing/code` | Generate 6-char pairing code (15 min TTL) |
| POST | `/v1/pairing/claim` | Claim pairing code → bidirectional ACTIVE trust |
| POST | `/v1/user/token` | Sync APNs device token |
| PUT | `/v1/user/public-key` | Upload your X25519 public key |
| GET | `/v1/user/:id/public-key` | Fetch someone's public key |
| GET | `/v1/trust-circle` | List your trust circle members |
| POST | `/v1/trust-circle/invite` | Invite user (creates PENDING) |
| POST | `/v1/trust-circle/accept` | Accept invite (PENDING → ACTIVE) |
| POST | `/v1/trust-circle/block` | Block user (bidirectional BLOCKED) |
| POST | `/v1/trust-circle/remove` | Remove from trust circle |
| POST | `/v1/rush/dispatch` | Send encrypted urgent message |
| POST | `/v1/rush/ack` | Reverse ACK (recipient viewed message) |
| GET | `/v1/rush/alerts/:id` | Get alert details + ciphertext |
| POST | `/v1/rush/unsend` | Recall message (60s window) |
| POST | `/v1/rush/rate-limit-override` | Admin: clear rate limits |
| POST | `/v1/user/heartbeat` | Update last_seen_at |

### Rate Limiting
- **100 dispatches per sender→recipient pair per hour**
- Uses Cloudflare Durable Objects for distributed state
- Returns `429` with `Retry-After` header when exceeded
- Admin override via `/v1/rush/rate-limit-override`

### Database Schema (D1 SQLite)
All tables prefixed `us_` to avoid collisions:

```sql
us_users (user_id, public_key, apns_token, display_name, created_at, updated_at)
us_trust_circles (user_id, pal_id, status, has_app_installed, last_seen_at, created_at)
us_rush_alerts (alert_id, sender_id, recipient_id, payload_ciphertext, raw_message_preview, is_critical, ttl_minutes, until_received, retry_count, max_retries, status, expires_at, acknowledged_at, created_at)
us_telemetry_events (event_id, user_id, event_type, latency_ms, delivery_status, created_at)
```

### KV Namespace Keys
| Pattern | Purpose |
|---------|---------|
| `apns_token:<userId>` | Device push token |
| `pairing:<code>` | 15-min TTL pairing code → userId |
| `apns_provider_token:<keyId>` | Cached APNs JWT (55 min TTL) |

---

## iOS App (UrgentSee/)

### Build
```bash
xcodegen generate
xcodebuild -workspace UrgentSee.xcworkspace -scheme UrgentSee -configuration Debug build
```

### Architecture
- **MVVM** with `ObservableObject` view models
- `APIService` — all backend communication, token persistence
- `E2EEManager` — CryptoKit X25519 + ChaChaPoly, Keychain key storage
- `PushNotificationManager` — APNs registration, alert handling
- `ReverseAckService` — BGAppRefreshTask + unlock observer for passive ACK
- `TrustCircleManager` — trust circle state + actions

### Key Files
```
UrgentSee/
├── App/
│   ├── UrgentSeeApp.swift          # @main entry, tab view, background tasks
│   ├── AuthSettingsView.swift      # auth + device identity
│   └── SettingsView.swift          # app settings
├── Core/
│   ├── APIService.swift            # all /v1/* API calls
│   ├── E2EEManager.swift            # encrypt/decrypt, key management
│   ├── PushNotificationManager.swift  # APNs, alert routing
│   ├── ReverseAckService.swift     # background ACK on unlock
│   ├── TrustCircleManager.swift    # recipients list + actions
│   ├── UrgentSeeDispatchConsole.swift  # main send UI
│   └── RecipientsView.swift        # trust circle UI
├── Shared/
│   ├── SharedModels.swift          # Codable models
│   └── DesignSystem.swift          # UI constants
└── Entitlements/
    └── UrgentSee.entitlements      # aps-environment
```

### Live Activity Extension
`UrgentSeeLiveActivityExtension/` renders a lock screen banner with:
- Sender name + message preview
- Countdown timer (expires at TTL)
- ACK button (`urgentsee://ack?id=<alertId>` deep link)
- Compact/expanded Dynamic Island layouts

---

## Android App (android/)

### Build
```bash
cd android
./gradlew assembleDebug
```

### Architecture
- **MVVM** with Coroutines + Hilt DI
- Jetpack Compose UI (Material3)
- `WorkManager` + `ForegroundService` for background ACK
- `UnlockReceiver` (ACTION_USER_PRESENT) triggers reverse ACK

### Key Files
```
android/app/src/main/java/com/urgentsee/app/
├── UrgentSeeApp.kt                 # Application class
├── core/
│   ├── APIService.kt               # OkHttp + Moshi API client
│   ├── E2EEManager.kt              # XDH + ChaCha20-Poly1305 (JCA)
│   ├── PushNotificationManager.kt  # FCM handling
│   ├── ReverseAckService.kt        # WorkManager retry queue
│   ├── ActiveAlertCache.kt         # in-memory alert state
│   ├── AppContext.kt               # initialization + unlock observer
│   └── Receivers.kt               # broadcast receivers
├── ui/
│   ├── MainActivity.kt             # Compose entry point
│   ├── DispatchConsole.kt          # send UI
│   └── TrustCircle.kt              # recipients UI
├── widget/
│   └── UrgentSeeWidget.kt          # home screen widget
└── data/
    └── Models.kt                   # Kotlinx Serialization models
```

---

## E2EE Wire Format

Both platforms produce identical ciphertext:

```
[ephemeral_public_key (32 bytes)][nonce (12 bytes)][ciphertext + tag (variable)]
```

- **iOS**: `CryptoKit.X25519.KeyAgreement` + `ChaChaPoly.SealedBox`
- **Android**: `javax.crypto.XDH` KeyAgreement + `ChaCha20-Poly1305` Cipher
- **Key derivation**: HKDF-SHA256 with info `"UrgentSeeE2EE"`

> The same encrypted payload can be decrypted by either platform. Public keys are exchanged via `/v1/user/:id/public-key`.

---

## Testing

### Backend (103 tests, all passing)
```bash
cd urgentsee-edge
npm test
```

Coverage includes:
- `base64UrlDecode` — encoding/decoding edge cases
- `verifyJWT` — valid, expired, tampered, wrong-secret tokens
- `RateLimiterDO` — allowed, blocked, reset, Retry-After
- APNs payload construction (critical vs normal)
- Trust circle status transitions
- Reverse ACK validation
- Unsend window validation
- Pairing code generation
- Telemetry event formatting
- Heartbeat timestamp generation

### iOS
```bash
xcodebuild test -workspace UrgentSee.xcworkspace -scheme UrgentSee
```

### Android
```bash
cd android
./gradlew test
```

---

## What's Done

- [x] Full backend API with JWT auth
- [x] E2EE encryption (cross-platform compatible)
- [x] Trust Circle (invite/accept/block/remove/list)
- [x] APNs push with critical override
- [x] Rate limiting (Durable Objects)
- [x] Reverse ACK with background retry
- [x] Unsend/recall (60s window)
- [x] Pairing codes (bidirectional trust)
- [x] Telemetry logging
- [x] iOS app (builds + installs)
- [x] iOS Live Activity extension
- [x] Android app (project structure + core logic)
- [x] Backend: 103 unit tests passing

## What's Next

### Backend
- [ ] Add integration tests that mock D1/KV/DurableObjects end-to-end
- [ ] Export more handlers for unit testing (only `verifyJWT`, `base64UrlDecode`, `RateLimiterDO` exported)
- [ ] Add FCM support alongside APNs (Android push)
- [ ] Implement `scheduleUntilReceivedRetry` properly (needs cron trigger or queue)

### iOS
- [ ] Unit tests for E2EE roundtrip (encrypt → decrypt)
- [ ] Unit tests for `APIService` with mocked URLSession
- [ ] UI tests for dispatch flow

### Android
- [ ] Wire up FCM in `PushNotificationManager`
- [ ] Unit tests for E2EE roundtrip
- [ ] UI tests for dispatch flow

### DevOps
- [ ] CI/CD with GitHub Actions
- [ ] Play Store / App Store deployment
- [ ] Automated screenshots

### Feature Ideas
- [ ] Message expiration with automatic cleanup worker
- [ ] Read receipts beyond just "unlock" (explicit tap-to-acknowledge)
- [ ] Group messaging (broadcast to multiple trust circle members)
- [ ] Scheduled sends ("send this at 9am tomorrow")
- [ ] Message priorities beyond critical/normal

---

## Vibe Coder Notes

**Where things get tricky:**

1. **APNs is finicky** — provider token cached in KV (55 min TTL) because Apple rate-limits token generation to ~1 per 20 min. If pushes fail with `429 TooManyProviderTokenUpdates`, check KV cache.

2. **The `untilReceived` retry is stubbed** — `scheduleUntilReceivedRetry` calculates `maxRetries` and stores it, but nothing triggers retries yet. You need a cron trigger (`[triggers] crons = ["*/5 * * * *"]`) or a separate queue.

3. **Trust circles are bidirectional** — when A invites B, we create `(A→B, PENDING)`. When B accepts, update `A→B` to ACTIVE and insert `(B→A, ACTIVE)`. Block/remove/delete affect both directions.

4. **The 60-second unsend window** — `handleUnsend` parses `created_at` from SQLite (no timezone) by appending `Z` and treating as UTC. If you change the DB schema, update this parsing.

5. **iOS keychain is picky** — private keys stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Keys are lost if user restores from backup to different device. Consider `ThisDeviceOnly: false` for key portability.

6. **Android X25519 requires API 30+** — the `XDH` algorithm with `X25519` parameter spec only works on Android 11+. For older devices, add the Tink dependency.

**Files you'll probably touch first:**
- `urgentsee-edge/src/index.ts` — all backend handlers live here (~1150 lines)
- `urgentsee-edge/src/RateLimiterDO.ts` — rate limiting Durable Object
- `UrgentSee/Core/APIService.swift` — iOS networking
- `UrgentSee/Core/E2EEManager.swift` — iOS crypto
- `android/.../core/APIService.kt` — Android networking
- `android/.../core/E2EEManager.kt` — Android crypto

**Environment for development:**
- Backend runs at `http://localhost:8787` (wrangler dev)
- iOS app defaults to `https://urgentsee-edge.pounds1.workers.dev` (override via `API_BASE_URL` in Info.plist)
- Android app defaults to `https://api.urgentsee.app/v1/` (override in `APIService` constructor)

---

## Credits

- Cloudflare Workers + D1 + KV
- CryptoKit (iOS) / JCA XDH (Android)
- BGAppRefreshTask (iOS) / WorkManager (Android)
- Live Activities + App Widgets