# 30 — Mock Machine + Digital Weighing Scale Simulator — Implementation Report

**Date:** 2026-11-27 · **Branch:** `claude/mes-busy-remediation` · **Base commit:** `6bae04b`
**Mock-first implementation.** No real machine, manufacturer cloud, physical scale, vendor credential, production record, deployment or BUSY connection. All new capability is **feature-flagged OFF by default** and **not wired into `server.js`**. No existing file, route, service, schema or migration was modified.

**Labels:** `[EXISTS]` verified existing code · `[NEW]` added this task · `[PROPOSED]` design pending approval (not built) · `[VENDOR?]` depends on vendor docs not yet supplied.

---

## 1. Files added and modified
**Added (10 files, all `[NEW]`):**
| File | Role |
|---|---|
| `backend/src/lib/production-sim/flags.js` | feature flags, **OFF by default** (`PRODSIM*`) + test override |
| `backend/src/lib/production-sim/state-machine.js` | pure roll-completion state machine + guards |
| `backend/src/lib/production-sim/events.js` | canonical `MachineEvent` / `ScaleReading` contracts + validation |
| `backend/src/lib/production-sim/adapters/mock-machine.js` | mock machine simulator (clearly labelled) |
| `backend/src/lib/production-sim/adapters/mock-scale.js` | mock digital-scale simulator (clearly labelled) |
| `backend/src/lib/production-sim/event-processor.js` | idempotency, ordering, offline replay |
| `backend/src/lib/production-sim/weight-validation.js` | gross/tare/net + validation rules |
| `backend/src/lib/production-sim/completion-manager.js` | pending-roll lifecycle + auditable weight correction |
| `backend/src/lib/production-sim/index.js` | flag-gated builder; inert when OFF; **not required by boot** |
| `backend/test/production-sim.test.js` | 30 DB-free tests |

**Modified: NONE.** `git diff --name-only HEAD` = empty — `server.js`, `src/lib/rolls.js`, `rolls.routes.js`, `live-data.routes.js`, the schema and all migrations are **unchanged**.

## 2. Architecture implemented `[NEW]`
A self-contained `production-sim` module mirroring the approved report-29 design, built as **pure, dependency-injected** units so it needs no database and has no side effects on import:
- **Replaceable adapters** (`MachineConnector`, `WeighingConnector`) with **mock** implementations only — there is **no real-equipment code path** in this module.
- **Device Event Processor** → **State Machine** → **Roll Completion Manager**, with **Weight Validation** feeding the manager.
- The manager reaches the **existing** roll engine through an **injected** `rollEngine.applyMeasuredWeight(...)` — so the real `src/lib/rolls.js` is the single finalisation point in a wired deployment, while tests use a spy. **No duplicate roll engine was built.**

## 3. Existing code reused (verified) `[EXISTS]`
- `src/lib/rolls.js` — `openRoll` / `closeOpenRoll`; the auto-doff already writes an **ESTIMATED** weight via `actual_weight_kg = COALESCE(actual_weight_kg, est)` (so a later counter update never overwrites a set weight). The manager treats that estimate as the placeholder and applies the measured weight as an auditable correction — exactly the seam the code comments describe.
- `rolls` table columns (`roll_id`, `machine_id`, `start_counter`/`current_counter`, `actual_weight_kg`, `status`, `warehouse_status`, `operator_id`, `shift`, `source`) — reused as-is; **roll ID format and one-open-roll-per-machine rule preserved** (unchanged, since `rolls.js`/`rolls.routes.js` are untouched).
- `operators.rfid_tag` / `rfid.routes.js` — operator attribution reused conceptually (operator id flows through the manager).
- `machine_live_data` / `machine_status_log` / `kg_per_counter` ingestion (`live-data.routes.js`) — the existing telemetry path is unchanged; the simulator produces the same canonical shape.

## 4. State machine `[NEW]`
`RUNNING → COMPLETION_PENDING → AWAITING_OPERATOR → AWAITING_WEIGHT → WEIGHT_CAPTURED → ROLL_RECORDED → RUNNING_AGAIN`, plus `EXCEPTION` and `MANUAL_REVIEW`. Enforced invariants (all tested):
- **Stop alone never opens a pending roll** — only a `completion` (stop + green) does.
- **Green-light alone does not finalise** — finalisation needs a validated weight + operator confirmation.
- **Operator confirmation is required** before weighing (`AWAITING_OPERATOR → AWAITING_WEIGHT`).
- **Duplicate completion** (same `device_event_id`) never creates a second pending roll.
- **Restart before `ROLL_RECORDED` never creates/finalises a roll** — pending is preserved.
- **Invalid/incomplete weighing never finalises** → `EXCEPTION`/`MANUAL_REVIEW`.
- **Invalid transitions throw** (`InvalidTransition`).

## 5. Machine simulator capabilities `[NEW]` / `[VENDOR?]`
Running, counter advance, **counter reset**, green-light, stop, **completion (doff)**, fault, restart, duplicate event, **delayed / out-of-order** event, communication failure (disconnect), **reconnect + replay of buffered events**. Every event carries: `event_id`, `device_id`, `machine_id`, `type`, `observed_at`, `received_at`, `source`, `validation_status`. **`[VENDOR?]` The real manufacturer cloud is not assumed to emit any of these — this is a test generator only.**

## 6. Scale simulator capabilities `[NEW]` / `[VENDOR?]`
Gross, **net-reporting** scale, tare, units, stable, unstable, zero, negative, over-capacity, wrong-unit, duplicate, delayed, disconnect/reconnect, invalid data. Supports **multiple scale IDs / weighing stations**. **`[VENDOR?]` No real serial/USB/Ethernet/API protocol is implied.**

## 7. Roll integration details `[NEW]`
- The manager records the **estimate placeholder** in its audit, then on a valid stable reading attaches the **measured net** and, at `finalise`, calls the injected roll engine `applyMeasuredWeight(roll_id, net, { source, scale_id, operator_id, estimate_weight_kg, device_event_id })`.
- **Measured weight is primary;** counter is never used as the roll weight. The **estimate is preserved** (passed to the engine for audit history; also kept in the manager's audit trail).
- **Manual fallback** sets `weight_source = 'MANUAL'`, requires `authorised: true`, records `by`/`reason`, and is always distinguishable from `SCALE` — **manual weight is never presented as automatic capture**.
- `[PROPOSED]` In a wired deployment the engine's correction would also persist `weight_source` + the estimate in a `roll_weight_audit` row and (optionally) a `rolls.weight_source` column — **both remain proposed in report 29 §10, not applied here.**

## 8. Database changes
**NONE.** The module creates **no tables**, runs **no migration**, and touches **no database** on import or with flags OFF. All simulator state is in-memory. The device/scale/pending tables remain **`[PROPOSED]`** in report 29 §10 and **await approval before any migration** — this task did not create or apply one.

## 9. Feature-flag behaviour `[NEW]`
Flags (all **OFF by default**), via env or a test override: `PRODSIM_MOCK_MACHINE`, `PRODSIM_MOCK_SCALE`, `PRODSIM_EVENT_PROCESSOR`, `PRODSIM_ROLL_COMPLETION` (or `PRODSIM=all`). With flags OFF, `build()` returns an inert facade that constructs nothing. The module is **not imported by `server.js`** (verified: `git grep production-sim` across `server.js`/`src`/`tests` = none outside the module), so even enabling a flag only activates the **in-memory simulator** — there is no real machine/scale/cloud/BUSY path to activate. The completion manager **refuses to write a real roll** unless a real `rollEngine` is explicitly injected (`defaultGuardEngine` throws), so a mock event can never create a real production record.

## 10. Test commands and exact results
```
# new simulator tests (DB-free)
cd backend && npx jest test/production-sim.test.js      → 30 passed / 30
# full unit suite (regression + new)
cd backend && npx jest                                  → 25 suites, 292 passed / 292
# e2e regression (scratch PG18.7, provisioned from baseline: 72 OK/0 FAIL, 185 tables)
cd backend && for t in tests/*.e2e.js; do node "$t"; done → 47 passed / 48
```
**Exact results (this session):**
- **Unit: 292 / 292 passed** (25 suites) — 262 prior + **30 new**; zero regressions.
- **E2E: 47 / 48 passed** on a fresh, localhost-only PG18.7 scratch cluster provisioned from `backend/schema/00_baseline_schema.sql` (72 OK / 0 FAIL, 185 public + 22 acct tables).
  - The 1 non-pass is `medium-batch.e2e.js`'s timestamp-coverage gate (one provisioned table lacks a timestamp) — a **pre-existing by-design exemption** of the baseline schema, **not** related to this change (the module adds no tables). `accounting`, `sales-role`, `reports-extra` initially failed only for **environmental** reasons (a missing `dhown_mes_staging` DB; the app server not running) and **all three PASS** once the staging DB exists and `server.js` is up.
- **Isolation proof:** `production-sim` is referenced by nothing in `server.js`, `src/` (outside the module), or any e2e test — it **cannot** affect e2e outcomes.
- **No production-hardware compatibility is claimed from these mock tests.**

## 11. Known limitations
- All adapters are **mocks**; they prove the workflow and contracts, **not** real-device behaviour.
- The DB-backed path (persisting pending rolls / scale readings, and the engine's weight-correction UPDATE) is **designed but not built** — it needs the proposed schema (report 29 §10) approved first.
- The module is **not wired into boot or any route** — wiring (flagged) is a later phase.
- Stable-reading, net-vs-gross and green-light semantics are modelled on `[VENDOR?]` assumptions.

## 12. Vendor documentation still required `[VENDOR?]`
Machine: transport (cloud/webhook/gateway), whether completion/green-light/stop/restart/fault are real events, counter semantics/reset/units, event-id/timestamp availability, historical retrieval, offline recovery, auth/encryption. Scale: comm interface + protocol, stability flag, gross/net/tare behaviour, units, capacity/resolution, multi-scale, SDK/driver. (Full questionnaires in report 29 §14.) **Phases E–F (real adapters) remain unauthorised until these arrive.**

## 13. Rollback procedure
This change is **purely additive and inert**. To remove it: delete `backend/src/lib/production-sim/` and `backend/test/production-sim.test.js` (or `git revert` the commit). Because nothing imports the module and all flags are OFF, removal has **no effect** on the running application, the database, or any existing test. No data migration or config change is involved.

## 14. Outstanding risks
- `[VENDOR?]` If the real machine cloud exposes no completion/green-light events, completion must be **MES-derived** from counter/status — lower fidelity than the mock assumes.
- `[EXISTS→risk]` The existing device ingest `dcApiKeyGuard` **fails open** when `DC_API_KEY` is unset; any future real device ingestion must fail **closed** (tracked in report 29 §17).
- The DB-backed persistence + the proposed `rolls.weight_source`/`roll_weight_audit` need review before implementation (schema change).
- Mock green results must **not** be read as real-equipment readiness.

---
## Safety confirmation
No real machine/manufacturer-cloud/physical-scale/vendor-credential connection; no real production record created from mock events; no mixing of mock and real production data; no production-config change; no deployment; no BUSY connection; no real integration flag activated; no legacy roll-generation, machine, operator or downtime route deleted; existing factory workflows and accounting/production history preserved. All mock flags remain **OFF by default**. Real machine and scale adapters remain unauthorised pending vendor documentation and separate approval.
