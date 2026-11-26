# 11 — Pre-Provisioning Review & Security Incident Investigation

**Date:** 2026-11-26 · Branch `claude/mes-busy-remediation` · Baseline reviewed: `backend/schema/00_baseline_schema.sql` (commit `d4ea09a`).
**Nothing executed.** No SQL run, no scratch DB created, no provisioning, no production contact, original repo untouched, recovered baseline unmodified.

**Tags:** `CONFIRMED` · `POTENTIAL-RISK` · `BLOCKER` · `INFO`.

---

## 1. Schema integrity findings (A)

**Object counts (verified against the file):**
| Object | Count | Object | Count |
|---|---|---|---|
| Tables | **63** | Primary keys | 63 |
| Sequences | **55** | Foreign keys | 63 |
| Indexes (all non-unique) | **39** | UNIQUE constraints | 34 |
| Trigger functions | **1** (`update_updated_at_column`) | CHECK constraints | 6 |
| Triggers | **1** (`trg_operators_updated_at`) | DEFAULT clauses | 240 |
| Generated columns | **1** (`… GENERATED … STORED`) | Identity columns | 0 |

- **PK/FK/unique/check:** PKs on all 63 tables; 63 FKs; 34 UNIQUE; 6 CHECK — all emitted as `ALTER TABLE ONLY … ADD CONSTRAINT …` (pg_dump style), 160 named constraints total.
- **Defaults/generated:** 240 defaults, all benign enums/literals (`'ACTIVE'`, `'DRAFT'`, `'VIEWER'`, `'India'`, `'KG'`, …). 1 `GENERATED … STORED` column (PG12+; fine on PG16). No virtual/identity columns.
- **Dependencies:** single schema `public`; FKs reference only in-dump tables; the trigger depends on the one function. Self-consistent as a unit.

**Safety — is the file free of data/secrets? (checked beyond "no INSERTs"):**
| Check | Result |
|---|---|
| `COPY` data blocks / `INSERT` / `\.` terminators | **0 / 0 / 0** — all stripped |
| `setval()` (sequence state) | 55 — numeric sequence positions only, **not sensitive** |
| `COMMENT ON` (can carry data) | 0 |
| DEFAULT literals scanned for secrets/emails/keys | none — all benign enums |
| bcrypt (`$2a$`), base64 keys, `sk-`, `AKIA`, `xox…`, emails | **none** |
| Function body | standard `NEW.updated_at = NOW()` — benign |
| `\restrict … <nonce>` / `\unrestrict … <nonce>` | present — **pg_dump 16.4+/17+ dump-hardening meta-commands; the token is a random nonce, NOT a credential** |

**Verdict (A): the baseline is schema-only and free of production data, credentials, hashes, tokens and PII.** ✅ `CONFIRMED`.

---

## 2. PostgreSQL 18.4 → 16 compatibility findings (B)

> Do not modify the recovered file. The adjustments below are applied at **load time** (a filter or a compat copy) or avoided by **matching the server version** — documented, not baked into `00_baseline_schema.sql`.

| # | Finding | Sev | Detail / required handling |
|---|---|---|---|
| B-1 | `SET transaction_timeout = 0;` | **BLOCKER on PG16** | GUC added in **PG17**. On PG16 → `ERROR: unrecognized configuration parameter`. Because `db-provision.js` applies the baseline with `-v ON_ERROR_STOP=1`, this **aborts the run**. Handling: run on **PG18** (matches prod), OR strip the PG17+ `SET` line(s) at load, OR drop `ON_ERROR_STOP` for the baseline step only. |
| B-2 | `\restrict` / `\unrestrict <nonce>` | POTENTIAL-RISK | psql meta-commands from recent pg_dump. Require a psql build that supports them (≥ 16.10 / 17.x). If the scratch `psql` is older → strip these two lines at load. |
| B-3 | `GENERATED … STORED` (×1) | INFO (OK) | Supported since PG12 — no issue on PG16. |
| B-4 | Extensions / collation / locale provider | INFO (OK) | **0** `CREATE EXTENSION`, **0** custom collation/`icu`/`LC_COLLATE`. No cross-version locale risk. |
| B-5 | Identity vs serial | INFO (OK) | Uses sequences + `DEFAULT nextval(...)` (not `IDENTITY`) → no PG17/18 identity quirks. |
| B-6 | Encoding | INFO (OK) | `client_encoding = 'UTF8'`, `standard_conforming_strings = on` — standard. |

**Recommendation (B): provision on PostgreSQL 18 to match the source dump and production** (eliminates B-1/B-2). If PG16 is mandated, apply a **documented load-time filter** removing the PG17+ `SET` line and the `\restrict/\unrestrict` lines — never editing the recovered baseline.

---

## 3. Migration & provisioning dependency map (C)

```
EMPTY SCRATCH DB
  └─0. backend/schema/00_baseline_schema.sql     ← 63 tables (incl. the 18 source cannot build), 55 seq, 160 constraints
        (plain CREATE TABLE → apply to EMPTY DB only; NOT idempotent on re-run)
  └─1. legacy migration_*.js  (20 files; ERP-phase0a→0b→0c→0def→phase1 first, then the rest)
        (14/20 use CREATE TABLE IF NOT EXISTS; 0 use plain CREATE TABLE → skip baseline tables, no table collisions)
  └─2. src/db/schema.js — 32 ensureXxxSchema() in server.js boot order
        (ADD CONSTRAINT: only 3, heavily guarded; ~259 IF NOT EXISTS / pg_constraint / DO guards;
         indexes via CREATE INDEX IF NOT EXISTS → low collision risk)
  └─3. migrate.run()  →  import-schema.ensure()  →  acct.ensureAccountingSchema()  →  seedDefaultAdmin()
```

**Findings:**
| Area | Finding | Sev |
|---|---|---|
| Duplicate object creation | 45 of 63 baseline tables are also created in source — **safe**, source guards with `IF NOT EXISTS`. | INFO |
| Conflicting column defs | July baseline columns vs post-July `ADD COLUMN IF NOT EXISTS` ensures → reconciled forward; **verify no type drift in the run**. | POTENTIAL-RISK |
| Constraint-name collisions | Baseline names are pg_dump style (`x_pkey`/`x_col_fkey`/`x_key`); ensures use `idx_*` + only 3 guarded `ADD CONSTRAINT` → **low risk**; confirm the 3 in the run. | POTENTIAL-RISK (low) |
| FK ordering | Baseline is self-consistent (all its FKs internal, applied first). | INFO (OK) |
| **Missing seed/reference data** | Stripping data emptied reference tables. Source **re-seeds** `users, warehouses, uom, tax_rates, item_categories, financial_years, doc_series, defect_types, app_settings`. **Not re-seeded: `hsn_codes`, `departments`, `cost_centres`** (had rows in the dump) — may be needed by ERP/e2e. | **POTENTIAL-RISK** |
| Idempotency | Baseline (plain CREATE TABLE) is **not** safe to re-run on a populated DB; the whole process is **clean-DB-only**. Document as a constraint. | CONFIRMED |
| Startup-only objects | `db-provision.js` already replicates the full `server.js` boot (ensures + acct + import-schema + seed) → **no object is startup-only / unreproducible**. | INFO (OK) |

---

## 4. Intended provisioning order
As in §3: **baseline → legacy migrations (ERP-phase first) → 32 ensures (boot order) → migrate.run → import-schema → acct ensure → seedDefaultAdmin** → then reference-data top-up for any unseeded tables (§3) → app-level/e2e seed as each suite requires.

---

## 5. SEC-7 & SEC-1 incident findings (D)

> No secrets, hashes or PII were printed. Columns were confirmed from the **data-free** baseline DDL; the exposed **data** lives in the original repo's `server-refractor` dumps, which were not opened/printed.

**SEC-7 — production DB dumps with data in a PUBLIC repo — `CONFIRMED`**
- **Affected files (4):** `backend/backups/dhown_mes_2026-07-01.sql`, `-07-02.sql`, `-07-03.sql`, `-07-05.sql`.
- **Affected branch/commit:** **only `server-refractor`**; all four introduced in **one commit `dec5183` ("Phase 1 backend architecture setup")**. Not in `main` or `claude/dhown-busy-bridge`.
- **Exposed content:** full table data (63 `COPY` blocks/dump). DDL confirms the dumped tables include **`users.password_hash`** (bcrypt hashes) and partner/commercial PII columns — **`gstin`, `pan`, `mobile`, `email`, `bank_name`/`bank_id`, `company_name`**. So **password hashes and customer/supplier PII were publicly exposed**.
- **Authentication material at risk:** user password hashes (offline-crackable) → treat as compromised.

**SEC-1 — Groq API key — `CONFIRMED`** (same branch, same commit `dec5183`, `backend/.env`).

---

## 6. Recommended security remediation (SEC-7 + SEC-1)

**Immediate (stops ongoing exposure):**
1. **Make the original repo `Nakuld9/DHOWN_LIVE_PRODUCTION_DASHBOARD` Private** (and the remediation repo). Assume everything public was already scraped.
2. **Rotate now:** the **Groq API key**; **all user passwords** (force reset + re-hash; bcrypt hashes are exposed); the **JWT secret** (SEC-2, already public); and **review `app_settings` dump data** for any integration credentials (WhatsApp/GLM/Groq tokens, `BUSY_BDS_PASSWORD`, DB passwords) and rotate those too.

**History cleanup (defense in depth):**
3. Purge `backend/backups/` and `backend/.env` from the original history — delete the stale `server-refractor` branch (it's already excluded from the remediation copy and superseded) and/or run `git filter-repo`/BFG on the original, then force-push. **Do not rewrite the original repo without the owner doing it deliberately** — this is a plan, not an action I take.

**Verification:**
4. After rotation + cleanup: confirm the files 404 on github.com, check GitHub's cached/forks, and audit access logs if available. Note GDPR/India-DPDP implications of the PII exposure for your records.

*(These are security actions on the original repo; none block P0-4, which uses only the scrubbed, data-free schema.)*

---

## 7. Clean-install execution plan (PROPOSED — do not run)

Two independent scratch DBs (`dhown_prov_a`, `dhown_prov_b`). **Prefer a PostgreSQL 18 scratch to match the dump** (resolves B-1/B-2); PG16 variant needs the documented load-time filter.

```bash
# 0. (PG16 only) one-time compat copy at load — never edits the recovered file:
#    grep -vE "^SET transaction_timeout|^\\\\(un)?restrict" backend/schema/00_baseline_schema.sql > /tmp/base.pg16.sql
# 1. start an isolated, localhost-only scratch cluster (never port-exposed)
#    initdb + pg_ctl -o "-p 55432 -c listen_addresses=127.0.0.1"
# 2. for DB in dhown_prov_a dhown_prov_b:
createdb -h 127.0.0.1 -p 55432 -U postgres $DB
# 3. provision from zero (applies baseline → legacy migs → 32 ensures → migrate → import-schema → acct → seed)
DB_HOST=127.0.0.1 DB_PORT=55432 DB_USER=postgres DB_PASSWORD=*** DB_NAME=$DB \
  node backend/scripts/db-provision.js            # (baseline step: see B-1 ON_ERROR_STOP handling)
# 4. reference-data top-up for any §3 unseeded tables (hsn_codes/departments/cost_centres) — confirm need first
# 5. unit regression (no DB):           cd backend && npx jest --ci            # expect 256/256
# 6. BUSY reconciliation (fixture):     node tests/busy-mirror.e2e.js          # expect 14/14
# 7. full DB-backed e2e from clean DB:  npm run check    # jest + ~37 e2e scripts (each refuses prod DB names)
# 8. record every failure; classify SETUP/ENV vs APPLICATION DEFECT; compare DB-a vs DB-b for repeatability
```
Safety built in: localhost-only cluster, scratch DB names (suite refuses `dhown_mes`/`vdknits_mes`), no production contact, no BUSY writes.

---

## 8. Outstanding blockers
1. **B-1** `transaction_timeout` vs PG16 + `db-provision.js` `ON_ERROR_STOP` → decide **PG18 scratch** vs **documented load-time filter** before running.
2. **§3 seed gap** — confirm whether `hsn_codes`/`departments`/`cost_centres` reference data is required by the e2e; if so, source a seed (not from the stripped dump's data unless you approve using that data).
3. Final completeness is **unproven until the run** — collisions/column-drift (C) only surface on execution.
4. **Security** (SEC-7/SEC-1) — your actions; not blocking P0-4 but urgent.

## 9. Go / No-Go for P0-4
**Recommendation: CONDITIONAL GO.** The recovered baseline is **safe** (no data/secrets) and **technically suitable**; the dependency model is sound (guarded migrations/ensures, no startup-only objects). Proceeding is gated only on the **operator decisions in §8.1–8.2** (PG version / load-time filter, and the seed-data question) — both documented and non-destructive. The first of the two provisioning runs **is** the verification that surfaces any residual collisions/drift; classify and report, don't paper over.

**No-Go would apply only if** you require provisioning on PG16 without the load-time filter (B-1 makes that fail) or if the seed gap blocks the e2e and no approved seed source exists.

---
**Files changed this step:** `remediation/11_PRE_PROVISIONING_REVIEW.md` (new). Recovered baseline **unchanged**. No execution performed. **Awaiting your review + P0-4 go-ahead.**
