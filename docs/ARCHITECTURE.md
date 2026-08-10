# Architecture

## What this is

A quiz and competition platform for Uzbek school students (grades 5–11), built
mobile-first with Flutter on the client and FastAPI on the server.

Subject codes are stable slugs and are never renamed:

| code | name |
|------|------|
| `geografiya` | Geografiya |
| `jahon_tarixi` | Jahon tarixi |
| `ozbekiston_tarixi` | O'zbekiston tarixi |
| `matematika` | Matematika |
| `fizika` | Fizika |
| `kimyo` | Kimyo |
| `ona_tili` | Ona tili |
| `biologiya` | Biologiya |
| `huquq` | Huquq |

The grader handles `mcq`, `multi_select`, `numeric`, `open_keyword`, `matching`
and `ordering`. Adding a question type is a data change, not a migration.

## The rule everything else follows

**The client renders, the server decides.** Question order, scoring, ranking and
streak state all live server-side. A student with a rooted phone and a packet
inspector should find nothing worth cheating with.

This is enforced structurally rather than by discipline:

- Answer keys live only in `questions.grading_spec` (JSONB, server-side).
- The `options` table has no `is_correct` column, so correctness cannot ride
  along on a row that gets rendered.
- `PublicQuestion` and `PublicOption` have no field capable of holding a key.
  `GradingQuestion` carries the key and is never used as a response model.
  `tests/test_projection.py` fails the build if a key field is added to the
  public model.

The single crossing point between the two worlds is `services/projection.py`.
The key is released in exactly one place, after a correct answer, in
`api/v1/content.py`. Remove that condition and the "answer wrong, read the key,
resubmit" farm opens up, so it is pinned by `tests/test_submissions.py`.

## Topology

```
Flutter (Web/Android)  ──HTTPS/JSON──▶  FastAPI (stateless workers)
                                            │
                            ┌───────────────┼───────────────┐
                        PostgreSQL        Redis         object storage
                     (source of truth)  (leaderboards,   (media, later)
                                         rate limiting)
```

One VPS running Docker Compose (FastAPI + Postgres + Redis), nginx in front.
No orchestration until real load justifies it.

The scale path is deliberate rather than built: FastAPI is stateless, so it runs
behind a load balancer as N replicas; Redis pub/sub is ready as the WebSocket
backplane; Postgres gains read replicas and PgBouncer, then `submissions` is
partitioned by month. Leaderboard reads never touch Postgres.

## Backend layout

```
backend/
  app/
    core/        config, database (async SQLAlchemy), redis, security, errors
    models/      SQLAlchemy ORM
    schemas/     Pydantic - public vs grading projections, request/response DTOs
    services/    grading, ranking, coins, challenges, progress, telegram
    api/v1/      thin HTTP handlers, no business logic
    ingest/      question bank importers
  sql/           forward-only migrations, 001..030
  tests/
```

Layering is `api → services → models`. Handlers stay thin; logic lives in
`services/` and is unit-testable without HTTP and, where possible, without a
database.

## Conventions

- Python 3.12, FastAPI, async SQLAlchemy 2.0, Pydantic v2.
- UUID v4 for all ids; no auto-increment integers are exposed.
- User-facing text never sits on the core row. It lives in `*_translations`
  tables keyed by `lang` (`uz-Latn`, `uz-Cyrl`, `ru`). Requests carry
  `Accept-Language` or `?lang=`, and the projection resolves one language.
- Errors follow RFC 7807 problem+json, one shape app-wide (`core/errors.py`).
- Auth is phone + OTP, or username + password. JWT access tokens live 15
  minutes; refresh tokens rotate and are stored hashed in `refresh_tokens`.
- Pagination is cursor-based.
- All timestamps are UTC `timestamptz`. The server clock is authoritative.
