# 39 — Job-Work (Subcontract) Inventory Reconciliation Design

**Date:** 2026-11-28 · **Branch:** `claude/mes-busy-remediation` · **HEAD:** `2055c94`.
**Documentation only.** No code/schema/migration change; no BUSY connection; no live write. **MES is authoritative for job-work quantities** (doc 22 **D7**, built & tested); BUSY receives the accounting document only. No BUSY voucher type/field invented; no real party/financial values included.

**Labels:** `CONFIRMED BY SOURCE` (verified in code, path cited) · `CONFIRMED BY DOC` (doc 22 D7) · `CONFIRMED BY USER` (frozen rule: job-work is MES→BUSY) · `PROPOSED` · `PENDING MGMT` (tolerance/threshold) · `PENDING BUSY VENDOR`.

## Scope
Track, per job-work party (subcontractor), the full material lifecycle: **sent → received back → consumed → wastage → finished goods received**, and the **party-wise outstanding quantity**. Ownership: **MES authoritative**; direction **MES → BUSY** `CONFIRMED BY USER` + `CONFIRMED BY DOC (D7)`.

## Existing building blocks `CONFIRMED BY SOURCE`
- **Issue (send):** `backend/src/routes/subcontract.routes.js` `POST /challans` → `subcontract_challans` + `subcontract_challan_items` (vendor_name, job_type, sent_date, fabric_type, color, roll_count, **weight_kg**); captures the `party_issue` BUSY event.
- **Recovery (receive back):** `subcontract_receipts` (joined to challans); captures `party_recovery`, carrying `original_ref` back to the issuing challan.
- **Correlation & outstanding:** deterministic `external_reference` with `original_ref` (`backend/src/lib/busy/identity.js`); **outstanding = Σ issued − Σ recovered**, correlated by `original_ref` (doc 22 **D7**, built & tested).
- **Costing:** `addCostEntry` records subcontract cost components (rate_per_kg × weight) — cost/accounting is BUSY's domain; MES holds the operational basis. `CONFIRMED BY SOURCE`.

## Quantity model (per party, per material/fabric) `PROPOSED` (extends D7)
Let, for a party `p` and material `m`:
```
sent(p,m)       = Σ weight_kg of challan items issued          (subcontract_challan_items)
received(p,m)   = Σ weight_kg received back                    (subcontract_receipts)
                  split into:  finished_goods(p,m) + returned_unprocessed(p,m)
consumed(p,m)   = input material converted into finished goods (process-defined)
wastage(p,m)    = sent − received − expected_conversion_loss?  ← definition PENDING MGMT
outstanding(p,m)= sent − received                              (D7, confirmed)  [in party's hands]
```
- **`outstanding` is confirmed** as Σsent − Σreceived, correlated by `original_ref` `CONFIRMED BY DOC (D7)`.
- **`consumed`, `wastage`, `finished_goods` vs `returned_unprocessed` splits are `PROPOSED`** — they need the process definition and an **acceptable wastage tolerance**, which is a **`PENDING MGMT`** decision (not invented here).

## Reconciliation checks `PROPOSED`
1. **Balance identity:** for every party/material, `sent = received_back + still_outstanding`. *Flag:* `JOBWORK_BALANCE_MISMATCH`.
2. **Finished-vs-input:** `finished_goods_received + wastage + returned_unprocessed ≈ consumed input` within tolerance. *Flag:* `YIELD_OUT_OF_TOLERANCE` (tolerance `PENDING MGMT`).
3. **Wastage ceiling:** `wastage(p,m) ≤ allowed_wastage%`. *Flag:* `WASTAGE_EXCEEDS_LIMIT` (limit `PENDING MGMT`).
4. **Ageing of outstanding:** material in a party's hands beyond N days. *Flag:* `OUTSTANDING_AGEING` (N `PENDING MGMT`).
5. **Correlation integrity:** every recovery has a valid `original_ref` to an issue; no orphan recovery. *Flag:* `UNLINKED_RECOVERY` `CONFIRMED BY SOURCE` (identity model).
6. **MES↔BUSY document parity:** each `party_issue`/`party_recovery` has its BUSY accounting document (once the adapter exists). *Flag:* `MISSING_IN_BUSY` `PENDING BUSY VENDOR`.

## Outcome handling `PROPOSED`
- Each check yields `MATCH | MISMATCH | MISSING`; mismatches are **surfaced to MANUAL_REVIEW, never auto-adjusted**; full audit in `busy_audit_log`/`audit_logs`.
- **MES quantities remain authoritative**; BUSY reflects the accounting document. A reconciliation mismatch never silently rewrites MES stock or the party's outstanding.

## Reporting (party-wise) `PROPOSED`
Per subcontractor: opening outstanding, sent, received (finished + unprocessed), consumed, wastage, closing outstanding, ageing buckets — all in **quantity/weight** (value is BUSY's domain). Reuses the existing subcontract data; no new authoring of accounting.

## Tolerances & thresholds — `PENDING MGMT` (none invented)
| Threshold | For | Status |
|---|---|---|
| Allowed wastage % per job type/material | checks 2/3 | **PENDING MGMT** |
| Expected conversion/yield band | check 2 | **PENDING MGMT** |
| Outstanding ageing window (N days) | check 4 | **PENDING MGMT** |
| Reconciliation cadence | scheduling | **PENDING MGMT** |

## Unresolved (this document)
- `PENDING MGMT`: wastage %, yield band, ageing window, cadence; the precise definitions of `consumed` / `finished_goods` / `returned_unprocessed`.
- `PROPOSED`: the consumed/wastage/finished split model (D7 confirms only sent/received/outstanding).
- `PENDING BUSY VENDOR`: the BUSY job-work voucher type/fields for the MES→BUSY accounting document (doc 38) and MES↔BUSY parity check 6.

*Read-only; nothing committed. No BUSY connection, no live write, no invented voucher type/field, no real values.*
