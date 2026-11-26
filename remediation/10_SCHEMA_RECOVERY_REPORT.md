# 10 — Original-Repository Schema Recovery Report

**Date:** 2026-11-26 · Branch `claude/mes-busy-remediation`. **Read-only investigation of the original repo; nothing in the original modified; no provisioning run; no production contact.**

**Outcome: ✅ Outcome 1 — a genuine, verifiable schema source was recovered** (an actual `pg_dump`, not invented DDL), with explicit limits requiring the approval-gated verification run to confirm completeness.

---

## 1. Original repository — branches & commits inspected
`ls-remote` on `github.com/Nakuld9/DHOWN_LIVE_PRODUCTION_DASHBOARD` → exactly **3 branches, no tags**:
| Branch | HEAD | Commits | `backend/server.js` | Notes |
|---|---|---|---|---|
| `main` | `a8ef1bb` | **1** (squashed "clean snapshot, no history") | 1,150 lines (refactored) | DDL extracted into `ensureXxxSchema()` |
| `server-refractor` | `8f257f3` | **8** | **9,053 lines (monolith)** | **Holds `backend/backups/*.sql` pg_dumps** |
| `claude/dhown-busy-bridge-5whntb` | `b379c25` | 2 | 3,810 lines | phase-11 bridge design |

## 2. Files & history examined
- `server.js` on all three branches (sizes above). **Even the 9,053-line monolith creates only ONE table in code** (`production_history`) — the core tables are created by **no source file on any branch**.
- All `.sql` across branches: `backend/migrations/knitting_structures.sql`, `migration_phase8/9/10*.sql`, `ha/setup-primary.sql`, and — decisively — **`backend/backups/dhown_mes_2026-07-01/02/03/05.sql`** (in `server-refractor`).
- `src/db/schema.js` (32 `ensureXxxSchema`), legacy `migration_*.js`, `src/lib/accounting/schema.js`.

## 3. Foundational tables recovered
The July-5 `pg_dump` contains **all 18 foundational tables that NO source file creates**:
`users, machines, operators, rolls, rfid_events, machine_status_log, machine_downtime, machine_live_data, app_settings, audit_logs, data_collectors, fabric_types, maintenance_records, oee_records, operator_assignments, production_records, subcontract_challan_items, subcontract_receipt_items`
— plus 45 more (63 total) that source can also build. **The 18 are the genuine irreducible recovery value.**

## 4. Accounting schema (`acct`) findings
The dump is **`public`-schema only** — **0** `CREATE SCHEMA acct` / `acct.` references. The `acct` schema (double-entry GL) did not exist at the July snapshot and is created at runtime by `src/lib/accounting/schema.js :: ensureAccountingSchema()`. **So the baseline does not and should not contain `acct`; source provisions it.** (The earlier "7 post-July tables" — `credit_notes`, `sales_returns`, `eway_bills`, `lot_allocations`, etc. — ARE created in `src/db/schema.js`; their earlier failures were FK **ordering**, not missing DDL.)

## 5. Missing / residual database objects
- **None irreducibly missing** for the foundational layer — the 18 are recovered.
- **To confirm only via the approval-gated verification run:** (a) July table definitions vs current post-July `ALTER`s (reconciled by `ADD COLUMN IF NOT EXISTS` ensures); (b) possible constraint/index **name collisions** between the baseline and the ensures; (c) that baseline + legacy migrations + ensures converge to the full current schema with the e2e green.
- Extensions: **0** required (dump has none). Owners: all `postgres` (portable). 1 trigger fn (`update_updated_at_column`) + 1 trigger.

## 6. Provenance of recovered definitions
| | |
|---|---|
| Object source | `backend/backups/dhown_mes_2026-07-05.sql` |
| Original repo | `Nakuld9/DHOWN_LIVE_PRODUCTION_DASHBOARD` |
| Branch @ commit | `server-refractor` @ `8f257f362a8854706a7a8b01ce0c2df38a3652b5` |
| Tooling | `pg_dump` 18.4 · server PostgreSQL **18.4** |
| Dump date | 2026-07-05 (latest of 4; 07-01/02/03 are earlier/smaller) |
| Scrub | all `COPY`/data + `\.` + `INSERT` removed — **verified 0 data rows**; 63 tables / 55 sequences / 39 indexes / 278 ALTERs / 1 fn / 1 trigger retained; no literal secrets |

Proposed file: **`backend/schema/00_baseline_schema.sql`** (header records all of the above).

## 7. Can a complete baseline genuinely be produced?
**Yes — genuinely, for the foundational schema.** The full *current* schema is reproducible as **baseline (July, recovered) + committed legacy migrations + `ensureXxxSchema()`** — all of which exist in source. **Final completeness is not yet proven**; it must be verified by the P0-4 run (two clean DBs + full e2e). This is recovery of a real schema, not a plausible-looking file.

## 8. 🔴 SEC-7 (NEW, urgent) — production DB dumps with data in a PUBLIC branch — `CONFIRMED`
`server-refractor` commits **four full `pg_dump` files WITH DATA** (`dhown_mes_2026-07-01…07-05.sql`, 63 `COPY` blocks each). The original repo is **public**, so **production rows — including `users` password hashes and whatever lived in `app_settings` — are publicly exposed in git history.** (Same branch also holds the leaked Groq key, SEC-1.)
**Actions (yours):** make the original repo **Private** and/or **purge `backend/backups/` from its history**; **rotate** any credential whose value sat in those dumps (user passwords, any keys stored in settings). The remediation copy already **excluded** `server-refractor`, so none of this data was copied here (only the scrubbed, data-free schema was).

## 9. Recommended next action
1. **Review the proposed `backend/schema/00_baseline_schema.sql`** (provenance + scrub in its header).
2. On approval → run **P0-4**: `db-provision.js` on **two** empty scratch DBs → full DB-backed e2e → preserve unit 256/256 + BUSY 14/14 → classify every failure (setup vs defect) → report. This verifies §5/§7 completeness.
3. Address **SEC-7** (public data dumps) and **SEC-1** (Groq key) on the original repo.
4. *(Optional, reduces §5 uncertainty)* if a **current** staging schema-only dump is easy to produce, it would need less layering than the July baseline — but is **not required**, since the layering lives in source.

## Files changed (this step)
- **NEW** `backend/schema/00_baseline_schema.sql` — proposed, scrubbed, pending review.
- **NEW** `remediation/10_SCHEMA_RECOVERY_REPORT.md` — this report.
- Commit hash: recorded on commit (below in chat).

**Stopping here for your review. No provisioning will run until you approve the baseline.**
