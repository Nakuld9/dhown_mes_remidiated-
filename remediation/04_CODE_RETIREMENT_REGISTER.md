# 04 — Code Retirement Register (Deliverable D / #6)

**Date:** 2026-11-26 · **Status:** draft for review. **Nothing here is actioned.** Per Condition 1, every REPLACE/RETIRE item **stays in place** until the BUSY integration is verified and you approve.

**Disposition classes (brief §6):** `KEEP` · `REFACTOR` · `REPLACE` (moves to BUSY/bridge) · `RETIRE` (obsolete/unused) · `INVESTIGATE`.
**Risk tags:** `CONFIRMED` · `HISTORICAL` · `POTENTIAL-RISK` · `UNUSED-CANDIDATE` · `NEEDS-BUSINESS-CONFIRMATION`.

> **Golden rule applied:** nothing is marked RETIRE on "no import" alone — wiring,
> dynamic requires, routes, the outbox, scheduled jobs and DB refs were checked.

---

## 0. Key structural facts that shape every disposition

1. **Two different "ledgers" — do not conflate:**
   - `src/lib/costing.js :: postToLedger()` = an **inventory / cost-movement** sub-ledger (operational; passed to `grn`/`yarn`/`subcontract`/`rolls`; 33 call-sites). → **KEEP.**
   - `src/lib/accounting/*` = the **double-entry financial GL** (vouchers, periods, TB). → **REPLACE** (BUSY owns this).
2. **The duplicate accounting engine is relatively ISOLATED.** `lib/accounting/*` is required only by `server.js` + `src/routes/accounting.routes.js`; operational routes do **not** call it directly. Its MES→GL outbox is **manually triggered** (`POST /api/acct/link/mes/outbox/:oid/process`) — **no running worker**. → retirement is cleaner than feared, but confirm no hidden trigger (INVESTIGATE).
3. **BUSY read-mirror already exists and is the correct pattern** (`lib/busy-bridge.js`) → KEEP + extend, don't retire.

---

## 1. KEEP — MES operational core (no change)

| Area | Files / routes | Notes |
|---|---|---|
| Production, rolls, machines, operators, shifts, downtime | `rolls/machines/operators/downtime/production*.routes`, firmware | Workflows C, B-internal |
| Quality, traceability, greige, batching, finishing | `quality-inspections/traceability/greige/batches/finishing.*` | — |
| Maintenance, work orders, spares, knitting library | `maintenance-*/work-orders/spare-parts/knitting-structures.*` | — |
| **Costing (operational)** | `src/lib/costing.js`, `costing.routes`, `addCostEntry`, `postToLedger` (inventory) | FIFO/knitting cost — stays in MES |
| Physical stock & movement | `yarn/grn/dispatch/subcontract/inventory-views.*` (physical side) | Financial posting moves to BUSY; physical stays |
| Dashboards, masters, imports (control tower ops) | `dashboard/erp-masters/imports.*` | — |

## 2. REFACTOR — useful, but reshape for the bridge

| Item | Files | Action | Tag |
|---|---|---|---|
| BUSY read-mirror | `lib/busy-bridge.js`, `busy-reconcile.js`, `busy-production.js` | Extend into the proper **read side** of the API/DOC bridge; keep "labelled, read-only, as-of" pattern | POTENTIAL-RISK (low) |
| MES→BUSY CSV feed | `busy-sync.routes/service/repository` | Evolve the GRN/Dispatch CSV into the **validated DOC-bridge export** with master-mapping + document-ref tracking | POTENTIAL-RISK |
| Bridge-state tables | *(to add)* from `migration_phase11_busy_bridge.sql` design | Implement `busy_master_mapping/sync_queue/audit/reconciliation/connection_state` as **proper migrations** | — |
| MES→GL coupling point | `lib/accounting/outbox.js`, `mes-events.js`, `ops-link.js` | Repoint operational events from the in-MES GL to the **bridge outbox** (so BUSY posts) — the hinge of Phase-7 | NEEDS-BUSINESS-CONFIRMATION |

## 3. REPLACE — functionality that becomes BUSY's (KEEP running until bridge verified)

| Domain | Files / routes | Why | Tag |
|---|---|---|---|
| Double-entry GL / vouchers / periods / TB | `lib/accounting/{service,outbox,mes-posting,posting-rules,documents,allocations,stock-valuation,depreciation,interest}.js`, `accounting.routes` (`/api/acct`) | BUSY is the statutory book | NEEDS-BUSINESS-CONFIRMATION |
| GST returns & registers | `lib/{gst-returns,gstr1,gstr9,gst-summary,gst-json}.js` | BUSY files GST | REPLACE |
| Tax/sales invoices | `tax-invoices.*`, `lib/{dispatch-invoice,sales-invoice-ai,purchase-invoice-ai}.js` | BUSY issues statutory invoices; MES pushes the **operational** doc only | NEEDS-BUSINESS-CONFIRMATION |
| Banking / receipts / payments / recon | `bank.routes`, `lib/bank-cashflow.js`, bank-recon schema | BUSY owns cash & bank | REPLACE |
| CFO suite | `{loans,budgets,cashflow,profitability,cfo}.routes`, `lib/{cfo-analytics,cfo-dashboard,budgets,cashflow,finance,finance-report}.js` | Statutory finance = BUSY | NEEDS-BUSINESS-CONFIRMATION (decision-support *analytics over the BUSY mirror* may stay read-only) |
| AI Accountant | `lib/accounting/ai-accountant.js`, `ai/tools/finance.tools.js` | Analysis over BUSY data | NEEDS-BUSINESS-CONFIRMATION |

> **Sequencing note:** none of §3 can be retired until (a) the bridge is live & reconciling, (b) BUSY is confirmed sole authority (Condition 2), and (c) the `/api/acct` + CFO pages are proven unused or migrated. Retirement = a later, staged, reversible phase — **not now.**

## 4. RETIRE — obsolete / unused (safe candidates, still pending approval)

| Item | Evidence | Tag |
|---|---|---|
| `backend/diag.tmp.js` | referenced by nothing; name = temp diagnostic | UNUSED-CANDIDATE |
| `backend/check_sj01.js` | referenced by nothing; one-off machine check | UNUSED-CANDIDATE |
| `backend/test_rollid.js` | referenced by nothing; ad-hoc script (not in `test/` or `tests/`) | UNUSED-CANDIDATE |
| `server-refractor` branch | leaked key + stale (already excluded from the copy) | HISTORICAL |

> Even these "safe" deletes wait for your go — they're low-risk cleanups, batched and reversible (git).

## 5. INVESTIGATE — uncertain, needs a closer pass

| Question | Where | Why it matters |
|---|---|---|
| Is the MES→GL outbox ever auto-triggered? | `lib/accounting/outbox.js`, any scheduler/webhook | If a job/webhook calls it, retirement coupling is larger than it looks |
| Does any operational flow create a GL voucher directly? | dispatch/grn/subcontract → `lib/accounting` | Confirms isolation claim (§0.2) |
| `backend/frontend/` (80 MB) vs top-level `frontend/` (6.9 MB) | repo root | Duplicate/stale built frontend? Likely large RETIRE candidate — size it before acting |
| `lib/import-busy.js`, `import-costing.js`, `lib/accounting/migration.js` | import/migration libs | One-time migration helpers vs live paths |
| CFO analytics: read-only over BUSY, or recomputing books? | `lib/cfo-*.js` | Decides REPLACE vs KEEP-as-analytics |

## 6. Hard dependencies to preserve during any later retirement
- Operational `postToLedger`/`addCostEntry` (costing) — **not** the GL; keep.
- The `busy_*` read-mirror and `ACCT_TEST_DB` prod-name guard.
- Historical accounting & production **data** (never drop tables with history without export).
- Workflows A–F behaviour.

## 7. Open confirmations (NEEDS-BUSINESS-CONFIRMATION)
1. Does BUSY author **all** statutory invoices (retire MES `tax-invoices`)? 
2. Keep CFO/AI-Accountant as **read-only analytics** over the BUSY mirror, or remove entirely?
3. Confirm `/api/acct`, `/api/cfo`, `/api/bank`, GST pages are safe to retire after cutover (usage check against access logs — your side).
