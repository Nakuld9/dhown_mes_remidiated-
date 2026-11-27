# 18 — Operational Event Integration Test Report (Phase 2.1)

**Date:** 2026-11-27 · Branch `claude/mes-busy-remediation` · Code commit `9d660fe` (this report follows).
**Mock-backed, feature-flagged OFF by default.** No production contact, no real BUSY connection, no live writes/voucher posting, no deployment. Recovered baseline unchanged.

> **Honesty:** results prove the **integration wiring + bridge** behave correctly. They do **NOT** prove real BUSY 21 compatibility (mock adapter).

---

## 1. Regression — baselines preserved, on two independent fresh PG18.7 DBs
| Check | Result |
|---|---|
| Provision (from zero, each DB) | **72 OK / 0 FAIL · 185 public + 22 acct tables** |
| Unit (Jest) | **262 / 262 PASS** (preserved) |
| BUSY reconciliation (`busy-mirror`) | **14 / 14 ALL-PASS** (preserved) |
| Full DB-backed e2e | **48 / 48 PASS on BOTH DBs** (47 preserved + 1 new operational-events) |
| Structure reg_1 vs reg_2 | **column md5 IDENTICAL** — zero drift |

**Existing MES workflow regression:** the 47 prior e2e suites run **unchanged with flags OFF**, booting the server with the new `captureMw` wiring in place → proves the hooks are a **pure no-op by default** (no behaviour, permission, validation or transaction change).

## 2. Operational-event integration coverage (`tests/operational-events.e2e.js`) — all PASS
| Requirement | Verified |
|---|---|
| Every supported operational event | all 5 (purchase, grn_receipt, party_issue, party_recovery, dispatch) capture, mapped to the correct BUSY operation |
| Feature flags disabled (default) | `capture()` is a no-op; **zero** integration-queue side effects |
| Feature flags enabled | each workflow enqueues exactly one bridge event |
| Duplicate event delivery | duplicate → **one** queue row |
| Concurrent event processing | 6 concurrent deliveries → **one** row |
| Interrupted transactions | capture inside a **rolled-back** txn leaves **no** event (transactional outbox) |
| Circular-synchronisation prevention | a **BUSY-originated** purchase is **not** pushed back to BUSY |
| Warehouse mapping conflicts | unmapped `warehouse_code` → **rejected `MANUAL_REVIEW`** at process time (no push, business untouched); mapped → SUCCESS |
| Party-wise issued/recovered/outstanding | issued − recovered = 100 − 60 = **40**; recovery correlated to the issue (`original_ref`) |
| Dispatch separation from sales invoicing | dispatch emits `DISPATCH` only — **no** sales-invoice event |
| Failed and retried events | transient → `RETRY` → `SUCCESS` after it clears (through the queue) |

## 3. Changed files (commit `9d660fe`)
**New:** `backend/src/lib/busy/operational-events.js` (capture layer + `captureMw` + mappers), `backend/tests/operational-events.e2e.js`.
**Modified (route registration only — verbatim handlers/controllers untouched):** `backend/src/routes/{grn,dispatch,purchase-orders,subcontract}.routes.js` (add `captureMw`).
**Modified (bridge):** `backend/src/lib/busy/queue.js` (warehouse-mapping rejection before push), `backend/src/lib/busy/index.js` (pass mapping into the queue).
**Docs:** `remediation/17_...`, `18_...` (this), `STATUS.md`.
**Unchanged:** `backend/schema/00_baseline_schema.sql` (recovered baseline); no accounting retirement; no factory-workflow change; no invoice/financial-policy change.

## 4. Intentional test changes (reported separately, per instruction)
- **No existing test was modified or weakened** in Phase 2.1. The only test change is the **new** `operational-events.e2e.js` suite (additive). The Phase-1.5 test fixtures/exemptions remain as documented in report 13.

## 5. Transaction boundary (honest)
`capture()` supports a true transactional outbox (accepts an open client); the **standalone test uses it in-transaction** and proves rollback-safety. The **wired production hooks** (`captureMw`) capture **post-commit** (after a 2xx response) — at-least-once + idempotent + reconcilable; an interrupted business write (non-2xx) produces no event. Same-txn hooks can replace the middleware at each commit point later without changing the contract.

## 6. Exact commands (reproducible)
```bash
DB_NAME=<scratch> node backend/scripts/db-provision.js                 # 72 OK/0 FAIL, 185 tables
cd backend && DB_NAME=<scratch> node tests/operational-events.e2e.js   # all PASS
npx jest --ci                                                          # 262/262
# full e2e (server booted per DB, flags OFF): 48/48 on two fresh DBs
```
Flags are OFF unless `BUSY_EVENT_<WORKFLOW>` / `BUSY_EVENTS` is set; the test uses an explicit `enabled` override. No `BUSY_*` credentials are set or needed.

## 7. Outstanding vendor & business decisions (before any real connection/write)
Unchanged from report 14 §6 / 17 §7: BUSY edition/licence + deployment topology; real write method (XML/Excel DOC vs partner API) + field mappings + how the voucher reference returns; confirm party/item master SoT; confirm BUSY authors all statutory invoices; a real BUSY instance to validate compatibility.

**Stopping after Phase 2.1. Requesting approval before implementing a real BUSY adapter or enabling outward-facing integration.**
