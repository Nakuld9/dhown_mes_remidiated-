# 37 — Final BUSY ↔ MES Transaction Ownership Matrix (Blueprint Freeze)

**Date:** 2026-11-28 · **Branch:** `claude/mes-busy-remediation` · **HEAD:** `2055c94`.
**Documentation only.** No code/schema/migration change; no real BUSY connection; no live writes; no deployment. **No BUSY voucher type, field or API capability is invented** — every BUSY-side specific is marked `PENDING BUSY VENDOR`.

**Evidence labels:** `CONFIRMED BY USER` (this task's business rule) · `CONFIRMED BY SOURCE` (verified in current code, path cited) · `PROPOSED` (design) · `PENDING BUSY VENDOR` (needs the manufacturer's/BUSY vendor's docs or a real export) · `PENDING MGMT` (management approval).

## Frozen business rule `CONFIRMED BY USER`
- BUSY is the **sole accounting/financial** source of truth; MES is the **manufacturing & operational-inventory** source of truth.
- **Purchase vouchers originate in BUSY → MES.**
- **All other approved factory inventory/operational transactions originate in MES → BUSY.**

> **Supersedes** the earlier assumption (doc 22 **D5** and `operational-events.js:24-25`, which model `purchase`/`grn_receipt` as `bidirectional:true`). Under this freeze **purchase is one-way BUSY→MES** and **GRN is MES→BUSY**. The code's current `bidirectional` flags therefore **do not yet match the frozen rule** — a reconciliation item for the future adapter (documented here; **no code changed**). `CONFIRMED BY USER` vs `CONFIRMED BY SOURCE` discrepancy.

## Confirmed integration facts (unchanged) `CONFIRMED BY SOURCE` / `CONFIRMED BY DOC`
- No BUSY public REST API; ACE-OLEDB **read** of the `.bds` validated; **XML/Excel import** is the documented **write** candidate (edition-gated); **direct BUSY DB writes forbidden** (doc 19). The exact importable voucher types/fields/format are **PENDING BUSY VENDOR** — **no real BUSY export has been received or is present in the repo** (verified: no BUSY export/schema file exists).
- MES-side bridge primitives exist: deterministic `external_reference` identity (`backend/src/lib/busy/identity.js`), warehouse-first master mapping with hard-fail (`backend/src/lib/busy/mapping.js`), idempotent queue + `AWAITING_BUSY`/`MANUAL_REVIEW` states + reconciliation + append-only `busy_audit_log` (`backend/src/lib/busy/queue.js`, `schema.js`), flag-OFF capture (`operational-events.js`).
- Master ownership (doc 22): party → **BUSY** (D1); item → MES SKU / BUSY ledger item (D2); warehouse/material-centre → **BUSY authoritative, 1:1, reject unmapped** (D3, built); statutory invoice authoring → **BUSY** (D4); external-party outstanding → **MES authoritative** (D7, built & tested).

## Ownership matrix
Columns: **Origin→Dest** · **MES workflow (source)** · **BUSY voucher (proposed, exact type PENDING VENDOR)** · **Master mappings** · **Inventory impact (MES)** · **Accounting resp.** · **Ext. doc ref** · **Dup prevention** · **Cancel/amend** · **Reconciliation**.

### 1. Purchase — **BUSY → MES** `CONFIRMED BY USER`
- MES workflow: inbound mirror into MES purchase view; PO module `backend/src/routes/purchase-orders.routes.js` `CONFIRMED BY SOURCE`. · BUSY voucher: BUSY purchase voucher (origin) — exact read fields `PENDING BUSY VENDOR` (read via `.bds`/export). · Masters: party (BUSY), item↔SKU, material-centre↔warehouse. · Inventory impact: MES records expected/received stock against the mirrored PO. · Accounting: **BUSY**. · Ext ref: BUSY voucher no. carried as `external_reference` origin=BUSY. · Dup prevention: `UNIQUE(external_reference)` + **circular-sync guard** (BUSY-origin not re-pushed) `CONFIRMED BY SOURCE`. · Cancel/amend: follows BUSY; MES mirrors (D6) `PENDING MGMT`. · Reconcile: mirror vs MES (doc 36 check 1).

### 2. GRN / material receipt — **MES → BUSY** `CONFIRMED BY USER`
- MES workflow: `backend/src/routes/grn.routes.js` (captures `grn_receipt`) `CONFIRMED BY SOURCE`. · BUSY voucher: a goods-receipt/stock-inward voucher `PENDING BUSY VENDOR`. · Masters: party, item, material-centre (hard-fail unmapped). · Inventory: MES increments received stock (authoritative). · Accounting: BUSY records the inward. · Ext ref: `MES:TRANSACTION:<GRN no.>:MATERIAL_RECEIPT`. · Dup: `UNIQUE(external_reference)`. · Cancel/amend: new correlated doc (D6) `PROPOSED`. · Reconcile: queue vs BUSY mirror.

### 3. Material issue (to production / internal) — **MES → BUSY** `CONFIRMED BY USER`
- MES workflow: production/issue flows (`production-entry.routes.js`, lot allocation) `CONFIRMED BY SOURCE (workflow)`; BUSY capture wiring for internal issue **PROPOSED** (not in current `WORKFLOWS`). · BUSY voucher: stock-journal/consumption voucher `PENDING BUSY VENDOR`. · Masters: item, material-centre. · Inventory: MES decrements issued stock. · Accounting: BUSY stock/cost movement. · Ext ref: `MES:TRANSACTION:<issue id>:MATERIAL_ISSUE` `PROPOSED`. · Dup: UNIQUE. · Cancel/amend: new correlated. · Reconcile: shift/stock totals.

### 4. Stock transfer (warehouse→warehouse) — **MES → BUSY** `CONFIRMED BY USER`
- MES workflow: warehouse moves via inventory views/lot allocation `CONFIRMED BY SOURCE (inventory)`; a dedicated transfer workflow + BUSY capture **PROPOSED** (no `stock_transfers` table/route found). · BUSY voucher: material-centre transfer voucher `PENDING BUSY VENDOR`. · Masters: both material-centres. · Inventory: MES moves stock between warehouses. · Accounting: BUSY inter-centre movement. · Ext ref: `MES:TRANSACTION:<transfer id>:STOCK_TRANSFER` `PROPOSED`. · Dup/cancel/reconcile as above.

### 5. Production (roll/finished output) — **MES → BUSY** `CONFIRMED BY USER`
- MES workflow: roll generation + weighing (`backend/src/lib/rolls.js`, `rolls.routes.js`, production-sim) `CONFIRMED BY SOURCE`. · BUSY voucher: production/manufacturing stock-journal `PENDING BUSY VENDOR`. · Masters: item (SKU↔ledger item), material-centre. · Inventory: MES creates finished/greige stock (authoritative; **actual scale weight** primary). · Accounting: BUSY values the output. · Ext ref: `MES:TRANSACTION:<roll_id>:PRODUCTION` `PROPOSED`. · Dup: roll_id/UNIQUE. · Cancel/amend: new correlated. · Reconcile: measured vs counter-estimate, shift totals (doc 36 checks 3/4).

### 6. Sales / dispatch — **MES → BUSY** `CONFIRMED BY USER`
- MES workflow: `backend/src/routes/dispatch.routes.js` (captures `dispatch`) `CONFIRMED BY SOURCE`. · BUSY voucher: **BUSY authors the statutory sales/tax invoice** (D4); MES pushes the **operational dispatch document only** — **dispatch is NOT auto-combined with sales invoicing** `CONFIRMED BY DOC (D4)`; exact import type `PENDING BUSY VENDOR`. · Masters: party (BUSY), item, material-centre. · Inventory: MES decrements dispatched stock. · Accounting: **BUSY** (tax invoice). · Ext ref: `MES:TRANSACTION:<dispatch no.>:DISPATCH`. · Dup: UNIQUE. · Cancel/amend: new correlated (D6). · Reconcile: dispatch vs BUSY invoice link.

### 7. Sales return — **MES → BUSY** `CONFIRMED BY USER`
- MES workflow: `backend/src/lib/returns.js` `CONFIRMED BY SOURCE (lib)`; BUSY capture **PROPOSED**. · BUSY voucher: sales-return / credit-side voucher `PENDING BUSY VENDOR`. · Masters: party, item. · Inventory: MES increments returned stock. · Accounting: BUSY (credit note is **BUSY's** to author — see #9). · Ext ref: `MES:TRANSACTION:<return id>:SALES_RETURN` `PROPOSED`. · Dup/cancel/reconcile as above.

### 8. Purchase return — **MES → BUSY** `CONFIRMED BY USER`
- MES workflow: `returns.js` `CONFIRMED BY SOURCE (lib)`; BUSY capture **PROPOSED**. · BUSY voucher: purchase-return voucher `PENDING BUSY VENDOR`. · Masters: party, item. · Inventory: MES decrements returned-to-vendor stock. · Accounting: BUSY. · Ext ref: `MES:TRANSACTION:<return id>:PURCHASE_RETURN` `PROPOSED`. · Note: the purchase itself is BUSY-origin (#1) — the **return of factory-held goods is an operational outflow**, so MES→BUSY; confirm treatment `PENDING MGMT`.

### 9. Debit / credit notes — **accounting authored in BUSY** `CONFIRMED BY USER` + `CONFIRMED BY DOC (D4)`
- MES workflow: MES may hold an operational basis (`credit-note-pdf.js`) but **financial debit/credit notes are BUSY's to author** (BUSY = accounting SoT). MES→BUSY pushes only the **operational trigger/reference**, not the statutory note. · BUSY voucher: debit/credit note `PENDING BUSY VENDOR`. · Masters: party. · Inventory: usually none (value adjustment). · Accounting: **BUSY**. · Ext ref: correllate to the originating MES doc `PROPOSED`. · Cancel/amend: BUSY mechanism (D6) `PENDING BUSY VENDOR`. · `PENDING MGMT`: confirm MES raises only an operational trigger, never the statutory note.

### 10. Job-work movements — **MES → BUSY** (MES authoritative for quantities) `CONFIRMED BY USER` + `CONFIRMED BY DOC (D7)`
- MES workflow: `backend/src/routes/subcontract.routes.js` (`subcontract_challans` + `subcontract_receipts`), captures `party_issue`/`party_recovery` `CONFIRMED BY SOURCE`. · BUSY voucher: job-work/subcontract material issue & receipt vouchers `PENDING BUSY VENDOR`. · Masters: party (vendor), item/fabric, material-centre. · Inventory: MES tracks sent/received/consumed/wastage/FG and **party-wise outstanding** (authoritative; see doc 39). · Accounting: BUSY records the accounting document. · Ext ref: `MES:TRANSACTION:<challan no.>:PARTY_ISSUE` and `…:PARTY_RECOVERY` (carries `original_ref`) `CONFIRMED BY SOURCE`. · Dup: `UNIQUE(external_reference)`. · Cancel/amend: new correlated. · Reconcile: Σissued−Σrecovered per party (doc 39).

## Unresolved decisions (this document)
- `PENDING BUSY VENDOR`: the **exact importable BUSY voucher type, format and fields** for every MES→BUSY transaction (needs a real export — not yet provided); the exact **read fields** for BUSY-origin purchases; cancellation/amendment mechanism.
- `CONFIRMED BY USER vs code`: `operational-events.js` flags `purchase`/`grn_receipt` as `bidirectional:true`; the freeze makes **purchase BUSY→MES**, **GRN MES→BUSY** — adapter/code reconciliation needed (future task, not now).
- `PROPOSED`/`PENDING MGMT`: BUSY-capture wiring for material issue, stock transfer, production, sales/purchase returns, debit/credit-note triggers (not yet in `WORKFLOWS`); treatment of purchase return direction; confirmation that MES never authors statutory notes.

*Read-only; nothing committed. No BUSY connection, no live write, no invented voucher type/field.*
