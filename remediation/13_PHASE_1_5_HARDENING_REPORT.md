# 13 — Phase 1.5 Application & E2E Hardening Report

**Date:** 2026-11-27 · Branch `claude/mes-busy-remediation` · Code commit `07c3795` (this report follows).
**Scope:** resolve the 9 e2e/app-robustness items left after P0-4, on **PostgreSQL 18.7** scratch DBs.
**Restrictions honoured:** scratch-only, no production contact, no live BUSY writes, no deployment, no accounting *retirement*, no factory-workflow change, no invoice/ownership policy change, recovered baseline (`00_baseline_schema.sql`) **unchanged**, all work on the remediation branch.

---

## Result — all green, reproducibly, on two independent fresh DBs

| Check | Result |
|---|---|
| Provision (2 fresh DBs, from zero) | **71 OK / 0 FAIL · 180 public + 22 acct tables** (each) |
| Unit (Jest) | **262 / 262 PASS** (256 baseline **preserved** + 6 new) |
| BUSY reconciliation | **14 / 14 ALL-PASS** (preserved) |
| Full DB-backed e2e | **46 / 46 PASS on BOTH DBs** (0 failed) |
| Structure comparison reg_1 vs reg_2 | **column md5 IDENTICAL** — zero drift |
| Auth / role regression (`roles`, `sales-role`, `jwt-fail-closed`) | **PASS** (in the suites above) |

> No test assertion was weakened; one dependency (Groq) is **mocked and labelled as such**; everything else is a real fix or a deterministic fixture.

---

## A — Application robustness (`finished-entry`)

**Root cause (deeper than a `.map`):** `finished_goods.roll_id` — written by `src/lib/finished-entry.js` — has **no `CREATE`/`ALTER` DDL anywhere in source** (a post-July column, like the F-DB-1 family). So `create()` returned a clean 500 and the *test* then crashed on `out.created.map`.

**Fix:**
- `src/db/schema.js`: `ensureFinishedGoodsSchema()` — `ALTER TABLE finished_goods ADD COLUMN IF NOT EXISTS roll_id VARCHAR(50)` (type matched to `rolls.roll_id`; nullable). Wired into `server.js` boot **and** `db-provision.js`.
- `tests/finished-entry.e2e.js`: guarded `(out.created || []).map(...)` — a create error now fails cleanly, never crashes, and the genuine error is **not** hidden.
- **New regression suite** `test/finished-entry.test.js` (6 tests): empty / null / non-positive / valid / DB-error paths (mocked pool).

## B — E2E environment configuration

- **`reports-extra`, `sales-role`:** run against a **real local server** booted on a scratch DB (`PORT=4000`, same `JWT_SECRET` so signed role tokens are accepted). Both **PASS**. No auth/role assertion weakened.
- **`wa-webhook-ai`:** part 1 (HMAC gate) is real and passes. Part 2's **Groq transport is MOCKED** (a canned completion intercepts `https.request` to `api.groq.com`) — exercises `callGroq`'s real build/parse with **no live call and no production credentials**. The test label now says "**Groq transport MOCKED**" so it is not mistaken for live reachability.

## C — Deterministic test fixtures (no production data, no invented master data)

| Suite | Fixture | Provenance |
|---|---|---|
| `accounting` | FY **2026-27** inserted + made active before acct build | Fixed Indian-FY dates (the suite is pinned to FY 26-27) |
| `allocation` | item insert resolves a **real `uom_id`** (`WHERE code='MTR'`) instead of hardcoded `1` | Seeded UOM reference data |
| `dispatch-invoice` | `app_settings.state = 'Punjab'` (home state ⇒ IGST/CGST split) | Documented DHOWN/VD-Knits location (the test itself uses "Punjab 03") |
| `matrix-valuation` | the app's **documented default approval bands** are seeded by provisioning (`wa-approvals.seedDefaults`) | `DEFAULT_BANDS` in `src/lib/wa-approvals.js` — the app's own defaults |

## D — By-design behaviour preserved (`medium-batch`)

Verified against the schema: `schema_migrations` (`applied_at`), `revoked_tokens` (`revoked_at`/`expires_at`, append-only JWT blocklist), and `morning_briefings` (`briefing_date`/`generated_at`, a generated daily report) legitimately track time via their **own** columns. **No columns were added**; the test expectation is **exempted with a documented reason** and its label narrowed to "every **business/operational** table".

---

## Deeper issues found & fixed (beyond the 9 tests)

| # | Finding | Class | Action |
|---|---|---|---|
| F-1.5-1 | **Outbox concurrency bug** — concurrent `process()` of one event: the lost-race call hit the idempotency-key unique violation, marked the row **FAILED**, and **threw** (corrupting the winner's PROCESSED status). | CONFIRMED-DEFECT (concurrency) | `outbox.js`: **idempotent lost-race recovery** — detect the winning voucher by key, mark PROCESSED, return it. Error-path only; 57 accounting unit tests still pass. |
| F-1.5-2 | **`db-provision.js` missed ~13 boot provisioners** server.js runs (seedDefaultAdmin, wa-approvals.seedDefaults, loans, budgets, cashflow, profitability, shade-approvals, busy-bridge, audit, wa-campaigns, error-tracker, ci, token-revocation, morning-briefing). Clean DB was silently incomplete (158 vs a booted 180). | CONFIRMED-DEFECT (provisioning) | Wired all into the provisioner → **180 tables, matches a booted app**. |
| F-1.5-3 | **Undeclared `openai` dependency** — `src/ai/glm.js` imports `openai`, absent from `package.json`; a fresh `npm ci` + boot fails. | CONFIRMED-DEFECT (deps) | Declared `openai@^7.65.0` in `package.json` + lockfile. |
| F-1.5-4 | **Eager AI-client init crashes boot** — `glm.js` constructs the OpenAI/GLM client at module load and **throws** without `OPENAI_API_KEY`, so a keyless deploy can't boot. | POTENTIAL-RISK | **Documented, not changed** (recommend lazy/guarded init). Test server booted with a dummy key. |
| F-1.5-5 | **Stale active financial year on a fresh DB** — `migration_erp_phase0def.js` pre-seeds `financial_years`, so `ensureReferenceData`'s current-FY insert is skipped; the **active FY is 2025-26**, not the current 2026-27. | POTENTIAL-RISK | **Documented** (accounting fixture works around it); recommend an idempotent current-FY upsert in the seed — a production-boot change, flagged for a separate decision. |

---

## Changed files (commit `07c3795`)
**App/schema:** `backend/src/lib/accounting/outbox.js`, `backend/src/db/schema.js`, `backend/server.js`, `backend/scripts/db-provision.js`, `backend/package.json` (+ `package-lock.json`).
**Tests:** `backend/test/finished-entry.test.js` (new), `backend/tests/finished-entry.e2e.js`, `backend/tests/accounting.e2e.js`, `backend/tests/allocation.e2e.js`, `backend/tests/dispatch-invoice.e2e.js`, `backend/tests/medium-batch.e2e.js`, `backend/tests/wa-webhook-ai.e2e.js`.
**Report:** `remediation/13_PHASE_1_5_HARDENING_REPORT.md` (+ `STATUS.md`).
**Unchanged:** `backend/schema/00_baseline_schema.sql` (recovered baseline + provenance preserved).

## Exact commands (reproducible)
```bash
# 2 fresh PG18.7 scratch DBs → provision from zero → verify
DB_NAME=dhown_reg_1 node backend/scripts/db-provision.js      # 71 OK/0 FAIL, 180 tables
cd backend && npx jest --ci                                   # 262/262
node tests/busy-mirror.e2e.js                                 # 14/14
# full e2e: boot server on the DB (PORT=4000, JWT_SECRET set), then:
for f in tests/*.e2e.js; do LOAD_BASE=http://localhost:4000 node "$f"; done   # 46/46
```
Mock/fixture notes for honesty: `wa-webhook-ai` mocks the Groq transport; the test server boots with a **dummy** `OPENAI_API_KEY`/`GROQ_API_KEY` (construction only — no real calls); `JWT_SECRET` is a test value.

## Remaining defects / blockers
- **None blocking** — all 46 e2e + 262 unit + 14 BUSY green on two independent DBs.
- **Flagged for a separate decision (production-boot changes, out of Phase 1.5 scope):** F-1.5-4 (lazy AI-client init) and F-1.5-5 (current-FY seed upsert). Neither blocks the test suite or the baseline.
- **Security items still open (owner action):** SEC-1 Groq key, SEC-2 JWT rotation, SEC-7 public prod dumps — unchanged from report 11.

**Stop after Phase 1.5. Awaiting explicit approval before Phase 2 (BUSY integration implementation).**
