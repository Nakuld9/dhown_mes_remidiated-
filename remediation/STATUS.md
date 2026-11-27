# Remediation — Status & Change Log

**Branch:** `claude/mes-busy-remediation` (from `main @ a8ef1bb`)
**Last updated:** 2026-11-26

> Living tracker for the DHOWN MES ↔ BUSY 21 remediation. Phase-1 is **audit only** —
> no production code is modified, nothing is deleted, nothing is deployed.

## Phase-1 deliverables (audit)

| ID | Deliverable | Status | File |
|---|---|---|---|
| A | Remediation branch from `a8ef1bb` | ✅ done | — |
| B | Baseline commit + provenance recorded | ✅ done | `00_BASELINE_AND_PROVENANCE.md` |
| — | Branch comparison report | ✅ done | delivered for approval (pre-branch) |
| — | Faithful copy + SHA verification (Deliv. #1) | ✅ done | `00_BASELINE_AND_PROVENANCE.md` |
| C | Data ownership matrix | ✅ draft | `01_DATA_OWNERSHIP_MATRIX.md` |
| — | BUSY 21 integration feasibility (#5) | ✅ done | `02_BUSY_INTEGRATION_FEASIBILITY.md` |
| — | Approved workflow map (A–F) (#3) | ✅ done | `03_WORKFLOW_MAP.md` |
| D | Code retirement register | ✅ draft | `04_CODE_RETIREMENT_REGISTER.md` |
| E | Database schema & migration risks | ✅ draft | `05_DATABASE_FINDINGS.md` |
| — | Repeatable clean-DB provision procedure (item 4) | ✅ scaffold (blocked on baseline DDL) | `backend/scripts/db-provision.js` |
| G | Test & build baseline | ✅ done | `06_TEST_BASELINE.md` |
| F | Independent security review (static; runtime pending) | ✅ draft | `07_SECURITY_FINDINGS.md` |
| H | Prioritised remediation backlog (#10) | ✅ done | `08_REMEDIATION_BACKLOG.md` |
| I | Consolidated findings + decision report | ✅ done | `09_FINDINGS_AND_PLAN.md` |

**Phase-1 audit COMPLETE — awaiting your review before any implementation.**

Legend: ✅ done · 🔄 in progress · ⏳ pending

## Hard guardrails (do not cross without explicit approval)
- No deletion/disabling of accounting modules.
- No modification or deployment to the original/live MES.
- Never write directly to BUSY's DB.
- Preserve workflows A–F unchanged.
- Security checks: **GET-only, against an isolated scratch DB** — never the live server.

## Change log
- **2026-11-27 — Phase 1.5 hardening COMPLETE** (`13_PHASE_1_5_HARDENING_REPORT.md`, code `07c3795`). All 9 leftover e2e items fixed with no weakened assertions: finished-entry (recovered missing `roll_id` column + unit tests), reports-extra/sales-role (real local server), wa-webhook-ai (Groq **mocked**, labeled), accounting/allocation/dispatch-invoice/matrix-valuation (deterministic fixtures), medium-batch (by-design exemptions). Deeper fixes: **outbox concurrency** lost-race recovery, **~13 boot provisioners** added to db-provision (→180 tables), **openai** declared. **Regression on two fresh PG18.7 DBs: 71 OK/0 FAIL provision, unit 262/262, BUSY 14/14, e2e 46/46 on both, structure IDENTICAL.** Baseline unchanged. Phase 2 NOT started — awaiting approval.
- **2026-11-26 (9)** — **P0-4 executed & verified** (`12_P0_PROVISIONING_VERIFICATION_REPORT.md`). PostgreSQL **18.7**; recovered baseline applied **unmodified**. **Two independent scratch DBs provisioned from zero: 57 OK / 0 FAIL each, 158 public + 22 acct tables, byte-identical (column md5 match).** Deterministic in-source seed only (no prod data). **Unit 256/256 ✓, BUSY 14/14 ✓, DB-backed e2e 37/46 on both** (identical fails: 3 need app-server/external keys, 4 need extra seed/config, 1 app-robustness, 1 by-design — **none a baseline/schema defect**). **Fixed** a provision-script gap (`db-provision.js` omitted `seedDefaultAdmin`). Baseline UNCHANGED. **Phase 2 NOT started — awaiting approval.**
- **2026-11-26 (8)** — Pre-provisioning review (`11_PRE_PROVISIONING_REVIEW.md`, no execution): baseline **integrity verified** (63/55/39 objects; **no data/secrets** — `\restrict` token is a dump nonce, not a credential). **PG16 compat BLOCKER B-1:** `SET transaction_timeout` is PG17+ (+`\restrict` meta-cmds) → run on PG18 or filter at load; never edit the recovered file. Dependency model sound (migrations/ensures guarded; no startup-only objects); **seed gap:** `hsn_codes`/`departments`/`cost_centres` possibly unseeded. **SEC-7:** 4 prod dumps (password hashes + PII) in public `server-refractor`, all in commit `dec5183` (same as SEC-1 Groq key). **Go/No-Go: CONDITIONAL GO** for P0-4. No DB created, no SQL run.
- **2026-11-26 (7)** — **Schema recovery (Outcome 1).** Recovered the genuine foundational schema from a real `pg_dump` (`server-refractor@8f257f3:backend/backups/dhown_mes_2026-07-05.sql`, PostgreSQL 18.4) — it contains all **18 foundational tables no source file creates**. Prepared **PROPOSED** `backend/schema/00_baseline_schema.sql` (schema-only, data-stripped, verified 0 rows, 63 tables) + `10_SCHEMA_RECOVERY_REPORT.md`. **NEW 🔴 SEC-7:** full production DB dumps with data (password hashes) committed in the PUBLIC `server-refractor` branch. **No provisioning run.** Awaiting baseline review/approval before P0-4.
- **2026-11-26 (6)** — Documentation only (P0-4 on hold): added `backend/scripts/README.md` recording `db-provision.js`'s **expected** execution order, explicitly marked **UNVALIDATED / not production-ready / blocked on the missing `schema/00_baseline_schema.sql`**. No script run, no scratch DB created, no code behaviour changed.
- **2026-11-26 (5)** — **Implementation (authorised: security containment only).** JWT fail-closed fix (SEC-2 / backlog P0-5): `src/middleware/auth.js` no longer falls back to a built-in secret — it throws if `JWT_SECRET` is missing/empty and refuses the former public value. Added `test/jwt-fail-closed.test.js` (4 tests) + `test/jest.setup.js` (test-only secret) + jest `setupFiles`. Regression: **unit 256/256** (252 baseline + 4 new), **BUSY reconciliation 14/14**. No other behaviour changed; no deploy; prod `JWT_SECRET` still needs rotating by you.
- **2026-11-26 (4)** — Phase-1 audit completed: code-retirement register (D), security review (F), BUSY feasibility (02), workflow map (03), prioritised backlog (H), consolidated decision report (I). No code changed; awaiting review.
- **2026-11-26 (3)** — DB findings (E) + provision runner (item 4): `db-provision.js` reproduces boot order; on empty DB yields 105 tables / 7 fails / acct=0, **proving core-table DDL is missing from source** (`users`, `machines`, `rolls`, `operators`, `machine_live_data`, `app_settings`, `credit_notes`, `sales_returns`, `eway_bills`, …). From-zero build **blocked** pending a `pg_dump --schema-only` baseline (your action).
- **2026-11-26 (2)** — Test & build baseline (G): `npm install` green; **unit 252/252 pass**; 2 self-provisioning e2e suites pass on an isolated scratch Postgres. Found a **reproducibility defect**: no from-zero schema bootstrap (~35 e2e suites can't run headlessly). No live system touched.
- **2026-11-26** — Branch `claude/mes-busy-remediation` created from `a8ef1bb`. Faithful mirror of `main` + `claude/dhown-busy-bridge` pushed & SHA-verified. `server-refractor` excluded (leaked Groq key + stale). Provenance (B), status tracker, and Data Ownership Matrix (C draft) committed.

## Open items awaiting your input
- Make the repo **Private**; rotate the exposed **Groq API key**; (optional) rename repo.
- Confirm the 2026-11-02 "accounting removed" history (reversion vs parallel line) — affects Phase-7 sequencing only.
