# 07 — Independent Security Review (Deliverable F / #7)

**Date:** 2026-11-26 · **Method:** **static** code review of the copy + safe checks against an **isolated scratch DB**. **No live server contacted; no DELETE/POST/PUT probes** (honouring the CLAUDE.md incident rule). Runtime GET-only checks are **pending** a fully-provisioned scratch env (blocked by F-DB-1).

**Tags:** `CONFIRMED` · `HISTORICAL` · `POTENTIAL-RISK` · `NEEDS-BUSINESS-CONFIRMATION`. **Sev:** 🔴 high · 🟠 medium · 🟡 low.

---

## 🔴 SEC-1 — Exposed Groq API key in public git history — `CONFIRMED`
- `server-refractor` → `backend/.env:16` (commit `dec5183`) commits a live **Groq API key**; the source repo is **public**. GitHub push-protection blocked copying it.
- **Action (urgent, yours):** **revoke/rotate the Groq key now**; purge from history if the branch is kept anywhere. (Excluded from this copy already.)

## 🔴 SEC-2 — Hardcoded JWT fallback secret in a public repo — `CONFIRMED` (latent)
- `src/middleware/auth.js:10` — `const JWT_SECRET = process.env.JWT_SECRET || 'dhown_mes_jwt_secret_2026';`
- If `JWT_SECRET` is ever unset (a fresh env, a new site, a mis-deploy), auth falls back to a **publicly-known** secret → **anyone can forge a valid token for any role** (incl. `SUPER_ADMIN`). Prod reportedly sets `JWT_SECRET` (so prod is likely OK *today*), but the known fallback in public source is a serious latent bypass and undermines the token-revocation design.
- **Fix:** remove the fallback — **fail closed** if `JWT_SECRET` is missing (`throw` at boot). Rotate the prod secret regardless (the string is public). Same pattern-check for every `process.env.X || '<literal>'` secret.

## 🟠 SEC-3 — Socket.IO: `origin:"*"` and no connection auth — `POTENTIAL-RISK` (→ `CONFIRMED` if sockets carry sensitive data)
- `server.js:96` → `cors: { origin: "*" }` for Socket.IO; `server.js:131` → `io.on('connection', () => {})` — **no token/handshake check.** Any origin can open a socket.
- HTTP CORS is correctly an **allowlist** (`server.js:51` origin callback) — so this is specifically the realtime channel. If live production/dashboard/DC data is emitted over sockets, it's readable without authentication.
- **Fix:** authenticate the socket handshake (JWT in `io.use(...)`) and restrict `origin` to the same allowlist as HTTP.

## 🟠 SEC-4 — DC ingest auth dormant — `POTENTIAL-RISK` (confirms project's own note)
- `dcApiKeyGuard` enforces `x-api-key` **only when `DC_API_KEY` is set**; `PROJECT_STATE.md` says it's **not set in prod** → the `:8090` live-data ingest may accept unauthenticated writes on the factory LAN.
- **Fix:** set `DC_API_KEY` in prod (and keep `:8090`/`:5432` bound to `127.0.0.1`/LAN only, never public — already a documented rule).

## 🟡 SEC-5 — Dynamic SQL interpolation surface — `POTENTIAL-RISK`
- **43** `query(\`… ${…} …\`)` interpolations across `src/`. **Sampled ones are safe** — they interpolate **placeholder indices** (`$${p}`), **validated date clauses**, or **WHERE fragments built from parameterised conditions**, not raw user input (consistent with the project's "parameterised throughout" claim).
- **Risk:** 43 is too many to certify by sampling. A new one could interpolate user input.
- **Fix:** a one-pass manual review of all 43 (I can do this next); add a lint rule forbidding non-placeholder interpolation in `query(`.

## 🟡 SEC-6 — Input validation is per-route, not centralised — `POTENTIAL-RISK`
- No schema-validation layer (e.g. zod/Joi) at the edge; validation is ad-hoc in handlers. Works, but coverage is uneven and hard to audit. **Fix (improvement):** standardise request validation on the write routes, especially the new bridge endpoints.

---

## Positives (verified present — preserve these)
- **Parameterised queries predominant**; advisory locks on money paths (`pg_advisory_xact_lock`).
- **HTTP CORS allowlist** (origin callback), **PIN rate-limiting** (5/5min), **login limiter**, **AI limiter**.
- **RBAC** via `requireRole` + role hierarchy; **auditor write-block**.
- **JWT revocation list** + per-user cutoff (`token-revocation.js`), `jwtid` on every token.
- **No weak admin default** (random if `ADMIN_DEFAULT_PASSWORD` unset); **no secrets committed on `main`**.
- **Tests refuse production DB names** (`dhown_mes`/`vdknits_mes`).
- **Audit logging** with real username.

## Historical (context, not an open defect)
- **`HIST-1` (2026-08-06):** a route-sweeping probe sent `DELETE /1` with an admin token and **deleted the live admin user**; recovered from backup. → the standing **GET-only / scratch-DB** rule exists because of this. I am honouring it — no write probes anywhere in this audit.

---

## Scope honesty / what's pending
- This is a **static** review plus scratch-DB-safe checks. **Runtime GET-only verification** (hitting endpoints on a local scratch instance to confirm auth gates, CORS behaviour, and the socket handshake) is **pending F-DB-1** (can't boot cleanly from zero yet). Once the baseline schema is recovered and `db-provision.js` completes, I'll run those GET-only checks to confirm SEC-2/3/4 behaviour empirically.
- **Backup/restore & transaction-integrity** review is partial: `backup.service.js` exists (daily `pg_dump`, offsite) — a restore-drill verification needs the scratch env and is queued.

## Priority order (security)
1. 🔴 SEC-1 rotate Groq key (now). 2. 🔴 SEC-2 remove JWT fallback + rotate. 3. 🟠 SEC-3 socket auth. 4. 🟠 SEC-4 set `DC_API_KEY`. 5. 🟡 SEC-5 audit 43 SQL interpolations. 6. 🟡 SEC-6 central validation (esp. bridge).
