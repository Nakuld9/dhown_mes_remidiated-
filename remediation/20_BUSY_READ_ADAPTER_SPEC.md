# 20 — BUSY Read Adapter Specification (Phase 2.2)

**Date:** 2026-11-27 · **Documentation only — no real BUSY connection.** Specifies the first **real read adapter** using the **only confirmed vendor-supported read method**: ACE-OLEDB read of the password-protected `.bds`. It implements the read side of the `BusyConnector` contract (`health`, `listMasters`, `getDocumentReference`, `getPostingStatus`).

Legend: **✅ VERIFIED** · **❓ VENDOR-UNKNOWN** · **◻ PROPOSED**.

---

## 1. Method (✅ verified, read-only)
BUSY stores each company/FY as an **MS-Access JET 4.0 `.bds`**, opened via **ACE-OLEDB** `Mode=Read` with the fixed Jet password — **SELECT only, never a write**. ACE-OLEDB is Windows-only, so the reader runs on the BUSY/accounts PC. This is the pattern the committed `tools/busy-bridge/extract-busy.ps1` already proves on `COMP0004`.

**Topology (◻ proposed):** a Windows-side extractor reads the `.bds` → writes a normalised JSON "busy-mirror/v1" document to a **drop-folder** → the MES ingests it into the existing read-mirror (`lib/busy-bridge.js` `busy_*` tables), exactly like the Bank-H2H drop-folder pattern. The MES (Linux/Docker) never opens ACE-OLEDB itself.

```
BUSY PC: extract-busy.ps1 (ACE-OLEDB, read-only) ──JSON──▶ DROP_FOLDER ──▶ MES ingest ──▶ busy_* read-mirror
                                                                              └▶ AceOledbReadConnector.listMasters()/getDocumentReference()
```

## 2. Objects to read

| Object | Source (✅ semantics validated on COMP0004) | Fields |
|---|---|---|
| **Company details** | company meta `.bds` / FY header | name, GSTIN, PAN, address, FY start/end |
| **Party masters** (CUSTOMER/VENDOR) | `Master1` MasterType=2 (ledger) under debtor/creditor groups; `ParentGrp` tree | ledger id, name, group, GSTIN, PAN, state, address, **opening balance** |
| **Item masters** | item master table | ❓ confirm table/columns (item code, name, unit, HSN) |
| **Warehouse / material-centre masters** | ❓ confirm table | centre id, code, name — the key for mapping |
| **Voucher references** | `Tran2` (`RecType=1`) headers | voucher no., type, date, series, party, amount |
| **Ledger balances / accounting** | `Tran2` movement `SUM(Value1)` per ledger (`<0`=Dr, `>0`=Cr); opening postings included | per-ledger closing, trial balance, P&L/BS totals |

## 3. `BusyConnector` read methods (how the adapter implements them)
- **`health()`** — reports whether a fresh mirror exists and its `as_of`; stale mirror ⇒ `online:false`. Updates `busy_connection_state`.
- **`listMasters(entityType)`** — returns the mirrored masters for `WAREHOUSE`/`CUSTOMER`/`VENDOR`/`ITEM` (from the JSON mirror), feeding `mapping.syncWarehousesFromBusy` etc.
- **`getDocumentReference(external_reference)`** — resolves a MES document to its BUSY voucher no. by matching on the integration key we wrote into the voucher narration/ref (❓ confirm which BUSY field carries our `external_reference`), read from the mirror.
- **`getPostingStatus(busy_reference)`** — confirms a voucher exists/posted in the mirror (the read side is how write-posting is confirmed, since BUSY posts on import).
- `capabilities()` → `{ method:'ACE_OLEDB_READ', can_read_masters:true, can_push_document:false, can_read_posting_status:true, writes_directly_to_busy_db:false }`.

## 4. Non-functional requirements
| Concern | Spec |
|---|---|
| **Pagination / volume** | The extractor exports full master sets + a **date-ranged** day book (`from`/`to`) to bound size; large companies export incrementally per FY. The MES ingests whole documents transactionally (replace-mirror). |
| **Timeout** | Per-query ACE timeout (◻ 30 s); the extractor fails the whole run atomically rather than writing a partial JSON. |
| **Error handling** | A failed/locked `.bds` read ⇒ no JSON written (never a partial mirror); the previous mirror stays valid and is marked stale by `as_of`. Ingest validates the JSON schema before replacing the mirror. |
| **Retry** | The extractor is a scheduled job (logon task / Windows service); a failed run retries on the next tick. Ingest is idempotent (replace by `source`+`as_of`). |
| **Reconciliation** | The existing `busy-mirror` reconciliation (validated 14/14) compares MES-derived TB vs BUSY TB to the rupee; extend to reconcile **document references** (MES outbound `busy_reference` vs the mirror) via `busy_reconciliation`. |
| **Freshness / schedule** | ◻ mirror refresh every N minutes/hours (business decision — report 22); every row carries `source` + `as_of` so the UI shows "as of <when>, from <where>". |
| **Security** | `.bds` Jet password + file-share creds in **environment/secret config only**; least-privilege read account; drop-folder readable by MES, writable only by the extractor. |

## 5. Vendor-dependent unknowns (❓ — confirm before build)
1. The **item** and **warehouse/material-centre** master tables/columns in the `.bds`.
2. Which BUSY voucher field can carry/return our **integration reference** (to link a MES document to its BUSY voucher no.).
3. Exact `.bds` file paths + whether the MES host can reach them or a shared folder.
4. The 64-bit ACE Database Engine is installed on the BUSY PC (ships with BUSY/Office).

## 6. Explicitly out of scope here
No real connection, no live read against the production `.bds`, no credentials used. Implementation begins only after report 19 §1–7 and these §5 unknowns are answered, under a later phase and approval.
