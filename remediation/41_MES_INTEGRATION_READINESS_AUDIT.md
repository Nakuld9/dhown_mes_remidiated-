# 41 — MES Integration Readiness Audit (Phase 4)

**Date:** 2026-11-28 · **Branch:** `claude/mes-busy-remediation` · **HEAD:** `092db2f`.
**READ-ONLY audit.** No source/schema/migration/config/data change; no BUSY connection; no live posting; no commit/push. Only this document (41) was created. Docs 34–40 unchanged. Examples below are synthetic where shown.

**Status vocabulary:** `VERIFIED IN MES SOURCE` · `VERIFIED IN MES DATABASE` · `PARTIALLY VERIFIED` · `MISSING` · `PROPOSED ONLY` · `PENDING BUSY VENDOR` · `PENDING MANAGEMENT DECISION`.

---

## 1. Executive summary
- The MES schema, master data and the **integration reliability layer** are substantially present and verifiable in source and in the recovered baseline DB. Identity mapping, idempotency, audit, retry and reconciliation primitives already exist (`backend/src/lib/busy/*`), flag-OFF and mock-backed.
- **Verified strengths:** stable PKs + unique business codes on every master; FK referential integrity across partners/items/warehouses/uom and the job-work chain; a deterministic `external_reference`; `UNIQUE(external_reference)` idempotency; append-only audit.
- **Real gaps (not blockers to design, but to integration):** **no dedicated stock-transfer workflow/table** (only `stock_ledger` paired movements); **GRN appears header-only** (no verified line-item table); **no per-party job-work outstanding rollup** endpoint (per-challan only); **no persisted `busy_reference`** column on MES transaction tables; **no formal consumed/wastage yield split** (only `balance_yarn_kg` + `rejected_weight_kg`).
- **Everything BUSY-side stays blocked:** import/write interface, mandatory fields, `OriginalID` writeability, numbering, job-work voucher mapping — all `PENDING BUSY VENDOR`.
- A **BUSY-independent canonical contract** (§8) can be defined now from verified MES structures; implementation is not started.

## 2. Actual MES schema inventory (verified)
`VERIFIED IN MES DATABASE` (`backend/schema/00_baseline_schema.sql`) unless noted.
| Entity | Table | PK | Unique business id | Key FKs |
|---|---|---|---|---|
| Party | `partners` (+ `partner_roles/addresses/bank/contacts`) | `partner_id` | `partner_code` (uq) | roles/addr/bank/contacts → partners |
| Item | `items` | `item_id` | `item_code` (uq) | `uom_id`→uom, `hsn_id`→hsn_codes, `category_id`→item_categories |
| Unit | `uom` (+ `uom_conversions`) | `uom_id` | `code` (uq) | — |
| Material centre | `warehouses` (+ `racks`) | `warehouse_id` | `code` (uq) | racks→warehouses |
| HSN | `hsn_codes` | `hsn_id` | `hsn_code` | — |
| Tax | `tax_rates` | `tax_id` | `code` | cgst/sgst/igst |
| GRN | `grn` | `grn_id` | `grn_number` (uq) | `partner_id`→partners, `warehouse_id`→warehouses |
| Dispatch | `dispatch_challans` / `dispatch_items` | `dispatch_id` / `item_id` | `dispatch_number` (uq) | items→challans (CASCADE), `partner_id`→partners, `fg_id`→finished_goods |
| Job-work issue | `subcontract_challans` / `_items` / `sc_challan_yarn_items` | `challan_id` / `item_id` | `challan_number` (uq) | `partner_id`→partners, `batch_id`→batches, `forwarded_from_challan_id`→self, items→challans (CASCADE) |
| Job-work receipt | `subcontract_receipts` / `_items` | `receipt_id` / `item_id` | — | `challan_id`→challans, items→receipts (CASCADE), `finished_goods.receipt_id`→receipts |
| Stock | `stock_ledger` | `ledger_id` | (`doc_type`,`doc_id`) logical | `item_id`,`warehouse_id`,`partner_id` |
| Production | `rolls` | `roll_id` | `roll_id` (text) | `fabric_item_id` |
| Bridge/identity | `busy_master_mapping`, `busy_sync_queue`, `busy_audit_log`, `busy_reconciliation`, `busy_connection_state` | ids | `UNIQUE(entity_type,dhown_id)`, `UNIQUE(external_reference)` | — |

## 3. Voucher-by-voucher workflow validation
Directions per the approved freeze (doc 37); **not inferred from BUSY XML**.
| Transaction | Direction | MES workflow (evidence) | Status |
|---|---|---|---|
| Purchase (from BUSY) | BUSY→MES | `purchase_orders`/`_items` (ensure-script); read-mirror design only | `PARTIALLY VERIFIED` (tables exist; BUSY read fields `PENDING BUSY VENDOR`) |
| GRN / material receipt | MES→BUSY | `grn.routes.js` → `grn` (header); captures `grn_receipt` | `PARTIALLY VERIFIED` — **no verified GRN line-item table** (header-only) → line-level BUSY `MaterialReceipt` mapping incomplete |
| Material issue | MES→BUSY | issue via `yarn_issue_items` / production flows | `PARTIALLY VERIFIED` — no single "material issue voucher" endpoint wired to the bridge |
| Stock transfer | MES→BUSY | `stock_ledger` paired OUT/IN movements only | `MISSING` as a discrete capturable workflow/table |
| Production | MES→BUSY | `rolls` + `rolls.js` (auto-doff, scale weight) | `VERIFIED IN MES SOURCE` (workflow); BUSY voucher mapping `PENDING BUSY VENDOR` (absent from export) |
| Sales / dispatch | MES→BUSY | `dispatch.routes.js` → `dispatch_challans`/`_items`; captures `dispatch` | `VERIFIED IN MES SOURCE`; BUSY authors the tax invoice (D4) |
| Sales return | MES→BUSY | `sales_returns`/`_items`, `returns.js` | `PARTIALLY VERIFIED` — bridge capture not wired |
| Purchase return | MES→BUSY | `returns.js` | `PARTIALLY VERIFIED` |
| Debit / credit notes | BUSY-authored | `credit_notes`/`credit_note_allocations`, `credit-note-pdf.js` | `PARTIALLY VERIFIED` — MES holds operational basis only |
| Job work | MES→BUSY | `subcontract.routes.js` (785 lines) → challans/receipts; captures `party_issue`/`party_recovery` | `VERIFIED IN MES SOURCE` (see §5) |
> **No workflow was assumed to exist from a doc table alone** — each row is traced to an actual route/table or explicitly marked MISSING/PARTIAL.

## 4. Master-data readiness
| Master | Stable identity | Active/inactive | Mapping | Duplicate risk | Status |
|---|---|---|---|---|---|
| Party | `partner_code` (uq) + `partner_id` | (status on roles) | `busy_master_mapping` CUSTOMER/VENDOR | GSTIN/name variants; BUSY `Accounts` not 1:1 | `VERIFIED IN MES DATABASE`; BUSY ids `PENDING BUSY VENDOR` |
| Item | `item_code` (uq) + `item_id` | `status`/`is_active` | mapping ITEM | name collisions | `VERIFIED` |
| Unit | `uom.code` (uq) + `uom_conversions` | `is_active` | — | conversion mismatch | `VERIFIED` (conversion parity `PENDING MES VALIDATION`) |
| Material centre | `warehouses.code` (uq) | `is_active` | mapping WAREHOUSE **1:1 exact, hard-fail, no auto-remap** (`mapping.js`) | low (exact) | `VERIFIED` |
| Tax | `tax_rates.code` + item `gst_rate`/`hsn` | `is_active` | — | — | `VERIFIED`; BUSY bill-sundry/tax-ledger mapping `PENDING BUSY VENDOR` |
**Referential integrity gaps:** job-work `subcontract_challans` carries **both** `partner_id` (FK→partners) **and** a free-text `vendor_name` — a consistency risk if they diverge (`PARTIALLY VERIFIED`; recommend standardising on `partner_id`, recommendation only). `stock_ledger.doc_id` is a logical text key, not an FK (by design for heterogeneous sources).

## 5. Job-work readiness & gaps
`VERIFIED IN MES SOURCE` (`backend/src/routes/subcontract.routes.js`) / `VERIFIED IN MES DATABASE`:
- **Goods sent:** `subcontract_challans.sent_weight_kg`, `roll_count`, `_items` lines; captures `party_issue`.
- **Goods received / partial receipts:** `POST /challans/:id/receive` computes `totalReceivedSoFar = SUM(received_weight_kg WHERE challan_id) + this` vs `sent_weight_kg` (lines 227-230, 336-338) → **partial-receipt handling is real and per-challan**; captures `party_recovery`.
- **Rejection / quality:** `subcontract_receipts.rejected_weight_kg`, `quality_status`.
- **Balance yarn (unconsumed):** `balance_yarn_kg` returned to the yarn store on each receipt (stock movement) — real.
- **Finished goods:** `finished_goods.receipt_id` → `subcontract_receipts` (FK).
- **Original document reference:** `subcontract_receipts.challan_id` → `subcontract_challans` (FK) — correlation integrity **enforced at DB level**; multi-stage via `forwarded_from_challan_id` (self-FK).
- **Outstanding calculation:** per-challan `sent − Σreceived` is computed in code (`PARTIALLY VERIFIED`). **A per-party (per-vendor) aggregate rollout across all challans is NOT a confirmed single endpoint** — the data supports it (`partner_id` + weights) but it is `PROPOSED ONLY` as a report. Doc 39's "outstanding = Σissued − Σrecovered" holds **per challan**; the party-wide aggregate and the **consumed-vs-wastage yield split** remain `PROPOSED ONLY` / `PENDING MANAGEMENT DECISION` (tolerances).
**Gaps (no rule changed, no tolerance invented):** per-party outstanding report; formal consumed/wastage/yield model; duplicate-receipt guard beyond the sent-vs-received sum (over-receipt is summed but acceptance policy is `PENDING MANAGEMENT DECISION`).

## 6. Inventory integrity risks
- **Stock transfer** has no discrete workflow/table → transfers are inferred from `stock_ledger` pairs; reconciling against a BUSY `StockTransfer` voucher (1 sample, two legs) is `MISSING`/`PENDING`.
- **GRN header-only** (no verified line table) → line-level receipt quantities for BUSY `MaterialReceipt` are incomplete (`PARTIALLY VERIFIED`).
- **Unit/precision:** MES weights `numeric(10,3)`; BUSY main/alt-unit split + `ConFactor` → rounding/conversion risk (`PENDING MES VALIDATION`).
- **Dual counting:** returns-plus-note and transfer two-leg could double-post if mapped naively (`PENDING BUSY VENDOR`).
- **Measured vs counter:** production weight is scale-measured (`rolls.actual_weight_kg`), counter is secondary — preserved; reconciliation tolerances `PENDING MANAGEMENT DECISION`.

## 7. Idempotency & reliability assessment
`VERIFIED IN MES SOURCE` (`backend/src/lib/busy/{identity,queue,schema,mapping}.js`) — **flag-OFF, mock-backed** (not yet exercised against real BUSY):
| Capability | Evidence | Status |
|---|---|---|
| External reference | `makeExternalReference` → `origin:entity_type:dhown_entity_id:operation` (identity.js:22) | `VERIFIED IN MES SOURCE` |
| Idempotency / duplicate detection | `UNIQUE INDEX uq_busy_queue_external_ref`; `INSERT … ON CONFLICT (external_reference) DO NOTHING` (queue.js:36) | `VERIFIED IN MES SOURCE` |
| Transaction status | `busy_sync_queue.status CHECK (PENDING/PROCESSING/AWAITING_BUSY/…)` | `VERIFIED` |
| Retry / backoff | atomic `claim` (PROCESSING, attempt_count++), `backoff(attempts)`, RETRY (queue.js:46-56) | `VERIFIED IN MES SOURCE` |
| Failure recovery / dead-letter | terminal FAILED/MANUAL_REVIEW states | `VERIFIED IN MES SOURCE` |
| Audit log | append-only `busy_audit_log` (payload_snapshot, attempt, busy_response, busy_reference, final_status, error_*) | `VERIFIED IN MES SOURCE` |
| Reconciliation | `busy_reconciliation` table + `queue.reconcile` | `VERIFIED IN MES SOURCE` |
| Manual replay | `process()` returns replay for SUCCESS; RETRY re-claim | `VERIFIED IN MES SOURCE` |
| Connection health | `busy_connection_state` | `VERIFIED IN MES SOURCE` |
> **Caveat:** these are proven against the **mock** connector (tests: `busy-integration.e2e.js`, `busy-mirror.e2e.js`). Real-BUSY behaviour is unproven. **`OriginalID` writeability is NOT assumed** — the external_reference is an MES-side key; binding it to a BUSY field is `PENDING BUSY VENDOR`.

## 8. Canonical integration contract proposal `PROPOSED ONLY` (BUSY-independent; not implemented)
A transport- and BUSY-independent document model MES can emit/consume; adapters translate to/from BUSY XML (or any future interface):
```
CanonicalDocument {
  header: {
    source_system:  'MES' | 'BUSY',
    doc_type:       PURCHASE | MATERIAL_RECEIPT | MATERIAL_ISSUE | STOCK_TRANSFER |
                    PRODUCTION | DISPATCH | SALES_RETURN | PURCHASE_RETURN |
                    DEBIT_NOTE | CREDIT_NOTE | JOBWORK_ISSUE | JOBWORK_RECEIPT,
    source_doc_id:  <MES PK, e.g. grn_number / dispatch_number / challan_number / roll_id>,
    external_reference: <origin:entity_type:dhown_entity_id:operation>,   // existing identity
    original_doc_ref:   <correlated source, e.g. challan_number for a receipt>,
    doc_date, posting_date,
    direction:      'MES_TO_BUSY' | 'BUSY_TO_MES'
  },
  party: { mes_partner_code, busy_account_ref? /*PENDING VENDOR*/ },
  material_centre: { mes_warehouse_code, busy_mc_ref? /*exact-mapped*/ },
  lines: [ {
    mes_item_code, busy_item_ref?,            // via busy_master_mapping
    qty_main, uom, qty_alt?, uom_alt?, conv_factor?,
    weight_kg, amount?, hsn_code?, tax_ref?    // amount/tax: BUSY-owned
  } ],
  tax_accounting: { /* references only — BUSY authors postings */ },
  status: { sync_status: PENDING|PROCESSING|AWAITING_BUSY|SUCCESS|FAILED|MANUAL_REVIEW,
            busy_voucher_no? /*returned, read-back PENDING VENDOR*/, attempt_count },
  validation: { ok, errors:[{code,message}], mapping_gaps:[...] }
}
```
Notes: every `busy_*_ref` is resolved only through `busy_master_mapping` (never by name); `amount`/`tax` are references, not MES-authored postings; `busy_voucher_no` persistence is a recommended (not implemented) MES column (§9).

## 9. Missing MES capabilities
1. `MISSING` — a discrete **stock-transfer** workflow/table (only `stock_ledger` pairs).
2. `PARTIALLY VERIFIED/MISSING` — **GRN line-item** table (header-only GRN).
3. `PROPOSED ONLY` — **per-party job-work outstanding** rollup report.
4. `PROPOSED ONLY` — persisted **`busy_reference`/`busy_voucher_no`** column per MES transaction (today the returned number lives only in `busy_audit_log`/queue). *Why a mapping layer alone is insufficient:* the BUSY-returned number must be persisted and reconciled per source document across the async `AWAITING_BUSY` round-trip; a stateless transform cannot retain it — **recommendation only, not implemented.**
5. `PROPOSED ONLY` — material-issue and production **bridge-capture wiring** (not in `operational-events.js` `WORKFLOWS`).
6. `PROPOSED ONLY` — formal **consumed/wastage/yield** model for job-work.

## 10. BUSY-dependent decisions that remain blocked (`PENDING BUSY VENDOR`)
Import/write interface and which groups are creatable; mandatory field sets; `OriginalID` writeability/read-back and suitability as the idempotency anchor; VchNo vs AutoVchNo allocation (+ StTfs no-number anomaly); job-work voucher mapping (`FGJobDetails`/`JobID`); returns-vs-notes stock behaviour; tax-ledger/bill-sundry representation; cancellation/amendment mechanism (`tmpOldVchNo`); a BUSY **test company** for import trials.
`PENDING MANAGEMENT DECISION`: reconciliation tolerances/cadence; job-work wastage/yield thresholds; over-receipt acceptance policy; whether to add the `busy_reference` column.

## 11. Recommended implementation sequence
1. Obtain vendor import-interface docs + test company (unblocks §10).
2. MES validation (§4/§6): confirm unit-conversion parity and precision; decide on `partner_id`-only for job-work; confirm GRN line handling.
3. Define the canonical contract (§8) concretely from the resolved mapping.
4. Build the adapter **mock-first, flag-OFF**, reusing the verified reliability layer (§7).
5. Add (if approved) the discrete stock-transfer capture, GRN lines, per-party outstanding report and `busy_reference` persistence — each as a separate, reviewed change.
6. Shadow-run against the BUSY test company; reconcile; then per-document-type cutover.
*All steps are recommendations; none is implemented here.*

## 12. Evidence references
Schema: `backend/schema/00_baseline_schema.sql` (constraints ~L3898–5242 for PK/UNIQUE/FK). Workflows: `backend/src/routes/{subcontract(785L),grn,dispatch,purchase-orders,sales-orders,production-entry}.routes.js`, `backend/src/lib/{rolls,returns}.js`. Reliability/identity: `backend/src/lib/busy/{identity.js:22, queue.js:36/46-56, schema.js:25-127, mapping.js}`. Masters: `partners`, `items`, `uom`, `warehouses`, `hsn_codes`, `tax_rates`. Prior docs: `remediation/37–40`.

---
*Read-only; no source/schema/migration/data change; no BUSY connection; no commit/push; docs 34–40 untouched; no invented BUSY ids/fields/tolerances; synthetic examples only.*
