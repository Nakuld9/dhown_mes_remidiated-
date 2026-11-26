# `db-provision.js` — expected execution order

> ⚠️ **STATUS: UNVALIDATED. NOT production-ready. NOT a verified provisioner.**
> This script has **never been run end-to-end successfully**. It is **blocked**
> on a missing input (`backend/schema/00_baseline_schema.sql`, the recovered core
> DDL — see remediation finding F-DB-1). A source-only trial run (without that
> baseline) produced **105 public tables, 7 failing steps, `acct`=0** — i.e. an
> *incomplete* schema. Do **not** describe this as validated, ready, or safe for
> any non-scratch use until P0-4 verification passes against the real baseline on
> two independent clean databases.

This document records the order the script **attempts**, so the intended
provisioning path is reviewable. It is a description of intent, not a guarantee.

## Scope & safety
- **Scratch databases only.** The script refuses the production DB names
  (`dhown_mes`, `vdknits_mes`).
- Reads `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` from env/`.env`.
- Does **not** contact production and performs no BUSY writes.

## Prerequisites (all required for a complete run)
1. `backend/schema/00_baseline_schema.sql` — **NOT YET SUPPLIED.** The authoritative
   core-table DDL (`users`, `machines`, `rolls`, `operators`, `machine_status_log`,
   `machine_downtime`, `rfid_events`, …) that is absent from source. Must come from
   `pg_dump --schema-only` of a **staging/restored** DB (never live prod).
2. An empty scratch PostgreSQL database (localhost).
3. `npm install` completed in `backend/`.

## Expected execution order (what the script attempts)
0. **Baseline DDL** — apply `schema/00_baseline_schema.sql` if present
   (the missing foundational tables). **Without it, later steps fail.**
1. **Legacy root migrations**, dependency-first:
   `migration_erp_phase0a → 0b → 0c → 0def → phase1`, then the remaining
   `migration_*.js` (attendance, bom, costing, dispatch_pricing/types,
   inventory_v2, knitting, knitting_rate, opening, phase2_columns/maintenance,
   quality_inspection, sc_invoice_lowstock, warehouse).
2. **32 `ensureXxxSchema()`** in **`server.js` boot order** (the `ENSURE_ORDER`
   array in the script is the canonical copy of that order).
3. **`migrate.run()`** (runner migrations) → **`import-schema.ensure()`** →
   **`acct.ensureAccountingSchema()`** → **`seedDefaultAdmin()`**.

Per-step `[OK]/[FAIL]/[MISSING]/[ABSENT]` is printed, with a final table-count
summary.

## Seed / reference data — documented SEPARATELY from schema DDL
The schema dump alone does **not** supply runtime data. Known seed/reference
producers (to be inventoried and tested independently, **not** assumed complete):
- `seedDefaultAdmin()` — the initial `admin` user (password from
  `ADMIN_DEFAULT_PASSWORD`, else random once).
- `ensureReferenceData()` — reference rows (UOM/HSN/categories etc.).
- Company/financial-year rows required by `acct` and ERP masters.
A full seed/reference dependency inventory is **pending** and is a P0-4 task.

## Known gaps (why this is not validated)
- **Baseline DDL missing** → cannot complete a from-zero build (F-DB-1).
- **Implicit boot-order dependencies** → mirrored in `ENSURE_ORDER`; a wrong
  insertion silently breaks a clean build (F-DB-3).
- **Not yet run** on two independent clean DBs; **DB-backed e2e not yet run from
  zero**.
- Until those pass with the real baseline, treat output as diagnostic only.

## How it will be validated (P0-4, pending the baseline + approval)
Provision two independent empty scratch DBs from zero → run the full DB-backed
e2e suite on each → preserve unit 256/256 and BUSY reconciliation 14/14 →
classify every failure as setup vs application defect → report. Only after that
may any part of this be described as validated — and still only for scratch use.
