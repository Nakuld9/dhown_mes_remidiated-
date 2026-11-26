# 03 — Approved Factory Workflow Map (Deliverable #3)

**Date:** 2026-11-26 · Maps your approved workflows A–F to the current MES code and the required integration direction. **These workflows must not change** (Conditions 3–7). This is a map of *what exists* and *what the bridge adds* — not a redesign.

**Integration legend:** `↔` bidirectional · `→BUSY` MES pushes · `BUSY→` BUSY pushes · `internal` MES-only.

---

| # | Workflow | Direction | MES modules (current) | Bridge work needed |
|---|---|---|---|---|
| **A** | **Purchase + material receipt** | **↔** (updated) | `grn.*` (receipt), `purchase-orders.*`, `erp-masters` (warehouse), `busy-sync` (GRN CSV) | **Bidirectional:** BUSY→ purchase/receipt docs + posting status + **warehouse/material-centre master**; MES→ receipt doc; store BUSY ref; 1:1 warehouse mapping; dup-prevention |
| **B** | **Material receipt into same warehouse/material centre** | BUSY→ then internal | `grn.*`, warehouse master, `inventory-views` | **Exact warehouse/material-centre mapping both systems** (hard-fail unmapped). Preserve item/qty/unit/supplier/doc refs |
| **C** | **Material issue to machine** | **internal** | yarn issue→WIP, `rolls`, `production.*`, `costing` (`postToLedger` inventory) | None (stays MES). Condition 6 |
| **D** | **Shift-wise production** | **internal** | `production*.routes`, `rolls`, `downtime`, operators/shifts, `quality-inspections` | None (stays MES). Roll gen / downtime / quality / reports preserved |
| **E** | **Material issue to party** | **→BUSY** | `subcontract.*` (challans, party ledger balances) | MES→ issue txn → BUSY; return + store doc ref; party-wise issued qty; original refs traceable |
| **F** | **Material recovery from party** | **→BUSY** | `subcontract.*` (receipts, wastage, chaining) | MES→ recovery txn → BUSY; maintain issued/recovered/outstanding **party-wise**; trace to original issue |
| **G** | **Dispatch** | **→BUSY** | `dispatch.*` (challan, pricing, packing), `busy-sync` (dispatch CSV) | MES→ dispatch doc → BUSY; return + store voucher ref; track sync success. **Dispatch ≠ sales invoice** (keep separate unless approved) |

> Note: your list labels Party issue/recovery/Dispatch as D/E/F; the MES implements party issue/recovery inside the **subcontract** module and dispatch in the **dispatch** module. Numbering above follows the workflow letters in your brief (A–F) with production split out.

## Source-of-truth per workflow
- **Physical movement, production, party balances** → **MES** (authoritative).
- **Accounting postings, vouchers, statutory invoice, GST** → **BUSY** (authoritative).
- **The document reference** that ties them → stored in the **bridge** (`busy_sync_queue.busy_reference` / mapping).

## What already works vs what the bridge must add
- **Works now:** all A–G exist operationally in MES; GRN + Dispatch already export to BUSY-import **CSV**; BUSY figures already mirror into MES (read bridge).
- **Must add (bridge):** master-mapping (esp. warehouse/material-centre), idempotent queue, document-origin + integration IDs, returned-reference storage, bidirectional reconciliation, duplicate/conflict detection — i.e. upgrade the CSV/mirror into the robust API & DOC bridge.

## Invariants to preserve (do not regress)
- Roll generation, downtime, quality, production reporting (D).
- Warehouse/material-centre identity across both systems (A/B).
- Party-wise issued/recovered/outstanding with traceability to the original issue (E/F).
- Dispatch and sales invoicing remain **separate** unless you explicitly combine them.
