# 09 — Consolidated Decision Report (Deliverable I)

**Date:** 2026-11-26 · **For your review before any major implementation.** Everything below is audit output — **no production code changed, nothing deleted/disabled/migrated/deployed; original repo & live DB never touched.**

Full detail in `00`–`08`. This is the decision summary in your six headings.

---

## 1. What is VERIFIED
- **Baseline & copy:** remediated repo = faithful, **SHA-identical** copy of `main @ a8ef1bb` + `busy-bridge @ b379c25`; original untouched. Branch `claude/mes-busy-remediation` cut from `a8ef1bb`. (`00`)
- **System identity:** production-live React + Node/Express + Postgres MES, ~290 endpoints, ~105 provisionable tables, two companies (`dhown_mes`, `vdknits_mes`). (`05`)
- **Tests:** **unit 252/252 green**; BUSY read-bridge reconciliation **14/14** (TB balances to the rupee); `gst-returns` 11/11 — all on an isolated scratch DB. (`06`)
- **BUSY read path is real & validated** (ACE-OLEDB `.bds`, decoded semantics, real-company totals). (`02`)
- **Accounting engine is isolated** from operational flows (only `/api/acct` + a **manual** outbox; `postToLedger` is *costing*, not the GL). (`04`)
- **Security:** parameterised queries predominate; RBAC, JWT revocation, rate-limits, audit logging present; **no secrets committed on `main`**. (`07`)

## 2. What remains UNCERTAIN
- **BUSY write capability** — edition/licence, partner API vs XML/Excel, deployment topology (P2-1). Blocks the write bridge design lock.
- **Full missing-DDL set** — core tables confirmed missing; the complete list needs the `pg_dump --schema-only` baseline (P0-3).
- **Is the MES→GL outbox ever auto-triggered?** (confirms the "isolated accounting" claim). (`04` §5)
- **`backend/frontend/` 80 MB** — duplicate/stale vs the 6.9 MB top-level `frontend/`? Needs sizing. (`04` §5)
- **CFO/AI-Accountant** — keep as read-only analytics over the BUSY mirror, or retire? (business call)
- **43 dynamic-SQL spots** — sampled safe; full manual pass pending. (`07` SEC-5)

## 3. What must be FIXED FIRST (prerequisites)
1. 🔴 **Rotate the exposed Groq key** (public history). *(you)*
2. 🔴 **Remove the hardcoded JWT fallback secret** → fail-closed; rotate prod secret. *(me→you deploy)*
3. 🔴 **Recover the baseline schema** (`pg_dump --schema-only`) → **restore a reproducible, from-zero build + full e2e**. *(you→me)* — **this gates the whole programme**; we cannot safely retire accounting without a testable build.
4. **Make the repo Private.** *(you)*
5. Socket.IO handshake auth; set `DC_API_KEY`. *(me / you)*

## 4. What can SAFELY be RETIRED (now / soon)
- **Now (low-risk, reversible, on your OK):** dead scripts `diag.tmp.js`, `check_sj01.js`, `test_rollid.js` (referenced nowhere); `server-refractor` already excluded.
- **After investigation:** `backend/frontend/` 80 MB if confirmed stale.
- **Only after the bridge is verified + BUSY = sole authority + your approval (NOT now):** in-MES double-entry GL, GST returns, bank/recon, CFO finance, tax-invoice authoring. These **stay running** until then (Condition 1).

## 5. What requires BUSINESS APPROVAL
- Does **BUSY author all statutory invoices** (retire MES `tax-invoices`)?
- Keep **CFO/AI-Accountant** as read-only analytics, or remove?
- **Master source-of-truth** per entity: warehouse/material-centre, party, item (sets sync direction & conflict rules).
- Confirm `/api/acct`, `/api/cfo`, `/api/bank`, GST pages are unused before cutover (your access-log check).
- **BUSY vendor capability** confirmation (edition/API/DOC).

## 6. Proposed IMPLEMENTATION SEQUENCE
```
P0  Prereqs: rotate key · private repo · JWT fail-closed · recover baseline schema
            → GREEN from-zero build + full e2e  ...............  (gate)
P1  Hardening: socket auth · DC_API_KEY · single provisioner · SQL-interp audit
P2  BRIDGE (core): confirm BUSY capability → bridge schema → BusyConnector(+Mock)
            → master mapping (warehouse first) → MES→BUSY DOC write (GRN, party
            issue/recovery, dispatch) → bidirectional Purchase/Receipt
            → reconciliation + monitoring .....................  (verify)
P3  Retirement (post-verify + approvals): dead scripts → stale frontend →
            repoint GL to bridge → stage-retire duplicate accounting
P4  Improvements: central validation · schema-drift reconcile · restore drill
```
**Gating rule:** P2 before P3; P0-3/4 before everything. Workflows A–F unchanged throughout; never write to BUSY's DB; live system untouched.

---

### Immediate asks (so I can proceed)
1. **Rotate the Groq key** and **set the repo Private** (P0-1/2).
2. Provide **`backend/schema/00_baseline_schema.sql`** via `pg_dump --schema-only` of a **staging/restored** DB (not live) (P0-3) — unblocks the reproducible build + full test baseline.
3. Confirm **BUSY edition/licence + integration method** (P2-1).
4. Answer the **business-approval** items in §5.

On your go, I'll start at **P0-5 (JWT fail-closed)** and **P0-4 (complete provisioning once the baseline lands)** — still no retirement, no deployment, pending your review of this report.
