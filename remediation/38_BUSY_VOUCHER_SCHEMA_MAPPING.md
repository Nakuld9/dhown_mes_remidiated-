# 38 — BUSY Voucher Schema Mapping (updated from an actual sanitised export analysis)

**Date:** 2026-11-28 (updated) · **Branch:** `claude/mes-busy-remediation` · **HEAD:** `2055c94`.
**Documentation only.** No code/schema/migration change; no BUSY connection; no live write. **No BUSY field, tag or voucher rule is invented.** No actual party, item or financial values appear here.

## Provenance of this update
- Source: **`DHOWN_BUSY_Sanitised_Schema_Findings.md`** — a sanitised *structural* analysis of an actual BUSY 21 export (`DHM_20261128_Vh01042026.DAT`, observed as an XML document, declared `ISO-8859-1`, root `BusyData`, attribute `FinYear="01-04-2026"`).
- **I did NOT open the original `.DAT` file** — the raw export is not in this repository. Everything below is taken from the sanitised report.
- **An export is not proof of import compatibility.** Group/element names and record presence are `CONFIRMED BY EXPORT`; whether any of this can be *written/imported*, which fields are *mandatory*, and how numbering/posting/cancellation behave are all `PENDING BUSY VENDOR`.

**Labels:** `CONFIRMED BY EXPORT` (observed in this file: groups, counts, element names, presence) · `CONFIRMED BY SOURCE` (MES code) · `PENDING BUSY VENDOR` (import/mandatory/writeability/posting/numbering/tax rules) · `PENDING MGMT`.

## 1. Export contents — voucher groups `CONFIRMED BY EXPORT`
| Group | Record element | Count | Meaning | Confidence |
|---|---|---:|---|---|
| `Purcs` | `Purchase` | 462 | Purchase | high |
| `Sales` | `Sale` | 454 | Sales | high |
| `MtRcs` | `MaterialReceipt` | 247 | Material receipt | high |
| `MtIss` | `MaterialIssue` | 224 | Material issue | high |
| `CrNts` | `CrNote` | 11 | Credit note | **low (11)** |
| `SlRts` | `SaleReturn` | 9 | Sales return | **low (9)** |
| `PrRts` | `PurchaseReturn` | 4 | Purchase return | **low (4)** |
| `StTfs` | `StockTransfer` | 1 | Stock transfer | **very low (1)** |
| `DrNts` | `DrNote` | 1 | Debit note | **very low (1)** |

> These nine groups **exist in the export**. This **upgrades** the doc-37 "proposed BUSY voucher type" from guesswork to *observed group names* — but **importability/writeability of each remains `PENDING BUSY VENDOR`**. `Production` and `Stock Journal` are **absent** (user reports no entries); Payment/Receipt/Journal/Contra were not selected — absence is **not** evidence they are unsupported.

## 2. Master groups `CONFIRMED BY EXPORT`
| Group | Record element | Count |
|---|---|---:|
| `Accounts` | `Account` | 110 |
| `Items` | `Item` | 52 |
| `Units` | `Unit` | 3 |
| `MaterialCenter` | `MaterialCenter` | 5 |
| `BillSundries` | `BillSundry` | 7 |
| `SaleTypes` | `SaleType` | 3 |
| `PurchaseTypes` | `PurchaseType` | 6 |
> `MaterialCenter` (5) corroborates the BUSY-authoritative warehouse/material-centre model (doc 22 D3). Item↔SKU and party identity map onto `Items`/`Accounts`. Exact master identity fields `PENDING BUSY VENDOR` (validate without copying values).

## 3. Common header elements & detail containers `CONFIRMED BY EXPORT`
- **Header (presence varies by group):** `VchSeriesName`, `Date`, `VchNo`, `AutoVchNo`, `VchType`, `OriginalID`, `MasterName1`, `MasterName2`, `TranCurName`, `StockUpdationDate`.
- **Detail containers observed:** `ItemEntries`, `ItemEntries1`, `AccEntries`, `BillSundries`, `BillingDetails`, `PendingBillDetails`, `FGJobDetails`, `JobEntries`, `VchOtherInfoDetails` (`OrgSalePurcDet` named in the report's cross-observations).
- **Item line (`ItemEntries/ItemDetail`) carries `MC`** (material centre) per line, plus `ItemName`, `ItemHSNCode`, `Qty`/`QtyMainUnit`/`QtyAltUnit`, `UnitName`/`AltUnitName`, `Price`/`ListPrice`, `Amt`/`NettAmount`, `BatchEntries`, `ItemTaxCategory`, `ParamStockEntries`. `CONFIRMED BY EXPORT`.

### Per-voucher container profile `CONFIRMED BY EXPORT` (this file)
| Group | ItemEntries | ItemEntries1 | AccEntries | BillSundries | PendingBillDetails | FGJobDetails/JobEntries | Notes |
|---|:--:|:--:|:--:|:--:|:--:|:--:|---|
| Purcs | ✅ | — | ✅ | ✅ | some | **✅ (10/462)** | job-work embedded via `JobID` |
| Sales | ✅ | — | ✅ | ✅ | some | — | e-invoice fields present |
| MtRcs | ✅ | — | — | — | — | — | *(profile per report)* |
| MtIss | ✅ | — | — | — | — | — | *(profile per report)* |
| SlRts | ✅ | — | — | — | — | — | low sample |
| PrRts | ✅ | — | — | — | — | — | low sample |
| **StTfs** | ✅ | **✅** | — | — | — | — | two MC legs; **no `VchNo`/`AutoVchNo` in the single sample** |
| **DrNts** | **—** | — | ✅ | — | ✅ | — | **accounting-only; no stock lines** |
| **CrNts** | **—** | — | ✅ | — | — | — | **accounting-only; no stock lines** |
> **Debit/credit notes carry NO `ItemEntries` in these samples** — consistent with "value adjustment, no stock movement," but with only 1 (Dr) / 11 (Cr) records this is `PENDING BUSY VENDOR` as a general rule. **Do not assume notes never affect stock.**

## 4. Dual voucher numbering & reference fields `CONFIRMED BY EXPORT`
- **Dual numbering:** `VchNo` (manual series no.) **and** `AutoVchNo` both present in Purcs/Sales/DrNts/CrNts (462/462, 454/454, 1/1, 11/11). The **`StTfs` single sample has neither `VchNo` nor `AutoVchNo` in its direct children** — anomaly, `PENDING BUSY VENDOR` (needs more stock-transfer samples).
- **`OriginalID`** appears in **all nine** voucher groups — a candidate to carry/return the MES external reference, **but its value format, semantics and writeability are `PENDING BUSY VENDOR`** (do not assume it is the integration key).
- **Notes carry original-voucher references:** DrNts/CrNts include `tmpOldVchNo`, `tmpOldAutoVchNo`, `tmpOldVchSeriesCode` — a correlation back to the original voucher (relevant to amendment/cancellation modelling). `CONFIRMED BY EXPORT`; semantics `PENDING BUSY VENDOR`.

## 5. MES → BUSY mapping (now against observed containers; import still PENDING)
MES envelope primitives (unchanged, `CONFIRMED BY SOURCE`): deterministic `external_reference` (`backend/src/lib/busy/identity.js`), warehouse-first master mapping hard-fail (`backend/src/lib/busy/mapping.js`), queue states incl. `AWAITING_BUSY`/`MANUAL_REVIEW` + reconciliation + `busy_audit_log` (`queue.js`, `schema.js`).

| MES source (confirmed) | → BUSY container/element (observed name) | Status |
|---|---|---|
| document no. (roll_id / GRN / dispatch / challan) | `VchNo` and/or `AutoVchNo` — which is writable/allocated `PENDING BUSY VENDOR` | PENDING |
| MES external reference (`external_reference`) | `OriginalID` **candidate** — writeability/read-back `PENDING BUSY VENDOR` | PENDING |
| party | `BillingDetails/PartyName` + `Accounts` master | PENDING (mandatory set) |
| item / SKU | `ItemEntries/ItemDetail/ItemName` + `Items` master | PENDING |
| warehouse / material-centre | `ItemEntries/ItemDetail/MC` + `MaterialCenter` master | PENDING |
| qty / weight | `ItemEntries/ItemDetail/Qty`/`QtyMainUnit`/`QtyAltUnit` + `UnitName` | PENDING |
| value / amount | `ItemEntries/ItemDetail/Amt`/`NettAmount` | PENDING |
| date | `Date` / `StockUpdationDate` | PENDING |
| tax (GST) | `BillSundries/BSDetail`, `ItemTaxCategory` (not invented — observed names) | PENDING (mapping rules) |
> These are **target container names observed in an export**, not confirmed importable fields. **No field is asserted mandatory** (the report explicitly does not establish mandatory fields).

## 6. BUSY → MES (purchase read) `CONFIRMED BY USER direction` / fields `PENDING BUSY VENDOR`
Purchase (`Purcs/Purchase`) is read into the MES purchase mirror. Readable structure observed (`BillingDetails`, `ItemEntries`, `AccEntries`, `OriginalID`, `VchNo`/`AutoVchNo`). Exact read mechanism (ACE-OLEDB `.bds` vs file export) and field semantics `PENDING BUSY VENDOR` (doc 20).

## 7. What remains `PENDING BUSY VENDOR`
Import/write format and whether this export can be re-imported; the **supported write interface** (XML import / Sales API / other); **mandatory fields** per voucher; **which groups are creatable** through a supported interface; **numbering allocation** (VchNo vs AutoVchNo); **posting/cancellation/amendment/deletion** behaviour; whether **`OriginalID`** (or another field) can store and return an MES reference; **tax/accounting rules**; inventory/accounting effect of **debit/credit notes and returns**; edition support for import (doc 19 §1/§3).

## 8. Unresolved vendor questions (concise)
1. Supported **import/write interface** and the voucher types creatable through it (export ≠ import).
2. **Mandatory field set** per voucher group for successful creation.
3. Can **`OriginalID`** (or which field) store an MES external reference and be **read back**?
4. **Numbering:** is `VchNo` caller-supplied or allocated by BUSY; role of `AutoVchNo`; why `StTfs` lacks both.
5. **Stock Transfer** full schema — only 1 sample; confirm `ItemEntries` vs `ItemEntries1` = from/to material-centre legs.
6. **Debit/Credit note** inventory & accounting behaviour — do they ever carry stock lines? (samples show none).
7. **Returns** (SlRts/PrRts) required fields and whether they adjust stock and/or create notes.
8. **Job-work** representation — the export embeds `FGJobDetails`/`JobEntries` (`JobID`) inside **Purchase** vouchers; confirm how MES job-work issue/recovery should map (see §9 discrepancy).
9. **Master identity** fields for Accounts/Items/Units/MaterialCenter.
10. **Cancellation/amendment** mechanism and the meaning of `tmpOldVchNo`/`tmpOldAutoVchNo` on notes.
11. **Test company** for import trials (never production).

## 9. Discrepancies with documents 37 and 39
- **Job-work (vs doc 37 #10 and doc 39):** docs 37/39 model job-work as MES→BUSY **`party_issue`/`party_recovery`** (subcontract challans) → a dedicated BUSY job-work voucher. The export instead shows job-work as **`FGJobDetails`/`JobEntries` with `JobID` embedded inside `Purcs` (Purchase) vouchers** (10/462), and `JobEntries/ItemDetail` carries its own item lines. **Implication:** the MES→BUSY job-work mapping may not be a standalone voucher but a purchase-with-JobID (or material issue/receipt with `JobID`). **Flag:** reconcile the doc-39 job-work voucher assumption against this; exact mapping `PENDING BUSY VENDOR`. No doc-39 change made here (documented for review).
- **Debit/Credit notes (vs doc 37 #9):** doc 37 said "inventory: usually none (value adjustment)." The export **corroborates** this (DrNts/CrNts have no `ItemEntries`), strengthening it to `CONFIRMED BY EXPORT (these samples)` — but the universal rule stays `PENDING BUSY VENDOR`. No contradiction.
- **Stock transfer (vs doc 37 #4):** doc 37 marked a dedicated MES transfer workflow as PROPOSED. The export confirms a BUSY `StockTransfer` group **exists** (two MC legs) — but 1 sample only, so low-confidence; the MES-side workflow is still PROPOSED. Consistent.
- **Material issue / receipt / returns (vs doc 37 #2/#3/#7/#8):** the export confirms BUSY groups `MaterialReceipt`, `MaterialIssue`, `SaleReturn`, `PurchaseReturn` **exist** — upgrading those doc-37 rows from "proposed voucher type" to "observed group" (importability still PENDING). Consistent, strengthened.
- **Ownership rule (doc 37):** unchanged and not contradicted by the export. The purchase/GRN `bidirectional:true` code inconsistency (doc 37) still stands as a future task.

---
*Read-only; nothing committed. Based solely on the sanitised report (original `.DAT` not opened). No invented BUSY field/rule; export structure is not treated as import-compatible; no real values included.*
