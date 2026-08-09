# ARCHITECTURE.md — Education Competition Platform

> This is the contract. Every developer and every AI coding agent reads this file
> **first**, before touching any module. If an instruction here conflicts with a
> code suggestion, this file wins. To change a rule here, change it deliberately —
> don't drift.

---

## 1. What we are building

A mobile-first (iOS + Android, Flutter) educational quiz + competition platform for
Uzbekistan, designed to scale to millions of users.

Launch subjects (codes are stable slugs, never change them):

| code | name (uz-Latn) |
|------|----------------|
| `geografiya` | Geografiya |
| `jahon_tarixi` | Jahon tarixi |
| `ozbekiston_tarixi` | O'zbekiston tarixi |
| `matematika` | Matematika |
| `geometriya` | Geometriya |
| `fizika` | Fizika |
| `kimyo` | Kimyo |
| `ona_tili` | Ona tili |
| `biologiya` | Biologiya |
| `huquq` | Huquq |

Question types: **`mcq` ships now.** `multi_select`, `numeric`, `open_keyword`,
`matching`, `ordering` are already supported by the grader. `open_text` (AI-graded)
is the only deferred type. Adding a type is a data change, never a migration.

---

## 2. The one rule that organizes everything

**The client renders. The server decides.**

Question order, timing, scoring, ranking, badge state, and payment state all live
server-side. The client is a dumb renderer. A student with a rooted phone and a
packet inspector must see nothing worth cheating with.

Concretely, this rule is enforced **structurally**, not by discipline:

- Answer keys live **only** in `questions.grading_spec` (JSONB, server-only).
- The `options` table has **no `is_correct` column** — correctness physically
  cannot ride along on a renderable row.
- `PublicQuestion` / `PublicOption` (Pydantic) have **no field that can hold a
  key**. `GradingQuestion` carries the key and is **never** used as a response
  model. `tests/test_projection.py` fails the build if anyone adds a key field to
  the public model.

If you are ever tempted to "just send the answer to the client to make the UI
easier" — stop. That is the product's whole security model.

---

## 3. Stack & topology

```
Flutter (iOS/Android)  ──HTTPS/JSON──▶  FastAPI (stateless workers)
        │                                   │
        └──────WebSocket (event window)─────┤   ← live competitions only
                                            │
                            ┌───────────────┼───────────────┐
                        PostgreSQL        Redis        Cloudflare R2
                     (source of truth)  (leaderboards,  (media: images,
                                         OTP rate-limit,  audio later)
                                         pub/sub backplane)
```

- **Hosting (launch):** one Hetzner VPS, Docker Compose (FastAPI + Postgres +
  Redis), Cloudflare in front (free CDN / DDoS / WAF). No Kubernetes until real
  scale demands it.
- **Scale path (documented, not built yet):** FastAPI is stateless → run N
  replicas behind a load balancer. Redis pub/sub is the WebSocket backplane so
  any worker can broadcast. Postgres → read replicas + PgBouncer, then partition
  `submissions` by month. Leaderboards never touch Postgres on read (Redis sorted
  sets). This is why "10M users" is a config change, not a rewrite.

---

## 4. Project layout (backend)

```
backend/
  app/
    core/        config, database (async SQLAlchemy), redis, security, errors
    models/      SQLAlchemy ORM (DB rows)
    schemas/     Pydantic — PUBLIC vs GRADING projections, request/response DTOs
    services/    business logic: grading, ranking, normalizer, analytics, ...
    api/v1/      thin HTTP/WS handlers — NO business logic here
    ingest/      data importers (geography_adapter, ...)
  sql/           001_init.sql (canonical schema)
  tests/
```

Layering rule: `api → services → models`. Handlers are thin. Business logic lives
in `services/` and is unit-testable without HTTP or (where possible) without DB.

---

## 5. Conventions

- **Language:** Python 3.12, FastAPI, **async** SQLAlchemy 2.0, Pydantic v2.
- **IDs:** UUID v4 everywhere (no auto-increment ints exposed).
- **Multilingual:** never store user-facing text on the core row. Use
  `*_translations` tables keyed by `lang` (`uz-Latn`, `uz-Cyrl`, `ru`, `en`).
  Requests carry `Accept-Language` (or `?lang=`); the projection resolves one
  language into `stem` / `text`.
- **Errors:** RFC 7807 problem+json. One error shape, app-wide (`core/errors.py`).
- **Auth:** phone + OTP. JWT access (15 min) + rotating refresh (hashed, revocable
  in `refresh_tokens`). Role enum `student|parent|admin` in one `users` table.
- **Pagination:** cursor-based (never `OFFSET` at scale).
- **Money & anti-cheat code:** human-reviewed line by line. AI may draft it; a
  human owns it.
- **Time:** all timestamps UTC (`timestamptz`). The server clock is authoritative
  for competition timing.

---

## 6. Module map & build phases

You (Zizu) own architecture + every trust boundary. Agents implement modules
against this doc + `openapi.yaml`. A separate fresh-context review pass audits
auth / payments / anti-cheat.

| Phase | Module | Status |
|------|--------|--------|
| **1** | DB schema, projection split, GradingService (type-dispatch), normalizer | ✅ built + tested |
| 1 | Subjects catalog, public questions, submit/grade endpoints | scaffolding |
| 1 | Geography ingest adapter (your two-layer JSON → DB) | scaffolding |
| **2** | Auth (phone+OTP, JWT, rotating refresh) | ✅ built + tested |
| **2** | Ranking (Redis sorted sets) + leaderboard endpoints | ✅ built + tested |
| **2** | Gamification (XP/level/streak), `/v1/me` | ✅ built + tested |
| **2** | Parent accounts (consent link-code, read-only dashboards) | ✅ built + tested |
| 2 | Async friend challenges | next |
| 2 | Analytics / weak-topic ML (your ML edge, no LLM) | next |
| 3 | Live competition (WebSocket, scheduled windows) + anti-cheat | later |
| 3 | Payments (Payme/Click webhooks, idempotent ledger) | later |
| 4 | open_text AI grading, LLM explanations, sponsorships/monetization wiring | later |
| — | Flutter app (type-dispatch renderer, metadata-driven nav, Material 3 + Rive) | parallel track |

Each future type (`matching`, `numeric`, image-based) is **additive**: the grader
branch already exists; the Flutter renderer adds one `case`. No core rewrite.

---

## 7. How agents are run (so output is coherent, not 10 piles of MVP)

1. **Contract first.** This file + `openapi.yaml` are the source of truth.
2. **One agent per module**, each isolated by the OpenAPI contract — modules don't
   share mutable state. They coordinate with the document, not with each other.
3. **Every implementation prompt starts with:** *"Read ARCHITECTURE.md and
   openapi.yaml. Implement only module X against that contract. Do not change the
   contract; if something's missing, list it and stop."*
4. **Separate review pass in fresh context** (ideally a different model) on auth,
   payments, anti-cheat: *"Assume the author was careless. List concrete security
   holes and contract violations."*
5. **Human owns** the architecture, the trust boundaries, and the final word.
