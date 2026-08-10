# Topag'on

A quiz and competition platform for Uzbek school students, grades 5–11.
Practice by subject, server-side grading, leaderboards, and head-to-head
challenges against a friend.

| | |
|---|---|
| **App** | https://app.topagon.uz |
| **API** | https://api.topagon.uz |
| **Site** | https://topagon.uz |
| **Bot** | [@topagonuzbot](https://t.me/topagonuzbot) |

```
Backend   FastAPI · async SQLAlchemy 2.0 · PostgreSQL 16 + PostGIS · Redis 7
Client    Flutter (Material 3, Riverpod, Dio) — Web + Android
Deploy    Docker Compose · nginx · Let's Encrypt · Ubuntu 24.04
Content   ~17 000 active questions · 7 subjects · tagged by grade and topic
Locale    uz-Latn (primary) + ru
```

## Design decisions

**Answer keys never leave the server.** `questions.grading_spec` (JSONB) is the
only source of truth; the `options` table has no `is_correct` column. The model
sent to the client (`PublicQuestion`) and the one used to grade
(`GradingQuestion`) are separate types with a single crossing point in
`services/projection.py`, so a leak is blocked by the type system rather than by
remembering to be careful. The key is released in one place, only after a
correct answer.

**Currency is a ledger, not a balance.** `coin_transactions` is append-only and
the balance is `SUM(amount)`. Every one-off reward is guarded by a partial
unique index, which holds regardless of how the code is called:

```sql
CREATE UNIQUE INDEX uq_coin_quiz_reward
    ON coin_transactions (user_id, ref_id) WHERE reason = 'quiz_reward';
```

A lock can be forgotten and transaction isolation can surprise you; the index
cannot. XP is tied to the same insert, so re-answering a question earns nothing.

**Leaderboards live in Redis, not Postgres.** `lb:total`, `lb:subject:*` and
`lb:region:*` are sorted sets, read with `ZREVRANGE` / `ZREVRANK` in O(log N).
Postgres is queried only for the names on the page being shown.

## Running it

```bash
cd backend
cp .env.example .env
docker compose up -d --build
./scripts/migrate.sh
curl http://127.0.0.1:8000/health
```

Tests need no database — they check logic, not SQL:

```bash
cd backend && PYTHONPATH=. python -m pytest tests -q
```

Client:

```bash
cd mobile
flutter pub get && flutter gen-l10n
flutter run -d chrome --dart-define=MOCK=true
```

`MOCK=true` runs fully offline: `lib/api/mock_backend.dart` emulates the
endpoints in-process and follows the same rules as the real server, including
never returning a key for a wrong answer. Without that, a screen that worked
against the mock could behave differently in production.

## Layout

```
backend/
  app/api/v1/      42 endpoints — handlers stay thin, logic lives in services/
  app/core/        config, security, rate limiting, anti-scraping, Redis
  app/models/      ORM
  app/schemas/     public / grading projection split
  app/services/    grading, coins, challenges, ranking, progress, telegram
  app/ingest/      question bank importers
  sql/             forward-only migrations, 001..030
  tests/           175 tests, no database required
mobile/lib/
  api/             Dio client + mock backend
  auth/            token storage, auth controller
  features/        screens (quiz, challenges, leaderboard, parent, ...)
  theme/ widgets/  design system
  l10n/            uz + ru
landing/           static site for topagon.uz
```

## Security

Before the server accepts traffic, `config.validate_runtime()` checks ten
conditions and refuses to start if any fails: a weak `JWT_SECRET`, OTP codes
echoed in responses, the default database password, `CORS_ORIGINS=*`, the SMS
gateway left in `console` mode, a missing Telegram webhook secret, and an ad
reward that trusts the client.

* **Auth** — HS256 JWT (15 min) plus a rotating refresh token (30 days, stored
  only as a SHA-256 hash). Passwords use argon2.
* **Telegram login is two-step.** Pressing Start does not link an account; the
  bot asks for a code shown in the app. Without that step the flow was
  one-click account takeover.
* **Rate limiting** fails open on learning routes and closed on auth routes: a
  Redis outage should not stop a student mid-practice, but it must not open the
  door to unlimited password guessing either.
* **Anti-scraping** — the question bank is the product's main asset. A burst
  limit plus a HyperLogLog breadth check (unique questions per hour) separates a
  real student, who returns to a narrow set, from a scraper, which never repeats.
* **Authorization** — the parent dashboard is bound to a guardianship record
  rather than a role, and that record is only created from a code the child
  hands over.

## Docs

| File | About |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | layers and conventions |
| [docs/openapi.yaml](docs/openapi.yaml) | API contract |

## License

Source-available for review purposes.
