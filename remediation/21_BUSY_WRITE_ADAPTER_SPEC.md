# 21 — BUSY Write Adapter Specification (Phase 2.2)

**Date:** 2026-11-27 · **Documentation only — NO actual external writes, no voucher import/posting, no connection.** Specifies how the approved write workflows *would* operate once a vendor-supported write method is confirmed. The primary candidate is **XML / Excel voucher import** (`Administration → Data Export/Import`); a licensed **partner dev API** is the alternative.

Legend: **✅ VERIFIED** · **❓ VENDOR-UNKNOWN** · **◻ PROPOSED**.

---

## 1. Mechanism (◻ proposed; ❓ schema unknown)
The write adapter (`XmlDocConnector`) implements `BusyConnector.pushDocument()` by **rendering a validated BUSY-import document (XML or Excel) into a write drop-folder** on the BUSY PC; a person or a scheduled BUSY job imports it; the posted **voucher number** is read back via the **read adapter** (report 20). Because BUSY posts on import (not synchronously), a push resolves to **`AWAITING_BUSY`** and is confirmed later. **BUSY's internal DB is never written directly** (forbidden, enforced in code).

```
MES event → busy_sync_queue → XmlDocConnector.pushDocument()
  → render validated XML/Excel into WRITE_DROP_FOLDER   (status: AWAITING_BUSY)
  → [BUSY import: person or scheduled job]
  → read adapter sees the posted voucher → store busy_reference → status SUCCESS; reconcile
```

## 2. Per-workflow specification

| # | Workflow | Source system | Document identity (`external_reference`) | Duplicate prevention |
|---|---|---|---|---|
| 1 | **Purchase** | MES **or** BUSY (bidirectional) | `<origin>:TRANSACTION:<PO no.>:PURCHASE` | `UNIQUE(external_reference)` + document-origin (BUSY-origin not re-pushed) |
| 2 | **Material receipt / GRN** | MES **or** BUSY (bidirectional) | `<origin>:TRANSACTION:<GRN no.>:MATERIAL_RECEIPT` | same |
| 3 | **External-party issue** | MES → BUSY | `MES:TRANSACTION:<challan no.>:PARTY_ISSUE` | same |
| 4 | **External-party recovery** | MES → BUSY | `MES:TRANSACTION:<receipt id>:PARTY_RECOVERY` (carries `original_ref`) | same |
| 5 | **Dispatch** | MES → BUSY | `MES:TRANSACTION:<dispatch no.>:DISPATCH` | same; **dispatch ≠ sales invoice** (not auto-combined) |

### Required field mappings (❓ confirm against a real BUSY export)
| MES field | BUSY voucher field (❓) |
|---|---|
| party (customer/vendor) | ledger name — **must pre-exist in BUSY** (mapped via `busy_master_mapping`) |
| warehouse / material-centre | BUSY material-centre code — **mapped, 1:1, hard-fail if unmapped** |
| item | BUSY item/ledger — mapped |
| qty / weight / amount | voucher line qty/value |
| date | voucher date (open FY period) |
| document no. | our `external_reference` carried in a BUSY narration/reference field (❓ which) |
| GST (CGST/SGST/IGST) | tax ledgers per the company's tax config (❓) |

### Validation rules (in our bridge, before rendering)
- Party, warehouse and item **must be mapped & SYNCED** (else the event → `MANUAL_REVIEW`, never a bad import).
- Voucher date within an **open** FY period.
- Balanced/complete document; amounts Decimal-safe.
- For purchase/receipt: **document origin** respected — a BUSY-originated document is not re-sent (no circular sync).

## 3. Common write-path requirements
| Concern | Spec |
|---|---|
| **Voucher import mechanism** | render XML/Excel to the write drop-folder; import performed BUSY-side (person or scheduled job — ❓). No preview in BUSY ⇒ all validation is ours. |
| **Voucher reference retrieval** | via the read adapter: match our `external_reference` (carried in a BUSY field) → read the assigned **voucher no.**; store as `busy_reference`. |
| **Posting confirmation** | `getPostingStatus(busy_reference)` from the mirror confirms POSTED → queue `SUCCESS`; until then `AWAITING_BUSY`. |
| **Duplicate prevention** | DB-enforced `UNIQUE(external_reference)`; idempotent enqueue; the same document is never imported twice (and a re-import of the same file is a no-op by reference). |
| **Failure recovery** | transient → `RETRY` + backoff; exhausted → `MANUAL_REVIEW`; permanent (e.g., unmapped master) → rejected to `MANUAL_REVIEW`; append-only `busy_audit_log`; **dead-letter** = rows stuck in `MANUAL_REVIEW`/`FAILED` surfaced on a dashboard. |
| **Reconciliation** | scheduled run compares queue (`SUCCESS`/`AWAITING_BUSY`) vs the BUSY mirror → `MATCH/MISMATCH/MISSING_IN_BUSY` into `busy_reconciliation`; an `AWAITING_BUSY` with no voucher after a threshold is alerted. |
| **Cancellation / amendment** | ❓ BUSY-side behaviour unknown — see report 22 decision; until defined, amendments create a **new** correlated document, never a silent overwrite. |

## 4. What the current code already provides (✅ built, mock-proven)
`busy_sync_queue` (idempotent, retry/backoff, states incl. `AWAITING_BUSY`/`MANUAL_REVIEW`), `identity.makeExternalReference` (deterministic key + origin), `mapping` (warehouse hard-fail/conflict), `queue.reconcile`, `busy_audit_log`, and the `pushDocument` contract. The write adapter only needs the **renderer** (XML/Excel) + the **reference-readback wiring** — both gated on the ❓ items below.

## 5. Vendor-dependent unknowns (❓ — confirm before build)
1. The **real XML/Excel import schema** per voucher type (needs a sample export from the customer's BUSY).
2. Which BUSY field carries/returns our **integration reference**.
3. Who triggers the import (person vs scheduled job) and the drop-folder location.
4. GST/tax-ledger mapping for imported vouchers.
5. BUSY's **cancellation/amendment** behaviour for imported vouchers.
6. Whether a **partner dev API** is licensed (would replace the file path with a direct, still-abstracted adapter).

**No write adapter is implemented in this phase.** Implementation begins only after the §5 unknowns and report 19 are answered, with management + vendor sign-off.
