# 15 — BUSY Workflow & Master-Data Mapping (Phase 2)

**Date:** 2026-11-27 · Design for the mock-first bridge. **No workflow is changed**; this maps the *existing* approved workflows onto the integration layer. No live writes.

---

## 1. Source-of-truth (unchanged)
- **DHOWN MES** — manufacturing/operations SoT: machines, rolls, operators, shifts, production, downtime, quality, physical stock & movement, party balances.
- **BUSY 21** — financial/accounting SoT: GL, vouchers, invoices, GST, party accounting balances.
- **Bridge** — integration state only: mapping, queue, idempotency, retry, reconciliation, audit. **Never a second ledger.**

## 2. Master-data mappings (`busy_master_mapping`)
IDs are never assumed equal; every cross-reference crosses the mapping table. `entity_type ∈ {CUSTOMER, VENDOR, ITEM, WAREHOUSE, TRANSACTION}`.

| Master | Authoritative | Sync | Rule |
|---|---|---|---|
| **Warehouse / material-centre** | **BUSY** | BUSY→MES (`syncWarehousesFromBusy`) | **1:1, exact.** Unmatched → `MANUAL_REVIEW`. An unmapped centre **HARD-FAILS** any push (`requireBusyId` throws `MAP_MISSING`). **No auto-create, no auto-remap.** |
| Party (customer/vendor) | Configurable (default BUSY for accounting identity) | BUSY→MES | Mismatch → `MANUAL_REVIEW`. A BUSY id already mapped to another DHOWN id is refused (partial-unique index + code) — **no silent merge**. |
| Item | Configurable (default MES SKU ↔ BUSY ledger item) | MES→BUSY | Same conflict handling. |

## 3. Workflow → integration mapping
`external_reference = <origin>:<entity_type>:<dhown_entity_id>:<operation>` (deterministic idempotency key, encodes origin).

| # | Workflow | Direction | entity_type / operation | Notes |
|---|---|---|---|---|
| 1 | **Purchase** | **MES ↔ BUSY** (bidirectional) | TRANSACTION / `PURCHASE` | See §4 origin/conflict policy. |
| 2 | **Material receipt** | **MES ↔ BUSY** (bidirectional) | TRANSACTION / `MATERIAL_RECEIPT` | Must preserve the **same warehouse/material-centre** both sides (mapping, hard-fail unmapped). |
| 3 | Warehouse/material-centre master | **BUSY authoritative** | WAREHOUSE / master sync | §2. |
| 4 | Material issue to machine | **MES internal** | — | Not synced. |
| 5 | Shift-wise production | **MES internal** | — | Not synced. |
| 6 | **External-party material issue** | **MES → BUSY** | TRANSACTION / `PARTY_ISSUE` | payload carries `party`, `qty`; outstanding tracked (§5). |
| 7 | **External-party material recovery** | **MES → BUSY** | TRANSACTION / `PARTY_RECOVERY` | payload carries `party`, `qty`, **`original_ref`** linking to the issue (§5). |
| 8 | **Dispatch** | **MES → BUSY** | TRANSACTION / `DISPATCH` | Returns a BUSY voucher reference; **dispatch is NOT auto-combined with sales invoicing** (separate, per the approved process). |

## 4. Bidirectional Purchase/Receipt — origin & conflict policy
Both systems can *initiate* a purchase/receipt, so the bridge does **not** assume they can independently create the same document. Rules:
- **document_origin** is recorded on every queue row (`MES` or `BUSY`) and encoded into the `external_reference`.
- **Origin wins creation.** A document that originated in BUSY is **mirrored into MES** (read-bridge/ingest), and MES does **not** re-push it to BUSY (and vice-versa). The origin tag prevents a round-trip re-create.
- **Unique integration id.** `external_reference` is unique (DB-enforced) → the same logical document cannot be created twice regardless of which side submits.
- **Conflict detection.** If both sides present a document for the same business key with different content, reconciliation records a `MISMATCH` for manual resolution — never a silent overwrite.
- **Returned reference.** After BUSY posts (likely via file import → `AWAITING_BUSY`), the BUSY voucher/doc reference is stored on the queue row (`busy_reference`) and is the traceable link.

## 5. Party-wise outstanding (workflows 6–7)
- Every `PARTY_RECOVERY` carries `original_ref` → stays linked to its `PARTY_ISSUE` (traceable).
- **Outstanding (per party) = Σ issued − Σ recovered.** Verified in the integration test (100 issued − 60 recovered = 40). This is an MES-side operational balance (the subcontract module remains the detailed SoT); the bridge preserves the linkage and feeds BUSY the accounting document.

## 6. Idempotency, retry & reconciliation design
- **Idempotent enqueue:** `INSERT … ON CONFLICT (external_reference) DO NOTHING` → a replayed/concurrent submission is a no-op returning the existing row.
- **Concurrency-safe processing:** atomic claim (`UPDATE … WHERE status IN ('PENDING','RETRY')`), so two processors can't double-push; an already-`SUCCESS` row is never re-pushed.
- **Retry:** transient failure → `RETRY` with exponential backoff (`next_retry_at`); after `BUSY_MAX_ATTEMPTS` (default 5) → `MANUAL_REVIEW`; permanent failure → `FAILED` immediately.
- **Async posting:** file-import style → `AWAITING_BUSY` until the reference is confirmed.
- **Reconciliation:** compares each handled document's MES-stored reference vs BUSY (`getDocumentReference`) → `MATCH / MISMATCH / MISSING_IN_BUSY` into `busy_reconciliation`.
- **Audit:** every outcome appended to `busy_audit_log` (append-only).

## 7. Open business/vendor confirmations
- Master SoT per entity (warehouse = BUSY assumed/built; confirm party & item).
- Whether BUSY authors **all** statutory invoices (so MES pushes only the operational dispatch, never a tax invoice).
- The real BUSY write method (XML/Excel vs partner API) — see report 14.
