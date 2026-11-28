# 31 — Production Simulator Integration Test Report

**Date:** 2026-11-28 · **Branch:** `claude/mes-busy-remediation` · **Base commit:** `7b62642`
**Isolated, mock-only integration testing.** No real machine / cloud / scale / BUSY / production connection; simulator **not wired into `server.js`** or any live route; all simulator flags **OFF by default**; **no production record created/updated/deleted**; **no schema or migration change**; no existing roll/machine/operator/downtime code deleted or refactored; no security/auth weakened.

---

## 1. What was added
- **`backend/test/production-sim.integration.test.js`** — 18 integration tests composing the `production-sim` units across multiple machines / operators / scales.
- **This report.**
- **No simulator-only fix was required** — the module passed every scenario unchanged. `git diff HEAD` shows **no change** to `backend/src/lib/production-sim/` or any production file; the only added code file is the new test.

## 2. Isolation & safety proof (quality gates)
- **No real engine:** the completion manager is driven with a **spy** `rollEngine`; with no engine injected it **refuses to finalise** (`defaultGuardEngine` throws) — a mock event can never write a real roll. Asserted in the `ISOLATION` block.
- **No DB / network:** tests are pure/in-memory; a test asserts `completion-manager.js` source contains **no** `config/database`, `pg`, `http`, `net` or `socket` reference. Importing the module performs no I/O.
- **Flags OFF:** `build()` with no override constructs nothing (asserted).
- **Invariants intact (owned by the unchanged `rolls.js`):** the simulator **never fabricates a roll id** — the id passed in is the exact id finalised, and it matches the existing format `^DHM-…-\d{8}-[A-Z]-\d{3}$`; **one pending (open) roll per machine** — a duplicate completion never opens a second pending (asserted).
- **No production writes or external connections occur** — the only persistence boundary is the injected spy.

## 3. Scenario coverage & results
| # | Scenario | Result |
|---|---|---|
| 1 | Multiple machines concurrently (SJ03/RB01/IL05) | ✅ independent state per machine |
| 2 | Multiple operators + correct attribution; wrong operator → MANUAL_REVIEW | ✅ |
| 3 | Multiple scale IDs / station association; wrong scale → conflict (MANUAL_REVIEW) | ✅ |
| 4 | Duplicate completion + duplicate scale readings | ✅ deduped / REPEATED_READING |
| 5 | Delayed & out-of-order events | ✅ OUT_OF_ORDER rejected; delayed still validated on content |
| 6 | Disconnect / reconnect / offline replay (machine + scale) | ✅ replay in order; processor idempotent |
| 7 | Invalid / unstable / negative / zero / over-capacity / wrong-unit | ✅ all rejected; roll not finalised |
| 8 | Gross/tare/net incl. **no double-tare** | ✅ net=gross−tare; NET-basis not re-tared |
| 9 | Stop / green-light / restart in different orders | ✅ completion only from RUNNING; restart-before-recorded makes no roll |
| 10 | EXCEPTION / MANUAL_REVIEW recovery | ✅ invalid→EXCEPTION→authorised manual fallback→finalise (MANUAL) |
| 11 | Completion before shift boundary, weighed after | ✅ **see §4 — established rule, not blocked** |
| 12 | Duplicate/replayed events cannot duplicate rolls or overwrite accepted weight | ✅ one finalisation; captured weight immutable after capture |

**All 18 integration tests pass.**

## 4. Scenario 11 — shift-boundary allocation (established rule, NOT invented)
**Verified existing behaviour (not a new rule):** a roll's `shift` is fixed at **creation/completion** — `rolls.routes.js` *requires* `shift` on roll create, and on approval/weighing `production_records` is allocated to **`roll.shift`** (`backend/src/routes/rolls.routes.js:102`, `const shift = roll.shift || detectCurrentShift(...)`), **not** the weighing-time shift. `detectCurrentShift` is only a fallback when `roll.shift` is null.
**Therefore** a roll completed in shift A but weighed after the A→B boundary stays allocated to **shift A**; late weighing does not reassign it. The test asserts: the pending roll's `shift` remains `A`, the **completion timestamp and the weighing timestamp are both preserved** (distinct audit entries), and the finalised roll id carries the completion shift (`-A-`). The simulator mirrors the established rule and invents nothing.
**Status:** **not blocked.** (Note: production *reporting/allocation* remains the server's responsibility in `rolls.routes.js`; the simulator only preserves the completion-shift and both timestamps so the existing rule can be applied — it does not itself write `production_records`.)

## 5. Test commands & exact results
```
# new integration tests (DB-free, isolated)
cd backend && npx jest test/production-sim.integration.test.js   → 18 passed / 18
# full unit suite (regression + both new simulator suites)
cd backend && npx jest                                           → 26 suites, 310 passed / 310
# database E2E (isolated PG18.7 scratch cluster, localhost-only, provisioned
#   from backend/schema/00_baseline_schema.sql: 72 OK / 0 FAIL, 185 public + 22 acct
#   tables; e2e + staging DBs; app server on :4000)
cd backend && for t in tests/*.e2e.js; do node "$t"; done        → 48 passed / 48
```
**Exact counts (this session, 2026-11-28):**
- **Unit: 310 / 310 passed, 0 failed, 0 skipped** (26 suites) — 292 prior + **18 new** integration tests (the 30 simulator unit tests from report 30 are included in the 292).
- **E2E: 48 / 48 passed, 0 failed, 0 skipped** on the isolated PG18.7 environment **with both the `dhown_mes_staging` DB and the app server present**.
  - Transparency note: in report 30's container the e2e tally was **47/48** *only because* the `dhown_mes_staging` DB and the running server were absent (the shortfalls were `accounting` → needs the staging DB; `sales-role`/`reports-extra`/`medium-batch` → need the app server on :4000). With the required isolated environment fully provided this session, all 48 pass. No test was skipped, hidden, or reclassified to reach green.

## 6. Limitations
- All adapters are **mocks**; these tests prove the **workflow, contracts and invariants**, **not** real-device behaviour or hardware compatibility.
- The **DB-backed** persistence of pending rolls / scale readings and the engine's weight-correction UPDATE are **designed but not built** (report 29 §10 schema is still proposed and unapproved); integration tests therefore use the injected engine, not real tables.
- The simulator is **not wired into boot/routes**; wiring (flagged) remains a later, separately-approved phase.
- E2E results depend on the isolated environment being provisioned (PG18.7 + staging DB + server); without it, DB-backed suites cannot run and would be reported as skipped.

## 7. Management decision needed
- **None newly required for scenario 11** — the existing rule (completion-shift governs allocation) is established and was followed. If management wishes to change that policy (e.g. allocate by weighing time), that would be a **new business decision** and is **out of scope** here; flag it only if a policy change is desired.
- The proposed device/scale persistence tables (report 29 §10) still await approval before any migration — unchanged by this task.

---
## Safety confirmation
No real machine / manufacturer-cloud / physical-scale / vendor-credential connection; no real production record created, updated or deleted; no mixing of mock and real data; no schema or migration change; no production code modified (only one test file added); simulator not wired into `server.js`/routes/dashboards; all simulator flags OFF by default; no authentication or security check weakened; BUSY integration untouched. Existing roll-generation, machine, operator and downtime code and the roll-ID / one-open-roll invariants are intact. No hardware integration or further phase was started.
