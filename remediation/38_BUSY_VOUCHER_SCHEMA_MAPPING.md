# 38 — BUSY Voucher Schema Mapping (Template — pending real export)

**Date:** 2026-11-28 · **Branch:** `claude/mes-busy-remediation` · **HEAD:** `2055c94`.
**Documentation only.** No code/schema/migration change; no BUSY connection; no live write. **No BUSY voucher field, tag, type or format is invented.** No actual financial or party values appear here.

## ⚠ Status of the actual BUSY schema
**No real BUSY XML/DAT/Excel export exists in the repository** (verified: no such file is committed or uploaded). The sample exports needed to resolve this were requested from the user (Purchase, GRN/receipt, Dispatch/Sales vouchers + a master export + BUSY edition). **Until they arrive, every BUSY-side field below is `PENDING BUSY VENDOR` and is shown only as a placeholder `‹busy:…›`.** This document is a **mapping template**: the left (MES source) side is `CONFIRMED BY SOURCE`; the right (BUSY target) side is filled **only** from a real export.

**Labels:** `CONFIRMED BY SOURCE` (MES field verified in code) · `PENDING BUSY VENDOR` (BUSY field/type — awaiting a real export) · `CONFIRMED BY DOC` (doc 19/22 fact) · `PENDING MGMT`.

## Confirmed MES→BUSY envelope primitives `CONFIRMED BY SOURCE`
These wrap every voucher regardless of type and are already built:
- `external_reference` — deterministic key `‹origin›:TRANSACTION:‹mes_doc_id›:‹OPERATION›` (`backend/src/lib/busy/identity.js`); carries `document_origin` (`MES`|`BUSY`).
- Master mapping via `busy_master_mapping` — party / item / **material-centre (1:1, hard-fail unmapped)** (`backend/src/lib/busy/mapping.js`, doc 22 D1/D2/D3).
- Queue states incl. `AWAITING_BUSY`, `MANUAL_REVIEW`, retry/backoff; append-only `busy_audit_log` (`backend/src/lib/busy/queue.js`, `schema.js`).
- Write mechanism candidate: render a validated **XML/Excel** import file; BUSY posts on import; voucher no. read back via the read adapter (doc 21) — **format/type `PENDING BUSY VENDOR`**.

## Mapping template (per voucher)
> The BUSY column stays `‹busy:…›` until a real export is parsed. Field **names/tags are illustrative placeholders**, not claims about BUSY's actual schema.

### Common header (all vouchers)
| MES source field | Source (confirmed) | → BUSY target | Status |
|---|---|---|---|
| document number (`roll_id` / GRN no. / challan no. / dispatch no.) | `rolls`, `grn`, `subcontract_challans`, dispatch route | `‹busy:voucher_ref_field›` | `PENDING BUSY VENDOR` (which field carries our ref) |
| voucher date | MES doc timestamp | `‹busy:voucher_date›` (open FY period) | `PENDING BUSY VENDOR` |
| party | `busy_master_mapping` (BUSY-authoritative) | `‹busy:ledger_name›` (must pre-exist) | `PENDING BUSY VENDOR` |
| warehouse/material-centre | mapping, 1:1 hard-fail | `‹busy:material_centre_code›` | `PENDING BUSY VENDOR` |
| item / SKU | mapping (SKU↔ledger item) | `‹busy:item_code›` | `PENDING BUSY VENDOR` |
| our integration reference | `external_reference` (`identity.js`) | `‹busy:narration_or_ref›` | `PENDING BUSY VENDOR` (which field is readable back) |

### Purchase (BUSY → MES, read) `CONFIRMED BY USER` direction
| BUSY source field | → MES target | Status |
|---|---|---|
| `‹busy:purchase_voucher_no›` | MES purchase mirror doc id | `PENDING BUSY VENDOR` |
| `‹busy:party/item/qty/value›` | MES purchase line (operational) | `PENDING BUSY VENDOR` |
> Read via ACE-OLEDB `.bds` or an export; exact tables/columns `PENDING BUSY VENDOR` (doc 20 §5 unknowns).

### GRN / material receipt (MES → BUSY)
| MES field (confirmed: `grn.routes.js`) | → BUSY | Status |
|---|---|---|
| GRN no., received qty/weight, party, item, warehouse | `‹busy:goods_inward_voucher.*›` | `PENDING BUSY VENDOR` |

### Production (MES → BUSY)
| MES field (confirmed: `rolls` / `rolls.js`) | → BUSY | Status |
|---|---|---|
| `roll_id`, `machine_id`, `actual_weight_kg` (**scale-measured, primary**), `fabric_item_id`, `shift` | `‹busy:production_stock_journal.*›` | `PENDING BUSY VENDOR` |
> Counter-derived estimate is **secondary**, never the posted quantity (`rolls.js`). `CONFIRMED BY SOURCE`.

### Dispatch (MES → BUSY, operational doc only)
| MES field (confirmed: `dispatch.routes.js`) | → BUSY | Status |
|---|---|---|
| dispatch no., party, item, qty/weight, warehouse | `‹busy:dispatch/delivery_doc.*›` | `PENDING BUSY VENDOR` |
> **BUSY authors the statutory sales/tax invoice** (D4); MES does **not** push a tax invoice and dispatch is not auto-combined with invoicing. `CONFIRMED BY DOC`.

### Job-work issue / recovery (MES → BUSY)
| MES field (confirmed: `subcontract_challans`/`_receipts`) | → BUSY | Status |
|---|---|---|
| challan no., vendor (party), fabric/item, roll_count, weight_kg, sent_date | `‹busy:jobwork_issue_voucher.*›` | `PENDING BUSY VENDOR` |
| receipt: received weight, `original_ref` (links to the issue) | `‹busy:jobwork_receipt_voucher.*›` | `PENDING BUSY VENDOR` |

### GST / tax ledgers (all taxable vouchers)
| MES field | → BUSY | Status |
|---|---|---|
| CGST/SGST/IGST amounts (where MES holds them) | `‹busy:tax_ledger.*›` per the company's tax config | `PENDING BUSY VENDOR` (tax-ledger mapping, doc 21 §5) |

## Validation rules (MES-side, before any render) `CONFIRMED BY SOURCE` / `PROPOSED`
- Party, warehouse and item **must be mapped & synced**, else → `MANUAL_REVIEW` (never a bad import) `CONFIRMED BY SOURCE`.
- Voucher date within an **open** FY period `PROPOSED`.
- Decimal-safe amounts; balanced/complete document `PROPOSED`.
- Purchase (BUSY-origin) is **not** re-pushed (circular-sync guard) `CONFIRMED BY SOURCE`.

## How this template gets completed (intake)
1. Receive the real exports (Purchase, GRN, Dispatch + masters) + BUSY edition.
2. Parse **structure only** — record the actual tags/columns/types into the `‹busy:…›` placeholders. **Do not reproduce any real party or financial values** in this file.
3. Confirm which field carries/returns our integration reference, and the tax-ledger representation.
4. Re-label completed rows `CONFIRMED BY SOURCE (export)`; promote the ownership matrix (doc 37) voucher types from `PENDING BUSY VENDOR` to confirmed.

## Unresolved (this document)
- **All BUSY-side fields/tags/types/format** — `PENDING BUSY VENDOR` (no export yet).
- Which BUSY field is both writable (on import) and readable back for the reference. `PENDING BUSY VENDOR`.
- GST/tax-ledger mapping. `PENDING BUSY VENDOR`.
- Whether the licensed edition supports XML/Excel import at all. `PENDING BUSY VENDOR` (doc 19 §1/§3).

*Read-only; nothing committed. No invented BUSY field; no real values included.*
