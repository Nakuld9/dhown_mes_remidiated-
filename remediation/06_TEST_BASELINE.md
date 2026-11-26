# 06 — Test & Build Baseline (Deliverable G)

**Date:** 2026-11-26 · **Env:** this remediation clone, Node 22.23, npm 10.9, Postgres 16 (isolated scratch cluster on `127.0.0.1:55432`, localhost-only). **No live system touched.**

> All runs below are against the **remediation copy** and an **isolated scratch DB**. Production DBs (`dhown_mes`, `vdknits_mes`) were never contacted; the e2e suite itself refuses those names.

---

## 1. Build

| Step | Result |
|---|---|
| `npm install` (backend) | ✅ **547 packages, ~5s.** 1 deprecation warning (`glob@10`). No install errors. |
| Root `package.json` | Empty/placeholder — the app is `backend/`. (minor: no root workspace scripts) |

## 2. Unit tests (Jest) — ✅ FULL PASS

```
npx jest --ci
Test Suites: 22 passed, 22 total
Tests:       252 passed, 252 total
Time:        ~0.9 s
```
Coverage spans accounting posting/rules/xml, GST (json/setoff/returns), TDS sections, payroll, shift, fabric grade, OEE quality, pagination, rate-limit, WhatsApp approvals/consent/margin/quote/score, invoice OCR. **This is the trustworthy, reproducible baseline.** (Note: `PROJECT_STATE.md` cited "171 unit"; the suite has since grown to **252** — a positive drift.)

## 3. E2E tests (Node scripts, `backend/tests/*.e2e.js`, 46 total)

| Category | Result |
|---|---|
| **Self-provisioning / fixture** (`busy-mirror`, `gst-returns`) | ✅ **PASS** against scratch DB — `busy-mirror` 14/14 (BUSY read-bridge TB balances to the rupee, net-profit reconciles), `gst-returns` 11/11. |
| **DB-backed, need core schema** (~35: `accounting`, `constraints`, `soft-delete`, `busy-production`, `dispatch-invoice`, `allocation`, `gstr1`, `financial`, `bank-recon`, …) | ⚠️ **BLOCKED** — crash on missing base tables (`users`, `machines`, `partners`, `financial_years`, `item_categories`). They self-provision their *own* sub-schema (`acct`, gst) but assume the **core public schema already exists**. |

## 4. 🔴 Finding (CONFIRMED-DEFECT / reproducibility) — no from-zero schema bootstrap

**There is no single command to provision the database from scratch.** Evidence:
- `npm run migrate:status` on a fresh DB → **0 applied, 0 pending**; the migrate runner (`src/db/migrate.js`) tracks almost nothing and **marks the legacy root `migration_*.js` as a pre-applied `baseline` without running them** (`LEGACY_BASELINE` logic) — it assumes an already-populated production DB.
- The core schema is built **only as a side-effect of `server.js` startup**, which calls ~**35 separate `ensureXxxSchema()`** functions from `src/db/schema.js` in a hand-ordered sequence. `schema.js` exports the 35 functions but **no orchestrator** (`ensureSchema`/`bootstrap`) — the order lives inside `server.js`.
- ~**20 legacy `migration_*.js`** scripts (idempotent DDL) must also be run, in an **undocumented order**, to complete the schema.

**Why it matters (remediation-relevant):**
- **CI/testing:** ~35 e2e suites can't run in a clean environment without booting the whole server — so CI can't validate them headlessly. This weakens the safety net right when we're about to change accounting/integration code.
- **DR / new environment:** standing up a fresh factory/standby or a staging DB is not a documented, repeatable step.
- **Confidence for retirement work:** you can't safely retire accounting modules if you can't reproducibly stand up and green-test the system in isolation first.

**Classification:** `CONFIRMED-DEFECT` (reproducibility) — not a runtime bug in production (prod already has the schema), so also `HISTORICAL` in origin.

## 5. Recommended fix (for the backlog, not done now)
Add a single idempotent `db:provision` entry point that, on an empty DB: (1) creates core schema, (2) calls every `ensureXxxSchema()` in the correct order (extract the order from `server.js`), (3) runs legacy `migration_*.js`, (4) records them in `schema_migrations`. Then e2e + CI can run from zero. This is **prerequisite work** before any accounting retirement, because it restores a testable baseline. → see `08_REMEDIATION_BACKLOG.md`.

## 6. What I did NOT do (and why)
- Did **not** boot `server.js` to force-provision — it starts background workers/integrations; not needed to establish the baseline or the finding, and out of scope for a read-only audit.
- Did **not** touch any production DB or the live server.

## Baseline summary (honest)
| Layer | Status |
|---|---|
| Build (`npm install`) | ✅ green |
| Unit (252 tests) | ✅ green |
| E2E self-provisioning (2 suites sampled) | ✅ green |
| E2E DB-backed (~35 suites) | ⚠️ not runnable from zero (reproducibility defect, §4) |
