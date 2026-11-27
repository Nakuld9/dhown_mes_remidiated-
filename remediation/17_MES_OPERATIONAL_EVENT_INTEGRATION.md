# 17 — MES Operational Event Integration (Phase 2.1)

**Date:** 2026-11-27 · Branch `claude/mes-busy-remediation`.
**Scope:** connect the real MES operational workflows to the **mock** BUSY bridge, **feature-flagged OFF by default**. **No real BUSY connection, no live writes/voucher posting, no deployment.** Existing workflows, screens, permissions, validations and transaction behaviour are unchanged.

---

## 1. Design — why this is safe to add to live workflows
`capture()` does exactly one thing: an **idempotent INSERT into `busy_sync_queue`**. It resolves no mapping and calls no connector — **mapping resolution and the push happen later, at queue PROCESS time, fully decoupled from the business write.** Therefore:
- An unmapped warehouse or a BUSY failure can **never** roll back or alter a factory operation.
- When a workflow's flag is **OFF**, `capture()` returns immediately touching no DB — a **guaranteed no-op, zero side effects**.
- Capture is wired **non-invasively**: `captureMw(workflow)` is a middleware inserted *before* the create handler in the route chain (route registration only — the verbatim handlers/controllers are untouched). It wraps `res.json` so capture runs **after a successful (2xx) response**, fire-and-forget, wrapped so it can never break the HTTP response.

## 2. Event mapping (each workflow → integration event)
`external_reference = <origin>:TRANSACTION:<dhown_entity_id>:<operation>` (deterministic idempotency key + origin).

| Workflow | Flag | Direction | operation | dhown_entity_id | key payload fields |
|---|---|---|---|---|---|
| Purchase | `BUSY_EVENT_PURCHASE` | MES ↔ BUSY | `PURCHASE` | PO number | supplier, origin |
| GRN / material receipt | `BUSY_EVENT_GRN_RECEIPT` | MES ↔ BUSY | `MATERIAL_RECEIPT` | GRN number | warehouse_code, supplier, amount, origin |
| External-party issue | `BUSY_EVENT_PARTY_ISSUE` | MES → BUSY | `PARTY_ISSUE` | challan number | party, qty, warehouse_code |
| External-party recovery | `BUSY_EVENT_PARTY_RECOVERY` | MES → BUSY | `PARTY_RECOVERY` | receipt id | party, qty, **original_ref** (→ issue) |
| Dispatch | `BUSY_EVENT_DISPATCH` | MES → BUSY | `DISPATCH` | dispatch number | customer, dispatch_type |

**Internal-only (never emit a BUSY voucher):** material issue to machine, shift-wise production, machine/operator/shift/roll recording. Not wired.

## 3. Wired hook points (route registration only)
| Route | Workflow |
|---|---|
| `POST /api/grn` | grn_receipt |
| `POST /api/dispatch` | dispatch |
| `POST /api/purchase-orders` | purchase |
| `POST /api/subcontract/challans` | party_issue |
| `POST /api/subcontract/challans/:id/receive` | party_recovery |

## 4. Feature flags
- Default: **all OFF.** Enabled per workflow via env `BUSY_EVENT_<WORKFLOW>=on`, or `BUSY_EVENTS=all` / a comma list. Tests use an explicit `enabled` override (no process-global env needed).
- When disabled: existing MES workflows behave exactly as before; **no integration-queue side effects**.
- When enabled (tests only): events reach **only the mock adapter**; no real BUSY connection is attempted; no external voucher is posted.

## 5. Transaction boundaries
- `capture()` accepts a `db` that may be a **pool** or an **open client**. Passing a client makes it a **transactional outbox** (the event commits/rolls back with the business write). Verified: a capture inside a **rolled-back** transaction leaves **no event**.
- The wired `captureMw` runs **after** a successful response (post-commit, at-least-once + idempotent). An interrupted business write returns non-2xx → **no capture**. The rare commit-then-crash window is covered by idempotency + reconciliation. (Same-txn hooks can replace the middleware at each commit point in a later pass without changing the contract.)

## 6. Queue behaviour & audit (from Phase 2)
- **Idempotency / duplicate prevention:** `UNIQUE(external_reference)` → duplicate/concurrent/replayed deliveries collapse to one row.
- **Concurrency-safe processing:** atomic claim; an already-SUCCESS row is never re-pushed.
- **Retry:** transient → `RETRY` + backoff; exhausted → `MANUAL_REVIEW`; permanent → `FAILED`.
- **Warehouse control:** at process time, an event carrying a `warehouse_code` is resolved against `busy_master_mapping`; **unmapped → rejected to `MANUAL_REVIEW`** (no push, no auto-create, no auto-remap). Conflicts (one BUSY id ↔ two DHOWN ids) → `MANUAL_REVIEW` (no silent merge). BUSY is authoritative for the warehouse master.
- **Origin & circular-sync:** `document_origin` on every row; a **BUSY-originated** purchase/receipt is **not** pushed back to BUSY.
- **Correlation:** recovery carries `original_ref` → stays linked to its issue; party outstanding = Σ issued − Σ recovered.
- **Audit:** every outcome appended to `busy_audit_log` (append-only). **Reconciliation** compares MES-stored vs BUSY references.

## 7. Outstanding vendor & business dependencies (before enabling outward-facing)
1. Real BUSY write method (XML/Excel DOC vs partner API) + edition/licence + deployment topology (report 14).
2. The real document→BUSY field mappings and how the **voucher reference** returns.
3. Confirm **party/item** master source-of-truth (warehouse = BUSY, built).
4. Confirm BUSY authors **all** statutory invoices (dispatch stays separate from sales invoicing).
5. A real BUSY instance to validate compatibility — the mock proves the bridge only.
