# 08 — Prioritised Remediation Backlog (Deliverable H / #10)

**Date:** 2026-11-26 · Ordered by dependency + risk. **Nothing here is implemented** — awaiting your review (Conditions: no delete/disable/migrate/deploy yet).

**Class:** `DEFECT-FIX` · `SECURITY` · `PREREQUISITE` · `BRIDGE` · `RETIRE` · `IMPROVEMENT`. **Owner:** 🧑 you · 🤖 me.

---

## P0 — Urgent / prerequisite (block everything else)

| ID | Item | Class | Owner | Depends on |
|---|---|---|---|---|
| P0-1 | **Rotate the exposed Groq API key** (public history) | SECURITY | 🧑 | — |
| P0-2 | **Make `dhown_mes_remidiated-` Private** (+ rename to `DHOWN_MES_REMEDIATED`) | SECURITY | 🧑 | — |
| P0-3 | **Recover baseline schema** `pg_dump --schema-only` (staging) → `backend/schema/00_baseline_schema.sql` | PREREQUISITE | 🧑→🤖 | — |
| P0-4 | Complete `db-provision.js` from baseline → **green from-zero build**; run full e2e | PREREQUISITE | 🤖 | P0-3 |
| P0-5 | **Remove hardcoded JWT fallback** → fail-closed; rotate prod `JWT_SECRET` | SECURITY/DEFECT | 🤖 build → 🧑 deploy | — |

## P1 — Reliability & security hardening

| ID | Item | Class | Owner | Depends on |
|---|---|---|---|---|
| P1-1 | Socket.IO: authenticate handshake + origin allowlist (SEC-3) | SECURITY | 🤖 | P0-4 (verify) |
| P1-2 | Set `DC_API_KEY` in prod; keep `:8090`/`:5432` LAN-only (SEC-4) | SECURITY | 🧑 | — |
| P1-3 | Converge on a single idempotent provisioner; keep runner for increments (F-DB-2) | DEFECT-FIX | 🤖 | P0-4 |
| P1-4 | Manual review of all 43 dynamic-SQL interpolations + lint rule (SEC-5) | SECURITY | 🤖 | — |
| P1-5 | Runtime GET-only security verification on scratch instance (SEC-2/3/4) | SECURITY | 🤖 | P0-4 |

## P2 — Build the API & DOC Bridge (the core project)

| ID | Item | Class | Owner | Depends on |
|---|---|---|---|---|
| P2-1 | **Confirm BUSY vendor capability** (edition/version/licence; API vs XML/Excel; deployment) | BRIDGE | 🧑 | — |
| P2-2 | Bridge-state schema as proper migrations (mapping/queue/audit/recon/connection) from phase-11 design | BRIDGE | 🤖 | P0-4 |
| P2-3 | `BusyConnector` interface + `MockBusyConnector` (default) + productionise `AceOledbReadConnector` | BRIDGE | 🤖 | P2-2 |
| P2-4 | **Master mapping — warehouse/material-centre first** (1:1, hard-fail unmapped), then party/item | BRIDGE | 🤖 | P2-2 |
| P2-5 | MES→BUSY **DOC write** (XML/Excel) for GRN, party issue/recovery, dispatch; idempotent; store returned ref | BRIDGE | 🤖 | P2-1,P2-3,P2-4 |
| P2-6 | Bidirectional Purchase/Receipt (BUSY→ posting status; document-origin + conflict handling) | BRIDGE | 🤖 | P2-5 |
| P2-7 | Reconciliation + integration monitoring dashboard | BRIDGE | 🤖 | P2-5 |

## P3 — Retirement (only after bridge verified + your approval)

| ID | Item | Class | Owner | Depends on |
|---|---|---|---|---|
| P3-1 | Retire dead scripts (`diag.tmp.js`, `check_sj01.js`, `test_rollid.js`) — low-risk, reversible | RETIRE | 🤖 | your OK |
| P3-2 | Investigate `backend/frontend/` 80 MB (duplicate/stale?) → size & retire if dead | RETIRE | 🤖 | — |
| P3-3 | Repoint operational events from in-MES GL outbox → bridge (BUSY posts) | BRIDGE/RETIRE | 🤖 | P2-6 verified |
| P3-4 | Stage-retire duplicate accounting (GL/GST/bank/CFO/tax-invoices) **after** BUSY = sole authority | RETIRE | 🤖 | P3-3 + approvals |

## P4 — Improvements

| ID | Item | Class |
|---|---|---|
| P4-1 | Central request validation (esp. bridge write routes) (SEC-6) | IMPROVEMENT |
| P4-2 | Reconcile two-company schema drift (`dhown_mes` vs `vdknits_mes`) | IMPROVEMENT |
| P4-3 | Backup **restore drill** verification | IMPROVEMENT |

---

**Rule:** P3 cannot start until P2 is verified (bridge live + reconciling) and you confirm BUSY is the sole authority (Condition 2). P0-3/P0-4 gate the whole programme — without a reproducible build we cannot safely change accounting code.
