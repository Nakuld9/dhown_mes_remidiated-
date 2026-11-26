# 01 — Data Ownership Matrix (Deliverable C / #4)

**Date:** 2026-11-26 · **Status:** draft for review
**Rule of record:** MES = manufacturing/operations source of truth. BUSY 21 = accounting/finance source of truth. The Bridge owns only the *integration state* between them (never a second copy of either book).

> Ownership below is the **target** state. Per Condition 1, modules currently in
> MES that are tagged **BUSY-OWNED** stay in place and keep running until the
> integration is verified (Condition 2). This matrix says *who should own each
> thing*, not *what to delete today*.

---

## A. Ownership principles

1. **Single writer per fact.** Each data fact has exactly one authoritative system; the other holds a labelled, read-only reflection ("as of / from where").
2. **Physical vs financial split.** Physical stock movement & shop-floor reality = MES. Monetary/GL valuation, statutory books = BUSY.
3. **Masters are mapped, never assumed equal.** Every cross-system reference goes through `busy_master_mapping`; IDs are never presumed identical.
4. **Configurable master ownership + explicit conflicts.** For shared masters (parties, items, warehouses), the owning system is configurable per entity type; a conflict is surfaced for manual review, never silently merged.
5. **Document-origin tracking.** Every synced document records which system created it, a stable integration ID, and the counterpart's returned reference.

---

## B. Ownership matrix

**Legend — Owner:** `MES` · `BUSY` · `BRIDGE` · `SHARED(master)`.
**Dir:** direction of authoritative→reflection flow. **Flag:** remediation disposition.

### B.1 Manufacturing & operations → **MES-owned** (KEEP)

| Domain / entity | Owner | Dir | Current code (on `main`) | Flag |
|---|---|---|---|---|
| Machines, machine config | MES | MES→BUSY (ref only) | `machines.routes`, `machine-settings.routes` | KEEP |
| Rolls, roll lifecycle, labels | MES | internal | `rolls.routes`, `traceability.routes` | KEEP |
| Operators / workforce / shifts | MES | internal | `operators.*`, `attendance.*`, `shift-handovers.*` | KEEP |
| Downtime, OEE, utilization | MES | internal | `downtime.routes`, `analytics.service` | KEEP |
| Quality inspection, defects, complaints | MES | internal | `quality-inspections.*`, `complaints.routes` | KEEP |
| Production, production plans | MES | internal (+stock feed) | `production.*`, `production-plans.routes` | KEEP |
| Knitting structures / library | MES | internal | `knitting-structures.routes` | KEEP |
| Greige / batching / finishing | MES | internal | `greige.*`, `batches.routes`, `finishing.*` | KEEP |
| Maintenance, work orders, spares | MES | internal | `maintenance-*`, `work-orders.*`, `spare-parts.*` | KEEP |
| Shop-floor collectors / firmware | MES | internal | `live-data.routes`, `firmware/` | KEEP |

### B.2 Stock & material movement → **MES-owned physical / BUSY-owned valuation**

| Domain / entity | Owner (physical) | Owner (value/GL) | Current code | Flag |
|---|---|---|---|---|
| Warehouses / **material centres** | **SHARED(master)** — must map 1:1 both ways | — | `erp-masters.routes`, warehouse tables | **KEEP + MAP** (critical: identical mapping both systems, Condition 4) |
| Yarn store / issue / returns / lots (FIFO) | MES | BUSY (inventory GL) | `yarn.*`, `inventory-views.*` | KEEP physical; value→BUSY |
| GRN / material receipt | MES (receipt event) | BUSY (purchase posting) | `grn.*` | **KEEP + BIDIRECTIONAL sync** (Workflow A/B) |
| Material **issue to machine** | MES | — | yarn-issue / WIP | KEEP internal (Condition 6) |
| Finished goods stock | MES | BUSY (FG valuation) | `finished-goods.*`, `finished-entry.*` | KEEP physical |
| Dispatch (challan, physical) | MES | BUSY (voucher) | `dispatch.*` | **KEEP + MES→BUSY** (Workflow F) |
| Subcontract / party issue & recovery | MES (balances) | BUSY (voucher) | `subcontract.*` | **KEEP + MES→BUSY** (Workflows D/E) |
| Costing (FIFO yarn, knitting cost) | MES (operational cost) | BUSY (COGS GL) | `costing.*`, `lib/costing.js` | KEEP operational; GL→BUSY |

### B.3 Accounting & finance → **BUSY-owned** (currently duplicated inside MES → REPLACE later)

| Domain / entity | Owner | Current code (on `main`) | Flag |
|---|---|---|---|
| Chart of accounts, ledgers, groups | BUSY | `lib/busy-bridge.js` (read-mirror) + `lib/accounting/*` | **REPLACE** (keep for now) |
| Double-entry posting / vouchers / journal | BUSY | `lib/accounting/outbox.js`, `mes-posting.js`, `posting-rules.js`, `service.js` | **REPLACE** (keep for now) |
| Trial balance / P&L / Balance Sheet / Cash flow | BUSY | `lib/finance*.js`, `lib/cashflow.js`, `lib/busy-bridge.js` mirror | **REPLACE** (keep for now) |
| Sales / tax invoices (GST) | BUSY | `tax-invoices.*`, `lib/dispatch-invoice.js`, `lib/sales-invoice-ai.js` | **REPLACE** (keep; see note) |
| Purchase invoices | BUSY | `lib/purchase-invoice-ai.js`, `import-busy.js` | **REPLACE** (keep for now) |
| GST returns (GSTR-1/3B/9), ITC | BUSY | `lib/gst-returns.js`, `gstr1.js`, `gstr9.js`, `gst-summary.js`, `gst-json.js` | **REPLACE** (keep for now) |
| TDS | BUSY | (in accounting libs) | **REPLACE** (keep for now) |
| Receipts / payments / bank recon | BUSY | `lib/bank-cashflow.js`, bank mirror | **REPLACE** (keep for now) |
| Customer/supplier **accounting** balances (outstanding) | BUSY | `lib/busy-bridge.js` mirror (`outstanding`) | KEEP as **read-mirror** (correct pattern) |
| Depreciation / interest / loans / budgets | BUSY | `lib/accounting/depreciation.js`, `interest.js`, `budgets.js`, `loans.routes`, `cfo*.js` | **REPLACE / NEEDS-BUSINESS-CONFIRMATION** (CFO decision-support may stay as analytics over BUSY data) |
| AI Accountant | BUSY-derived | `lib/accounting/ai-accountant.js` | **NEEDS-BUSINESS-CONFIRMATION** (analysis layer over BUSY mirror; may stay read-only) |

> **Note on invoices:** your Condition 7 routes party-issue/recovery/dispatch MES→BUSY, and the codebase direction said "NO MES→Busy invoice push." Reconciliation: MES pushes the **operational document** (dispatch/issue); **BUSY generates the statutory tax invoice** and returns its reference. MES does not author tax invoices in the target state → `tax-invoices` becomes REPLACE, pending your confirmation (`NEEDS-BUSINESS-CONFIRMATION`).

### B.4 Integration state → **BRIDGE-owned** (to build; design carried from `busy-bridge` branch)

| Domain / entity | Owner | Target table (from carried-forward design) | Flag |
|---|---|---|---|
| Master cross-mapping (customer/vendor/item/warehouse) | BRIDGE | `busy_master_mapping` | **BUILD** |
| Outbound sync + idempotency + retry | BRIDGE | `busy_sync_queue` (unique `external_reference`) | **BUILD** |
| Integration audit (append-only) | BRIDGE | `busy_audit_log` | **BUILD** |
| Bidirectional reconciliation | BRIDGE | `busy_reconciliation` | **BUILD** |
| Connection health / adapter state | BRIDGE | `busy_connection_state` | **BUILD** |
| BUSY read-mirror (figures for MES visibility) | BRIDGE | existing `busy_*` mirror (`lib/busy-bridge.js`) | **KEEP + extend** |
| Document-reference tracking (BUSY voucher no. ↔ MES txn) | BRIDGE | new column(s) / mapping | **BUILD** |

---

## C. Shared masters & conflict handling

| Master | Proposed owner | Sync | Conflict rule |
|---|---|---|---|
| **Warehouse / material centre** | **SHARED** — mapped 1:1, names/codes must match both systems | BUSY↔MES | Hard-fail import on unmapped centre; no auto-create. |
| Parties (customers/suppliers) | Configurable (default BUSY for accounting identity; MES for operational) | BUSY→MES | Mismatch → `MANUAL_REVIEW` in `busy_master_mapping`. |
| Items / fabric / yarn | Configurable (default MES for SKU; BUSY for ledger item) | MES→BUSY | Mismatch → `MANUAL_REVIEW`; never merge two items. |
| UOM / HSN / tax codes | BUSY (statutory) | BUSY→MES | BUSY authoritative; MES reflects. |

---

## D. Cross-references
- Modules tagged **REPLACE** feed the **Code Retirement Register** (`04_...`) — classified, **not** actioned in Phase 1.
- Workflows A–F detailed in the **Workflow Map** (`03_...`).
- Bridge tables detailed in **BUSY Integration Feasibility** (`02_...`).

## E. Open confirmations (NEEDS-BUSINESS-CONFIRMATION)
1. Does BUSY author **all** tax invoices (so MES `tax-invoices` is retired), or does MES retain invoice authoring for any flow?
2. Do CFO/AI-Accountant analytics **stay** as read-only decision-support over the BUSY mirror, or move entirely into BUSY/BI?
3. Which system owns the **item** master of record, and which owns **party** master of record (sets sync direction)?
