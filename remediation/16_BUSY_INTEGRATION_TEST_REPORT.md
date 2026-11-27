# 16 — BUSY Integration Test Report (Phase 2, mock-first)

**Date:** 2026-11-27 · Branch `claude/mes-busy-remediation` · Code commit recorded below.
**Everything runs against the mock connector on isolated PostgreSQL 18.7 scratch DBs.** No production contact, no live BUSY connection/writes, no deployment, recovered baseline unchanged.

> **Honesty:** these results prove the **bridge** (idempotency, retry, reconciliation, mapping, concurrency) is correct. They do **NOT** prove real BUSY 21 compatibility — that requires a confirmed vendor method and a real instance (see report 14 §3).

---

## 1. Regression — baselines preserved, on two independent fresh DBs
| Check | Result |
|---|---|
| Provision (from zero, each DB) | **72 OK / 0 FAIL · 185 public + 22 acct tables** (180 + the 5 bridge tables) |
| Unit (Jest) | **262 / 262 PASS** (preserved) |
| BUSY reconciliation (`busy-mirror`) | **14 / 14 ALL-PASS** (preserved) |
| Full DB-backed e2e | **47 / 47 PASS on BOTH DBs** (46 preserved + 1 new bridge suite) |
| Structure reg_1 vs reg_2 | **column md5 IDENTICAL** — zero drift |

## 2. Integration test coverage (`tests/busy-integration.e2e.js`)
All **PASS** against the mock:

| Scenario (required) | Assertion verified |
|---|---|
| **Duplicate documents** | same event enqueues once; the duplicate is a no-op; exactly one queue row per `external_reference` |
| **Concurrent events** | 5 concurrent enqueues of one event → **1 row**; 3 concurrent `process()` of one row → **1 push** (one SUCCESS audit) |
| **Replayed events** | reprocessing a SUCCESS row is an idempotent no-op (no second push) |
| **Retries / interrupted sync** | transient failure → `RETRY` (not FAILED); succeeds after the transient clears; `attempt_count` reflects retries |
| **Partial failures** | permanent failure → `FAILED` (not retried forever); recorded in the audit log |
| **Mapping mismatches** | a BUSY id already mapped to another DHOWN id → `MANUAL_REVIEW` (no silent merge) |
| **Invalid warehouse/material-centre references** | an unmapped centre **HARD-FAILS** (`MAP_MISSING`); no auto-create |
| **BUSY→MES warehouse sync** | matches map 1:1; unmatched → `MANUAL_REVIEW` (BUSY authoritative) |
| **Party-wise outstanding** | issued − recovered = 100 − 60 = **40**; recovery stays linked to the original issue (`original_ref`) |
| **Reconciliation** | pushed documents reconcile as **MATCH** (6 match, 0 mismatch) |

## 3. What was built (changed files)
**New module `backend/src/lib/busy/`:** `schema.js` (5 integration-state tables), `connector.js` (interface + capabilities + `selectConnector`), `adapters/mock.js` (MockBusyConnector), `identity.js` (external_reference + origin), `mapping.js` (warehouse-first master mapping), `queue.js` (idempotent enqueue / atomic claim / retry / reconcile / audit), `index.js` (factory).
**Wiring:** `backend/scripts/db-provision.js` + `backend/server.js` — `busy-integration.ensure` added to provisioning and boot (→ 185 tables).
**Tests:** `backend/tests/busy-integration.e2e.js` (new).
**Docs:** `remediation/14_BUSY_CONNECTOR_DESIGN.md`, `15_BUSY_WORKFLOW_MAPPING.md`, `16_...` (this).
**Unchanged:** `backend/schema/00_baseline_schema.sql` (recovered baseline preserved); no accounting retirement; no factory-workflow change.

## 4. Exact commands (reproducible)
```bash
DB_NAME=<scratch> node backend/scripts/db-provision.js        # 72 OK/0 FAIL, 185 tables
cd backend && DB_NAME=<scratch> node tests/busy-integration.e2e.js   # all bridge checks PASS
npx jest --ci                                                 # 262/262
node tests/busy-mirror.e2e.js                                 # 14/14
```
Default connector = `mock`. No `BUSY_*` credentials are set or needed; a real connector is never selected by default.

## 5. Source-of-truth & safety (held)
MES = operations SoT, BUSY = accounting SoT, bridge = integration state only (no second ledger). `assertConnector` **refuses** any adapter that would write BUSY's internal DB. Credentials belong in environment config, never source.

## 6. Remaining vendor & business decisions (before any real connection or write)
1. BUSY **edition/version/licence** + deployment topology (XML import excluded from Basic).
2. Real **XML/Excel voucher-import schema** (or a licensed partner-dev API) → build `XmlDocConnector`.
3. Who triggers the BUSY-side import and how the **voucher reference** returns.
4. Master SoT per entity (warehouse = BUSY built/assumed; confirm **party** & **item**).
5. Confirm BUSY authors **all** statutory invoices (dispatch stays separate from sales invoicing).

**Stopping after this mock-first foundation. Requesting approval before any real BUSY connection or write integration.**
