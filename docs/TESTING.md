# TESTING — verify what's built so far (Phase 1)

Run these in order. Each step lists the command and what you should see.
If a step doesn't match, copy the command + output and send it back.

---

## A. Backend — unit tests (fastest check, no database needed)

```bash
cd backend
pip install -r requirements.txt
PYTHONPATH=. pytest -q
```

**Expect:** `9 passed`

What this proves: MCQ grading is correct; matching / numeric / multi-select /
keyword (with Uzbek Latin↔Cyrillic folding) all work; and the public question
projection cannot leak an answer key (a test fails the build if it ever could).

---

## B. Backend — full stack with Docker

```bash
cd backend
cp .env.example .env
docker compose up --build
```

**Expect:** logs end with `Application startup complete` and
`Uvicorn running on http://0.0.0.0:8000`.

Then in a browser open: **http://localhost:8000/docs**
You should see the Swagger UI with these endpoints:
`/v1/subjects`, `/v1/subjects/{id}/catalog`, `/v1/questions`, `/v1/submissions`,
`/health`.

Quick health check in another terminal:
```bash
curl http://localhost:8000/health
# -> {"status":"ok","env":"dev"}
```

> Note: the bundled docker-compose loads `001_init.sql` automatically but not the
> seed. Load seed + sample data once (see C) so the endpoints return content.

---

## C. Backend — load data and exercise the real endpoints

With the stack running (B), seed and ingest:

```bash
# from the backend folder, against the docker DB (or your own Postgres)
docker compose exec -T db psql -U edu -d edu < sql/002_seed.sql
docker compose exec api python -m app.ingest.run_geography \
    app/ingest/sample_data/geo_core.json app/ingest/sample_data/geo_uz.json
```

**Expect:** `ingest done: inserted=5 ...`

Now test the endpoints:

```bash
# 1) subjects -> should list 10, geografiya carries a name + image_url
curl http://localhost:8000/v1/subjects

# 2) grab geografiya id from above, then the catalog:
curl "http://localhost:8000/v1/subjects/<GEO_ID>/catalog"
#   -> grades [grade 6:2, grade 10:3], contexts school:5 entrance:3,
#      topics with localized titles: "Iqlim", "Aholi", "Materik va okeanlar..."

# 3) public questions for grade 10 -> 3 questions, and NONE contain
#    "correct", "is_correct", "grading_spec" or "answer_key"
curl "http://localhost:8000/v1/questions?subject_id=<GEO_ID>&grade=10"
```

This is the core security check: the answer key is never in the question payload.

To load **your real geography files** instead of the sample, drop them in and:
```bash
docker compose exec api python -m app.ingest.run_geography \
    geo_g10_core.json geo_g10_uz.json
```

---

## D. Mobile — run the app

```bash
cd mobile
flutter pub get          # also generates lib/l10n/app_localizations.dart
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

**Expect:** the app launches to the **Fanlar** (Subjects) screen showing the
subject grid with colored covers and progress bars.

Checks:
- Toggle your device/emulator to **dark mode** → the app follows it (orange stays,
  background goes near-black). The chrome never changes color per subject.
- The 10 subjects render with their accent colors on the covers only.
- Mascot: drop the EduOwl PNGs into `assets/mascot/` (names in mobile/README.md);
  until then the mascot simply doesn't render — nothing breaks.

> `10.0.2.2` is the Android emulator's alias for your computer's localhost (where
> the backend from step B runs). On a physical phone, use your computer's LAN IP,
> e.g. `--dart-define=API_BASE_URL=http://192.168.1.50:8000`.

---

## Common issues

- **Port 8000 already in use** → stop the other process or change the port in
  `docker-compose.yml`.
- **`flutter pub get` nudges a package version** → that's normal; let it update.
- **Mobile shows an empty/“—” grid** → the backend isn't reachable. Confirm B is
  running and the `API_BASE_URL` is right (emulator = `10.0.2.2`, phone = LAN IP).
- **Endpoints return empty lists** → you haven't run the seed + ingest in step C.

---

## What is NOT testable yet (by design — later phases)

Auth, leaderboard, gamification, live competitions, payments, and the remaining
app screens (picker, quiz, result) are not built yet. They're Phase 2–3.

---

# Phase 2 — auth, ranking/leaderboard, gamification, parent

## P2-A. Unit tests (no DB, no Redis needed)

```bash
cd backend
PYTHONPATH=. pytest -q
```

**Expect:** `38 passed` (29 always-on + 9 Redis-backed via fakeredis).
The Redis-backed OTP/ranking tests `pip install fakeredis` to run; without it
they **skip** (you'll see `28 passed, N skipped`) and the core suite still passes.

```bash
pip install fakeredis     # optional, to exercise OTP + ranking tests in-memory
```

What this proves: JWT issue/verify/expiry/tamper, refresh-token hashing, Argon2
password verify, Uzbek phone normalization, XP/level/streak arithmetic, OTP
lifecycle (issue → verify → single-use burn → attempt cap → request cooldown →
role intent), and leaderboard sorted-set ordering/standing/count.

> NOT covered by unit tests (needs a live DB): the auth/parent endpoints' actual
> Postgres round-trip. Exercise those with the curl flow below against the Docker
> stack.

## P2-B. Manual end-to-end (stack from step B running, data from step C loaded)

```bash
# 1) request an OTP (dev returns the code in the response)
curl -s -X POST localhost:8000/v1/auth/otp/request \
  -H 'content-type: application/json' \
  -d '{"phone":"+998901234567","role":"student"}'
#   -> {"retry_after_seconds":60,"expires_in_seconds":300,"debug_code":"123456"}

# 2) verify -> token pair
curl -s -X POST localhost:8000/v1/auth/otp/verify \
  -H 'content-type: application/json' \
  -d '{"phone":"+998901234567","code":"<debug_code>","display_name":"Ali","region_code":"tashkent","grade":10}'
#   -> {"access_token":"...","refresh_token":"...","token_type":"bearer","expires_in":900}

ACCESS=<access_token>

# 3) answer a question AS THE USER (Bearer token, not the guest header)
curl -s "localhost:8000/v1/questions?subject_id=<GEO_ID>&grade=10" | head
curl -s -X POST localhost:8000/v1/submissions \
  -H "authorization: Bearer $ACCESS" -H 'content-type: application/json' \
  -d '{"question_id":"<QID>","payload":{"option_ids":["a"]},"response_ms":4200}'

# 4) self overview -> xp/level/streak/accuracy + total rank
curl -s localhost:8000/v1/me -H "authorization: Bearer $ACCESS"

# 5) leaderboards (public; pass Bearer to also get your own standing back)
curl -s "localhost:8000/v1/leaderboard?scope=total&limit=10"
curl -s "localhost:8000/v1/leaderboard?scope=subject&key=geografiya&limit=10"
curl -s "localhost:8000/v1/leaderboard?scope=region&key=tashkent" -H "authorization: Bearer $ACCESS"

# 6) refresh rotation (old refresh token becomes invalid after this)
curl -s -X POST localhost:8000/v1/auth/refresh \
  -H 'content-type: application/json' -d '{"refresh_token":"<refresh>"}'
```

### Parent link flow
```bash
# student (logged in) mints a code
curl -s -X POST localhost:8000/v1/parent/link-code -H "authorization: Bearer $STUDENT_ACCESS"
#   -> {"code":"K7M2QP","expires_in_seconds":600}

# parent signs up (role=parent at otp/request), then redeems the code
curl -s -X POST localhost:8000/v1/parent/link \
  -H "authorization: Bearer $PARENT_ACCESS" -H 'content-type: application/json' \
  -d '{"code":"K7M2QP"}'

# parent reads child progress (read-only)
curl -s localhost:8000/v1/parent/children -H "authorization: Bearer $PARENT_ACCESS"
```

## P2-C. Config guard (DevOps/Security)

The API refuses to boot in prod with insecure config. Verify:
```bash
ENVIRONMENT=prod JWT_SECRET=change-me-in-prod docker compose up api
#   -> RuntimeError: insecure configuration: JWT_SECRET must be ... ; OTP_DEBUG_RETURN must be false ...
```
In dev the same problems log a `WARNING` but boot proceeds.
