# 05 — Database Schema & Migration Findings (Deliverable E + items 2–4)

**Date:** 2026-11-26 · All evidence from the remediation copy against an **isolated localhost scratch Postgres 16**. Production never contacted.

**Classification tags:** `CONFIRMED-DEFECT` · `HISTORICAL` · `POTENTIAL-RISK` · `PROPOSED-IMPROVEMENT`.

---

## F-DB-1 🔴 No from-zero schema provisioning — core table DDL is missing from source — `CONFIRMED-DEFECT`

**Claim:** The current source **cannot recreate its own database.** The foundational tables have **no `CREATE TABLE` anywhere** in the repo.

**Evidence (empirical — `backend/scripts/db-provision.js` on an empty DB):**
- Result: **105 public tables created, 7 steps FAILED, `acct` schema = 0 tables.**
- The schema-ensure functions are mostly **ALTER/augment** helpers that assume tables already exist. Failures, verbatim:
  - `ensureSoftDelete` → **`relation "users" does not exist`**
  - `ensureKnittingSchema` → `relation "machine_live_data" does not exist`
  - `ensureFabricInspectionSchema` → `relation "app_settings" does not exist`
  - `ensureFinancialViews` / `ensureFinancialConstraints` → `credit_notes`, `credit_note_allocations`, `sales_returns`, `lot_allocations`, `lot_allocation_rolls`, `eway_bills`, `delivery_proofs` do not exist
  - `acct.ensure` → **aborted** (depends on missing tables)
- Direct check: `machines`, `rolls`, `operators`, `machine_status_log`, `machine_downtime`, `rfid_events` → **no CREATE DDL in any `.js`/`.sql`**. The code only does `ALTER TABLE machines ADD COLUMN …` (a source comment even lists `machines` among tables it alters).
- Static tally: **175** `CREATE TABLE` statements in source vs **~385** distinct tables referenced in queries.

**Root cause (`HISTORICAL`):** the original monolithic `server.js` (7,914 lines) that created these tables was refactored down to ~791 lines; the inline `CREATE TABLE`s for the oldest core tables were **not carried into the new `ensureXxxSchema` modules** — production kept working only because its tables already existed.

**Impact:**
- **CI / testing:** ~35 DB-backed e2e suites can't run from a clean DB → the safety net is unavailable exactly when we need it for integration/retirement work.
- **Disaster recovery / new site / staging:** no documented, repeatable way to stand up the schema. A rebuild depends on an existing DB.
- **Blocks the remediation itself:** you cannot safely retire accounting code without first proving the system stands up and greens in isolation.

**Fix (prerequisite, see §Procedure):** recover the authoritative DDL as a committed baseline, then the provision runner completes.

---

## F-DB-2 Migrate runner tracks almost nothing; schema is built by side-effects — `CONFIRMED-DEFECT` (design)

- `npm run migrate:status` on a fresh DB → **0 applied, 0 pending**. `src/db/migrate.js` marks the **20 legacy root `migration_*.js` as a pre-applied `baseline` without running them** (`LEGACY_BASELINE`), assuming an already-populated prod DB.
- Real provisioning is scattered across **three mechanisms**: (a) **32 `ensureXxxSchema()`** called in a hand-ordered sequence inside `server.js` (lines 956–999), (b) **20 legacy `migration_*.js`** (idempotent DDL, undocumented order), (c) a few `migrations/*.js` run by the runner. There is **no single source of truth** for the schema.
- **`PROPOSED-IMPROVEMENT`:** converge on one idempotent provisioner (delivered as `db-provision.js`) + a committed baseline; keep the runner for incremental changes only.

## F-DB-3 Provision/boot order dependencies are implicit — `POTENTIAL-RISK`

- The ensure order matters (e.g. `ensureFinancialConstraints` adds FKs to tables other ensures create) but is encoded only by call order in `server.js`. A reordering or a new module inserted wrongly silently breaks a clean build. Documented now in `db-provision.js` (`ENSURE_ORDER`) — **the canonical order lives in that array.**

## F-DB-4 Self-ensuring `busy_*` mirror has no migration — `POTENTIAL-RISK` (low)
- `lib/busy-bridge.js` creates its `busy_*` mirror tables at runtime via `ensure()`. Fine operationally, but the bridge-state tables we're adding (master-mapping/queue/recon) should be **proper migrations** (per the carried-forward `migration_phase11_busy_bridge.sql` design), not runtime-only, so they're reviewable and versioned.

## F-DB-5 Two-company schema drift risk — `POTENTIAL-RISK` / `NEEDS-BUSINESS-CONFIRMATION`
- Two production DBs exist (`dhown_mes`, `vdknits_mes`). With no single provisioner, the two can drift. Reconciling them is out of scope here but should be verified before BUSY cutover (each company maps to its own BUSY company file, e.g. COMP0004).

---

## Deliverable item 3 — e2e suites & legacy scripts: dependencies & execution order (documented)

**Schema provision order (canonical, from `server.js` boot, now in `db-provision.js`):**
1. *(recovered)* `schema/00_baseline_schema.sql` — the missing core tables (F-DB-1).
2. Legacy ERP masters, dependency-first: `migration_erp_phase0a → 0b → 0c → 0def → phase1`, then the remaining `migration_*.js` (attendance, bom, costing, dispatch_*, inventory_v2, knitting*, opening, phase2_*, quality_inspection, sc_invoice_lowstock, warehouse).
3. 32 `ensureXxxSchema()` in the exact `ENSURE_ORDER` list.
4. `migrate.run()` → `import-schema.ensure()` → `acct.ensureAccountingSchema()` → `seedDefaultAdmin()`.

**e2e DB dependency classes (46 suites):**
- **Self-contained / fixture** (run anywhere): e.g. `busy-mirror` (✅ 14/14), `gst-returns` (✅ 11/11).
- **Self-provision a sub-schema** then run (need core tables to pre-exist): e.g. `accounting` (drops+ensures `acct`).
- **Need full core schema** (blocked until F-DB-1 fixed): `constraints`, `soft-delete`, `busy-production`, `dispatch-invoice`, `allocation`, `gstr1`, `financial`, `bank-recon`, … (~35).
- **Safety:** every DB-backed suite reads `ACCT_TEST_DB`/`DB_NAME` and **refuses production names** (`dhown_mes`, `vdknits_mes`). Good pattern — preserve it.

---

## Deliverable item 4 — repeatable clean-DB provision-and-test procedure

**Delivered:** `backend/scripts/db-provision.js` — idempotent, refuses prod DB names, reproduces boot order, reports a per-step OK/FAIL summary + table counts.

**Procedure (once the baseline DDL is recovered):**
```bash
# 1. scratch cluster (localhost only)  → createdb dhown_scratch
# 2. provision
DB_HOST=127.0.0.1 DB_PORT=55432 DB_USER=postgres DB_PASSWORD=*** DB_NAME=dhown_scratch \
  node backend/scripts/db-provision.js
# 3. create dhown_mes_staging, re-provision it, then run the suite
cd backend && npm test && npm run check   # unit (252) + e2e (46)
```

**BLOCKER (needs your action — one safe step):** produce the authoritative baseline DDL **without exposing data**:
```bash
pg_dump --schema-only --no-owner --no-privileges -d dhown_mes_staging \
  > backend/schema/00_baseline_schema.sql
```
- `--schema-only` ⇒ **structure only, zero rows, no secrets.** Run it against **staging or a restored backup, never the live prod DB directly** (your Condition 10). Commit it to this **private** repo.
- Once present, `db-provision.js` applies it first and the ~35 blocked e2e suites become runnable → a true from-zero green baseline.

**Current partial result (source-only, no baseline):** 105 public tables, 7 failing steps, acct=0 — documented above as proof of F-DB-1.

> Until the baseline is recovered, the **preserved baselines stand**: unit **252/252** and BUSY read-bridge reconciliation (`busy-mirror` 14/14). We do **not** lose those.
