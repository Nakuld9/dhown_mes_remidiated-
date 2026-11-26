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
| — | BUSY 21 integration feasibility | 🔄 to re-issue (ACE-OLEDB findings) | `02_BUSY_INTEGRATION_FEASIBILITY.md` |
| — | Approved workflow map (A–F) | ⏳ pending | `03_WORKFLOW_MAP.md` |
| D | Code retirement register | ✅ draft | `04_CODE_RETIREMENT_REGISTER.md` |
| E | Database schema & migration risks | ✅ draft | `05_DATABASE_FINDINGS.md` |
| — | Repeatable clean-DB provision procedure (item 4) | ✅ scaffold (blocked on baseline DDL) | `backend/scripts/db-provision.js` |
| G | Test & build baseline | ✅ done | `06_TEST_BASELINE.md` |
| F | Independent security review (static; runtime pending) | ✅ draft | `07_SECURITY_FINDINGS.md` |
| H | Prioritised remediation backlog | ⏳ pending | `08_REMEDIATION_BACKLOG.md` |
| I | Consolidated findings + implementation plan | ⏳ pending | `09_FINDINGS_AND_PLAN.md` |

Legend: ✅ done · 🔄 in progress · ⏳ pending

## Hard guardrails (do not cross without explicit approval)
- No deletion/disabling of accounting modules.
- No modification or deployment to the original/live MES.
- Never write directly to BUSY's DB.
- Preserve workflows A–F unchanged.
- Security checks: **GET-only, against an isolated scratch DB** — never the live server.

## Change log
- **2026-11-26 (3)** — DB findings (E) + provision runner (item 4): `db-provision.js` reproduces boot order; on empty DB yields 105 tables / 7 fails / acct=0, **proving core-table DDL is missing from source** (`users`, `machines`, `rolls`, `operators`, `machine_live_data`, `app_settings`, `credit_notes`, `sales_returns`, `eway_bills`, …). From-zero build **blocked** pending a `pg_dump --schema-only` baseline (your action).
- **2026-11-26 (2)** — Test & build baseline (G): `npm install` green; **unit 252/252 pass**; 2 self-provisioning e2e suites pass on an isolated scratch Postgres. Found a **reproducibility defect**: no from-zero schema bootstrap (~35 e2e suites can't run headlessly). No live system touched.
- **2026-11-26** — Branch `claude/mes-busy-remediation` created from `a8ef1bb`. Faithful mirror of `main` + `claude/dhown-busy-bridge` pushed & SHA-verified. `server-refractor` excluded (leaked Groq key + stale). Provenance (B), status tracker, and Data Ownership Matrix (C draft) committed.

## Open items awaiting your input
- Make the repo **Private**; rotate the exposed **Groq API key**; (optional) rename repo.
- Confirm the 2026-11-02 "accounting removed" history (reversion vs parallel line) — affects Phase-7 sequencing only.
