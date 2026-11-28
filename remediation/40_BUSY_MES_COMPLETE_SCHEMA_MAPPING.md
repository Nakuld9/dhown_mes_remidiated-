# 40 — Complete BUSY 21 ↔ MES Schema Matching Audit

**Date:** 2026-11-28 · **Branch:** `claude/mes-busy-remediation` · **HEAD:** `245b1f8`.
**READ-ONLY audit.** No source/schema/migration/config/data change; no BUSY connection; no live posting; no commit/push. Only this document (40) was created.

**Status vocabulary:** `EXACT MATCH` · `TRANSFORM REQUIRED` · `MES ONLY` · `BUSY ONLY` · `PENDING BUSY VENDOR` · `PENDING MES VALIDATION` · `NOT OBSERVED IN EXPORT`.

---

## 1. Executive summary
- Matching is done against a **sanitised structural analysis** of one BUSY export plus the **actual MES schema** (`backend/schema/00_baseline_schema.sql`, `backend/src/db/schema.js`) and workflows. **No BUSY data type, constraint or mandatory rule is available** in the sanitised report — only element names and presence — so **almost nothing qualifies as `EXACT MATCH`**; most voucher fields are `TRANSFORM REQUIRED` or `PENDING`.
- MES already has the **identity-mapping layer** (`busy_master_mapping`, entity_type ∈ CUSTOMER/VENDOR/ITEM/WAREHOUSE/TRANSACTION) and the deterministic `external_reference` — so the two schemas are bridged by a **mapping/transformation layer**, never by assuming equal identities.
- **Ownership rules are preserved and NOT reinterpreted** from the XML: Purchase BUSY→MES; all other operational/inventory MES→BUSY.
- **Biggest open items:** BUSY import/write interface and mandatory fields (all `PENDING BUSY VENDOR`); the **job-work** representation (BUSY embeds it in Purchase vouchers vs MES subcontract model); and several voucher groups with **very low sample counts** (StTfs 1, DrNts 1, PrRts 4, SlRts 9, CrNts 11).
- **No voucher type is integration-ready** — observing an XML structure is not import readiness (see §14).

## 2. Evidence sources & limitations
| Source | Used | Note |
|---|---|---|
| `DHOWN_BUSY_Sanitised_Schema_Findings.md` | ✅ read in full | sanitised; element names + counts only, **no data types/mandatory** |
| Original BUSY `.DAT` | ❌ **not opened** (not in repo) | all BUSY facts are from the sanitised report |
| `remediation/37,38,39,34,35,36` | ✅ read | docs 38 already updated from the export |
| MES schema `backend/schema/00_baseline_schema.sql`, `backend/src/db/schema.js` | ✅ | table/column references below |
| MES workflows `backend/src/routes/*`, `backend/src/lib/*` | ✅ | route/lib references below |
| `backend/src/lib/busy/{schema,identity,mapping,queue}.js` | ✅ | the MES-side bridge layer |
**Limitations:** export ≠ import compatibility; low sample counts; BUSY types/mandatory/posting/numbering unknown; Production & Stock Journal absent from the export (not evidence of non-support); Payment/Receipt/Journal/Contra not selected.

## 3. Confirmed BUSY export schema `CONFIRMED BY EXPORT`
Voucher groups (record element / count): `Purcs/Purchase` 462, `Sales/Sale` 454, `MtRcs/MaterialReceipt` 247, `MtIss/MaterialIssue` 224, `CrNts/CrNote` 11, `SlRts/SaleReturn` 9, `PrRts/PurchaseReturn` 4, `StTfs/StockTransfer` 1, `DrNts/DrNote` 1.
Master groups: `Accounts/Account` 110, `Items/Item` 52, `Units/Unit` 3, `MaterialCenter/MaterialCenter` 5, `BillSundries/BillSundry` 7, `SaleTypes/SaleType` 3, `PurchaseTypes/PurchaseType` 6.
Common header: `VchNo`, `AutoVchNo`, `VchType`, `OriginalID`, `VchSeriesName`, `Date`, `StockUpdationDate`, `MasterName1/2`, `TranCurName`. Containers: `ItemEntries`(+`/ItemDetail/MC`,`ItemName`,`ItemHSNCode`,`Qty*`,`UnitName`,`Amt`,`NettAmount`,`ItemTaxCategory`), `ItemEntries1`, `AccEntries`, `BillSundries`, `BillingDetails`, `PendingBillDetails`, `FGJobDetails`/`JobEntries`(+`JobID`), `VchOtherInfoDetails`. (`tmp*` elements are BUSY-internal working fields — treated as out of scope for integration mapping.)

## 4. Existing MES schema inventory (relevant) `CONFIRMED BY SOURCE`
| Domain | MES table | Key columns |
|---|---|---|
| Party master | `partners` | `partner_id` PK, `partner_code` (unique), `company_name`, `gstin`, `pan`; roles in `partner_roles` |
| Item master | `items` | `item_id` PK, `item_code` (unique), `item_name`, `uom_id`, `hsn_id`, `gst_rate`, `status`/`is_active` |
| Units | `uom` (+ `uom_conversions`) | `uom_id` PK, `code`, `name`, `is_active` |
| Warehouse/MC | `warehouses` | `warehouse_id` PK, `code`, `name`, `type`, `is_active` |
| HSN | `hsn_codes` | `hsn_id`, `hsn_code`, `gst_rate` |
| Tax | `tax_rates` | `tax_id`, `code`, `cgst`, `sgst`, `igst` |
| Cost centre | `cost_centres` | `cc_id`, `code`, `name` |
| GRN (receipt) | `grn` | `grn_id`, `grn_number`, `supplier_name`, `partner_id`, `warehouse_id`, `receipt_date` |
| Dispatch | `dispatch_challans` / `dispatch_items` | `dispatch_number`, `partner_id`, `dispatch_date`, `total_*`; items: `weight_kg`, `rate_per_kg`, `gst_rate`, `taxable_value`, `roll_id` |
| Job-work | `subcontract_challans`/`_items`, `subcontract_receipts`/`_items` | challan: `vendor_name`, `job_type`, `sent_weight_kg`; receipt: `received_weight_kg`, `rejected_weight_kg`, `balance_yarn_kg` |
| Stock movement | `stock_ledger` | `doc_type`, `doc_id`, `item_id`, `warehouse_id`, `movement_type`, `quantity`, `uom_code`, `partner_id` |
| Purchase | `purchase_orders`/`purchase_order_items` | (ensure-script) |
| Returns | `sales_returns`/`sales_return_items`; `returns.js` | (ensure-script) |
| Notes | `credit_notes`/`credit_note_allocations`; `credit-note-pdf.js` | (ensure-script) |
| Production | `rolls` (+ `rolls.js`) | `roll_id`, `machine_id`, `actual_weight_kg`, `fabric_item_id`, `shift` |
| **Bridge/identity** | `busy_master_mapping`, `busy_sync_queue` | `entity_type`, `dhown_id`↔`busy_id`/`busy_code`, `sync_status`; `UNIQUE(entity_type,dhown_id)` |

## 5. Master-by-master mapping
| BUSY master | MES table | MES business id | Identity mapping | Status | Notes |
|---|---|---|---|---|---|
| `Accounts/Account` (110) | `partners` (+ MES accounting ledger) | `partner_code` (unique) | `busy_master_mapping` CUSTOMER/VENDOR | **TRANSFORM REQUIRED** | BUSY `Accounts` includes GL ledgers MES does not model as partners → **not 1:1**; names ≠ identity. BUSY account id/fields `PENDING BUSY VENDOR` |
| `Items/Item` (52) | `items` | `item_code` (unique) | mapping ITEM | **TRANSFORM REQUIRED** | BUSY item identity fields `PENDING BUSY VENDOR`; uom/hsn/gst transform |
| `Units/Unit` (3) | `uom` (+ `uom_conversions`) | `code` | — | **TRANSFORM REQUIRED** | BUSY `ConFactor`/alt-unit observed on item lines → conversion handling; `PENDING MES VALIDATION` of conversion parity |
| `MaterialCenter/MaterialCenter` (5) | `warehouses` | `code` | mapping WAREHOUSE, **1:1 exact, hard-fail unmapped** (`mapping.js`, D3) | **TRANSFORM REQUIRED** | **No auto-remap**; exact identity preserved; unmapped → MANUAL_REVIEW |
| `BillSundries/BillSundry` (7) | `tax_rates` + item `gst_rate` (no MES bill-sundry master) | — | — | **BUSY ONLY** (master) / **TRANSFORM REQUIRED** | MES models tax/charges differently; BUSY owns bill sundries |
| `SaleTypes/SaleType` (3) | `dispatch_challans.dispatch_type` (no master) | — | — | **BUSY ONLY** | MES has no sale-type master; `PENDING MGMT` whether needed |
| `PurchaseTypes/PurchaseType` (6) | (none) | — | — | **BUSY ONLY** | MES has no purchase-type master |

> **Rule:** matching names never imply matching identity; all master identity is resolved through `busy_master_mapping`, and warehouse/material-centre mapping stays exact with no automatic remapping.

## 6. Voucher-by-voucher mapping (direction preserved)
| BUSY group | Direction (approved) | MES workflow/table | Status | Key notes |
|---|---|---|---|---|
| `Purcs/Purchase` | **BUSY → MES** (read) | `purchase_orders`/`_items` mirror | **TRANSFORM REQUIRED** / read fields `PENDING BUSY VENDOR` | also embeds `FGJobDetails`/`JobEntries` (job-work) — §9 |
| `Sales/Sale` | **BUSY authors invoice (D4)**; MES pushes dispatch only | `dispatch_challans`/`_items` | **TRANSFORM REQUIRED** | dispatch ≠ sales invoice; MES does not author the tax invoice |
| `MtRcs/MaterialReceipt` | **MES → BUSY** | `grn`/grn items | **TRANSFORM REQUIRED** | GRN no. ↔ `VchNo`/`OriginalID` `PENDING` |
| `MtIss/MaterialIssue` | **MES → BUSY** | material issue (`yarn_issue_items`, production issue) | **TRANSFORM REQUIRED** / MES issue→BUSY wiring `PENDING MES VALIDATION` |
| `StTfs/StockTransfer` | **MES → BUSY** | warehouse move via `stock_ledger` (no dedicated table) | **PENDING** (1 sample) | two legs `ItemEntries`/`ItemEntries1` — §D |
| `SlRts/SaleReturn` | **MES → BUSY** | `sales_returns`/`_items` | **PENDING** (9 samples) | stock + note impact `PENDING` |
| `PrRts/PurchaseReturn` | **MES → BUSY** | `returns.js` / purchase-return | **PENDING** (4 samples) | |
| `DrNts/DrNote` | accounting in BUSY | `credit_notes` family (operational trigger only) | **PENDING** (1 sample) | **no `ItemEntries`** in sample (accounting-only) |
| `CrNts/CrNote` | accounting in BUSY | `credit_notes` | **PENDING** (11 samples) | **no `ItemEntries`** in samples |
| *(Production)* | **MES → BUSY** | `rolls`/`rolls.js` | **NOT OBSERVED IN EXPORT** | BUSY production/stock-journal mapping `PENDING BUSY VENDOR` |

**MES operational transactions without a confirmed BUSY mapping:** production/roll output (no Production voucher in export); internal material issue to production; party-wise job-work outstanding (MES-authoritative concept, no direct BUSY voucher — §9).

## 7. Field-by-field mapping tables (established fields only)
> BUSY data types are **unknown** (not in the sanitised report), so the "BUSY type" column is `PENDING BUSY VENDOR` throughout; `EXACT MATCH` is therefore withheld.

### 7.1 Common voucher header
| BUSY field (path) | MES source (table.column / route) | Direction | Status | Note |
|---|---|---|---|---|
| `VchNo` | MES doc no. (`grn.grn_number`, `dispatch_challans.dispatch_number`, `subcontract_challans.challan_number`, `rolls.roll_id`) | MES→BUSY | **TRANSFORM REQUIRED** | writeability/allocation `PENDING BUSY VENDOR` (§7A) |
| `AutoVchNo` | (BUSY-allocated) | n/a | **BUSY ONLY** | returned by BUSY `PENDING BUSY VENDOR` |
| `VchType` | implied by workflow | MES→BUSY | **TRANSFORM REQUIRED** | exact values `PENDING BUSY VENDOR` |
| `OriginalID` | `external_reference` (`busy/identity.js`) | both | **PENDING BUSY VENDOR** | writeability/read-back unconfirmed (§7B) |
| `Date`/`StockUpdationDate` | MES doc date (`receipt_date`, `dispatch_date`, `sent_date`, roll `created_at`) | MES→BUSY | **TRANSFORM REQUIRED** | format/zone `PENDING` |
| `BillingDetails/PartyName` | `partners.company_name` (via mapping) | MES→BUSY | **TRANSFORM REQUIRED** | identity via `busy_master_mapping` |
| `BillingDetails/GSTNo`,`ITPAN` | `partners.gstin`,`pan` | MES→BUSY | **PENDING MES VALIDATION** | presence/parity to confirm |
| `MasterName1/2` | party/account names | MES→BUSY | **TRANSFORM REQUIRED** | |
| `TranCurName` | (currency) | — | **PENDING MES VALIDATION** | MES assumes INR; confirm |

### 7.2 Item line (`ItemEntries/ItemDetail`)
| BUSY field | MES source | Status | Note |
|---|---|---|---|
| `ItemName` | `items.item_name` (via mapping ITEM) | **TRANSFORM REQUIRED** | identity via mapping, not name |
| `MC` (material centre) | `warehouses` (via mapping WAREHOUSE) | **TRANSFORM REQUIRED** | **exact identity, no auto-remap** |
| `ItemHSNCode` | `items.hsn_id → hsn_codes.hsn_code` | **TRANSFORM REQUIRED** | |
| `Qty`/`QtyMainUnit`/`QtyAltUnit` | line weight/qty (`*_weight_kg`, `dispatch_items.weight_kg`, `subcontract_*`.`weight_kg`) | **TRANSFORM REQUIRED** | **unit & precision risk** (§G): MES weight `numeric(10,3)`; BUSY main/alt unit split + `ConFactor` |
| `UnitName`/`AltUnitName` | `uom.code`/`uom_conversions` | **TRANSFORM REQUIRED** | |
| `Amt`/`NettAmount` | line value (`taxable_value`, `rate_per_kg`×qty) | **TRANSFORM REQUIRED** | BUSY owns valuation |
| `ItemTaxCategory` | `items.gst_rate`/`tax_rates` | **TRANSFORM REQUIRED** / `PENDING BUSY VENDOR` | tax-ledger mapping unknown |

### 7.3 Accounting / tax containers
`AccEntries/AccDetail/*`, `BillSundries/BSDetail/*`, `TDSDetails`, `VchGstSumAcc`, e-invoice fields → **BUSY ONLY / PENDING BUSY VENDOR** (BUSY is the accounting authority; MES does not author these). MES supplies only the operational basis.

## 8. Identity & numbering strategy
- **Idempotency key:** MES `external_reference` (`busy/identity.js`) + `busy_master_mapping.UNIQUE(entity_type, dhown_id)` + `busy_sync_queue` idempotent insert — the **MES-side** key is confirmed. Mapping it onto a BUSY-visible field (`OriginalID` candidate) is `PENDING BUSY VENDOR`.
- **Dual numbering:** `VchNo` (series no.) vs `AutoVchNo` both appear; which MES supplies vs which BUSY allocates is `PENDING BUSY VENDOR`. **`StTfs` sample had neither** — anomaly, needs more samples.
- **BUSY-originated purchase number** must be preserved on read (origin=BUSY, not re-pushed — circular-sync guard confirmed in `operational-events.js`). **MES-originated numbers** must survive the push and be reconciled against the BUSY-returned number (read-back). **No BUSY voucher number is predicted/fabricated.**

## 9. Job-work mapping analysis `CONFIRMED` discrepancy
- **MES (docs 37/39, code):** job-work is sent/received/consumed/wastage/finished tracked via `subcontract_challans`/`_items` (sent) and `subcontract_receipts`/`_items` (received, `rejected_weight_kg`, `balance_yarn_kg`), MES-authoritative for party-wise outstanding (D7). Direction **MES→BUSY** for factory-originated goods sent for job work — **approved, not to be reversed**.
- **BUSY export:** job-work appears as `FGJobDetails`/`JobEntries` with `JobID` **embedded inside `Purcs` (Purchase)** vouchers (10/462), with `JobEntries/ItemDetail` carrying item lines.
- **Possible mapping approaches (ALTERNATIVES, not requirements):** (a) MES job-work issue/recovery → a BUSY material issue/receipt voucher carrying `JobID`; (b) → job details embedded in a BUSY purchase voucher for the **inbound** (finished-goods-received) leg only, keeping the **outbound send** as an MES→BUSY issue; (c) a dedicated BUSY job-work voucher if the vendor confirms one exists.
- **Do not** conclude all job-work must become Purchase vouchers. `JobID` semantics, which leg maps where, and whether `FGJobDetails` is importable are **PENDING BUSY VENDOR** + **test-company validation**. **No change made to docs 37/39.**

## 10. Stock & accounting impact analysis
- **Stock Transfer (StTfs, 1 sample):** two item containers `ItemEntries` + `ItemEntries1`, each with `MC` — **likely source vs destination legs**, but **insufficient evidence** (1 record, and it lacked `VchNo`/`AutoVchNo`). MES represents transfers as paired `stock_ledger` movements (OUT one warehouse, IN another). Mapping `PENDING` until more samples.
- **Returns (SlRts 9 / PrRts 4):** carry `ItemEntries` (stock) in samples → likely adjust stock; whether they **also** generate a credit/debit note is `PENDING` (risk of **double stock/accounting movement** if both a return and a note post). `sales_returns`/`returns.js` on the MES side.
- **Dr/Cr notes (DrNts 1 / CrNts 11):** **no `ItemEntries`** in samples → accounting-only (value adjustment); carry `tmpOldVchNo`/`tmpOldAutoVchNo` (reference to original). **Do not infer universal stock behaviour** from small samples. BUSY authors; MES sends only an operational trigger.
- **Tax/GST:** observed `BillSundries/BSDetail`, `ItemTaxCategory`, `TDSDetails`, `VchGstSumAcc`, e-invoice fields — **BUSY-owned**; MES does not compute or author postings. No tax calculation invented.

## 11. Schema gaps & transformations
1. **BUSY fields with no MES equivalent (BUSY ONLY):** `AutoVchNo`, `AccEntries/*` detail, `BillSundries` master+detail, `SaleTypes`, `PurchaseTypes`, `TDSDetails`, `VchGstSumAcc`, e-invoice (`EInv*`), `VchSeriesName`, `ParamStockEntries`, `FGJobDetails` (as a purchase sub-structure).
2. **MES fields with no BUSY equivalent (MES ONLY):** `rolls.actual_weight_kg` (scale-measured, operational), `machine_id`/`shift`/operator attribution, `subcontract_receipts.rejected_weight_kg`/`balance_yarn_kg`, lot/batch (`lot_id`, `batch_rolls`), `warehouse` rack/bin, QR, cost entries. (These stay MES-only operational data.)
3. **Transform required:** every party/item/warehouse/unit identity (via mapping), qty/unit/ConFactor, dates, document numbers, amounts.
4. **Conflicting meanings:** BUSY `Accounts` (ledger, incl. GL) vs MES `partners` (trade parties only); BUSY `MC` identity vs MES `warehouse_id` (map by code, not name).
5. **Duplicate/ambiguous identities:** party could match multiple BUSY accounts; item name collisions — resolved only by explicit `busy_master_mapping`.
6. **Missing mandatory info:** BUSY mandatory-field sets are **unknown** → cannot guarantee a push will be accepted (`PENDING BUSY VENDOR`).
7. **Unresolved vendor questions:** §12.
8. **MES workflows without confirmed BUSY mapping:** production/roll output, internal material issue, party-wise outstanding.
9. **BUSY groups without sufficient evidence:** StTfs (1), DrNts (1), PrRts (4), SlRts (9), CrNts (11).

**Schema-change recommendations (recommendation only — do NOT implement):**
- *Possibly* add a nullable `busy_reference`/`busy_voucher_no` column to MES transaction tables to store the BUSY-returned number. **Why a mapping layer alone is insufficient:** the returned BUSY number must be **persisted and reconciled** per document for audit and duplicate prevention; a stateless transform cannot retain it across the async `AWAITING_BUSY` round-trip. Still a recommendation pending approval + the proposed bridge tables (doc 29 §10).
- All other differences are handled by the **mapping/transformation layer** (`busy_master_mapping` + render/parse) without MES schema change.

## 12. Unresolved BUSY vendor questions
1. Supported **import/write interface** and which groups are creatable (export ≠ import).
2. **Mandatory field set** per voucher group.
3. Is `OriginalID` **writable** and **readable back**? Is it unique/suitable as the idempotency anchor?
4. **Numbering:** VchNo caller-supplied or BUSY-allocated; role of AutoVchNo; the StTfs no-number anomaly.
5. **Stock Transfer** full schema (ItemEntries vs ItemEntries1 = from/to legs?).
6. **Returns & notes:** do returns post stock *and* a note? Can Dr/Cr notes ever carry stock?
7. **Job-work:** JobID semantics; how MES issue/recovery should map; is FGJobDetails importable?
8. **Masters:** identity fields for Accounts/Items/Units/MaterialCenter; account-type taxonomy.
9. **Tax ledgers / bill sundries / TDS** representation on import.
10. **Cancellation/amendment** mechanism; meaning of `tmpOldVchNo`/`tmpOldAutoVchNo`.
11. **Test company** for import trials.

## 13. MES validation questions (`PENDING MES VALIDATION`)
- Confirm MES material-issue and stock-transfer workflows exist as discrete, capturable events (issue currently via `yarn_issue_items`/production; transfer only via `stock_ledger`).
- Confirm currency is always INR (no `TranCurName` variance).
- Confirm unit-conversion parity (`uom_conversions`) against BUSY `ConFactor`/alt-unit, and precision (`numeric(10,3)` weight vs BUSY main/alt split) to quantify rounding risk.
- Confirm `partners`→BUSY-account cardinality (one partner ↔ one BUSY account?).

## 14. Voucher readiness matrix
Per voucher: Schema evidence (SE) · MES field mapping (MM) · Master identity (MI) · Direction/ownership (DO) · Import/write (IW) · Validation rules (VR) · Test-company (TC).
| Voucher | SE | MM | MI | DO | IW | VR | TC |
|---|---|---|---|---|---|---|---|
| Purchase (read) | high | partial | mapping-ready | ✅ confirmed | `PENDING VENDOR` | `PENDING` | not done |
| Sales/dispatch | high | partial | mapping-ready | ✅ | `PENDING VENDOR` | `PENDING` | not done |
| Material receipt (GRN) | high | partial | mapping-ready | ✅ | `PENDING VENDOR` | `PENDING` | not done |
| Material issue | high | `PENDING MES` | mapping-ready | ✅ | `PENDING VENDOR` | `PENDING` | not done |
| Stock transfer | **low (1)** | `PENDING` | mapping-ready | ✅ | `PENDING VENDOR` | `PENDING` | not done |
| Sales return | low (9) | partial | mapping-ready | ✅ | `PENDING VENDOR` | `PENDING` | not done |
| Purchase return | low (4) | partial | mapping-ready | ✅ | `PENDING VENDOR` | `PENDING` | not done |
| Debit note | **very low (1)** | partial | mapping-ready | BUSY-authored | `PENDING VENDOR` | `PENDING` | not done |
| Credit note | low (11) | partial | mapping-ready | BUSY-authored | `PENDING VENDOR` | `PENDING` | not done |
| Production | **none in export** | MES-ready | mapping-ready | ✅ | `PENDING VENDOR` | `PENDING` | not done |
> **No voucher is integration-ready.** Observed structure ≠ import readiness; every IW/VR/TC column is unmet.

## 15. Recommended next steps
1. Vendor confirmation of the import/write interface, mandatory fields, numbering and `OriginalID` writeability (doc 35 [M] items).
2. Additional StTfs / DrNts / PrRts / SlRts samples; a Production sample if/when created.
3. Resolve the **job-work** mapping with the vendor + a test company (§9) — then (separately approved) reconcile docs 37/39.
4. MES validation (§13): confirm issue/transfer event capture, currency, unit conversions/precision.
5. Decide (mgmt) whether to add a persisted `busy_reference` column (§11) — recommendation only.
6. Build the adapter **mock-first**, flag-OFF, against a BUSY **test company** only — no production.

## 16. Assumptions that must NOT be treated as confirmed facts
- That any exported group is **importable/writable** (export ≠ import).
- That `OriginalID` is writable or is the idempotency key.
- That `VchNo` is caller-supplied or that MES controls numbering.
- That Dr/Cr notes never move stock (small sample).
- That returns post stock only once (possible note duplication).
- That job-work must become Purchase vouchers.
- That `ItemEntries1` = destination leg of a transfer (1 sample).
- That matching master/field names imply matching identity.
- That BUSY supports a generic REST API (it does not; no interface assumed).
- That Production/Payment/Receipt/Journal/Contra are unsupported (merely absent/unselected).

---
*Read-only; original `.DAT` not opened; no invented BUSY field/type/rule; no real party/item/financial values; ownership directions preserved; nothing committed.*
