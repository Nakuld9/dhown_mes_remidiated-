# 34 — Production Integration Readiness & Acceptance Test Specification

**Date:** 2026-11-28 · **Branch:** `claude/mes-busy-remediation` · **HEAD:** `2055c94` (verified; note: the prior "8cf3369" checkpoint is now behind the approved doc-33 commit).
**Read-only specification.** No code / schema / migration / firmware change; no vendor-cloud or production connection; ESP32, mes-bridge and `live-data` routes untouched; roll-generation, shift and BUSY behaviour unchanged. **No vendor endpoint/field/auth invented.**

**Labels:** `CONFIRMED` verified in current code (path cited) · `PROPOSED` test design, not yet runnable against a real vendor · `PENDING VENDOR` needs the manufacturer's API docs · `PENDING MGMT` a management decision (e.g. a tolerance).

---

## Phase 1 — Current architecture verification (capabilities vs gaps)
| Capability | Status | Source of truth |
|---|---|---|
| Replaceable machine connector (`subscribe`/`fetchEvents(since)`/`health`/`capabilities`) — supports poll **and** webhook | `CONFIRMED` | `backend/src/lib/production-sim/adapters/mock-machine.js:41-45` |
| Canonical `MachineEvent` envelope + validation | `CONFIRMED` | `backend/src/lib/production-sim/events.js` (types RUNNING/COMPLETION/STOP/RESTART/FAULT/COUNTER/GREEN_LIGHT) |
| Device event processor: idempotency, ordering, offline replay | `CONFIRMED` | `backend/src/lib/production-sim/event-processor.js` |
| Roll-completion state machine + guards | `CONFIRMED` | `backend/src/lib/production-sim/state-machine.js`, `completion-manager.js:44-160` (`onCompletion/onOperatorConfirmRemoval/onWeight/onManualWeight/finalise/onRestart`) |
| Existing roll engine reused (auto-doff, estimate placeholder) | `CONFIRMED` | `backend/src/lib/rolls.js`; create/approve `backend/src/routes/rolls.routes.js` |
| Scale weighing + validation (net=gross−tare, no double-tare, capacity/unit/limits/wrong-scale/stability) | `CONFIRMED` | `backend/src/lib/production-sim/weight-validation.js` (reasons: ZERO/NEGATIVE/OVER_CAPACITY/UNSTABLE/WRONG_UNIT/WRONG_SCALE/REPEATED_READING/INVALID_DATA/ABOVE_PRODUCT_MAX/BELOW_PRODUCT_MIN) |
| Operator attribution (RFID/login) | `CONFIRMED` | `backend/src/routes/rfid.routes.js`; operator carried through `completion-manager` |
| Shift allocation fixed at completion (late weighing never reassigns) | `CONFIRMED` | `backend/src/routes/rolls.routes.js:102` (`roll.shift || detectCurrentShift`); `backend/src/lib/shift.js` |
| Counter→kg + live status + OEE | `CONFIRMED` | `backend/src/routes/live-data.routes.js` (counter×`kg_per_counter`); `backend/src/lib/machine.js` (`computeLiveStatus`, `updateOEE`) |
| Audit / exception states (EXCEPTION, MANUAL_REVIEW) | `CONFIRMED` | `state-machine.js`; `completion-manager` audit entries; `busy_audit_log`/`audit_logs` |
| Ingest sink + fail-closed guard (push path) | `CONFIRMED` (deploy PENDING) | `backend/src/routes/live-data.routes.js`, `backend/src/middleware/auth.js` `dcApiKeyGuard` |
| **VendorCloudMachineAdapter** (real cloud source) | `PENDING VENDOR` | design only in `remediation/33_VENDOR_CLOUD_INTEGRATION_ASSESSMENT.md` |
| DB-backed persistence of pending rolls / scale readings / device events | `PROPOSED` | tables proposed in `remediation/29_…§10`, not built |

**Gaps (not to be duplicated — only the vendor adapter + its persistence are missing):** the entire workflow engine, state machine, weighing, validation, operator/shift/audit and the connector interface already exist and are tested (unit 318/318, integration 18/18, e2e 48/48 per reports 30/31). The only real gaps are (a) the `VendorCloudMachineAdapter` (blocked on vendor docs) and (b) the DB persistence layer (proposed, pending approval).

---

## Phase 2 — Production acceptance test cases
Each case: **Pre** (preconditions) · **In** (input/event) · **MES** (expected behaviour) · **DB** (expected impact) · **Audit** · **Pass/Fail**. Cases marked `PENDING VENDOR` can only execute once a real adapter + sandbox exist; the underlying MES behaviour each asserts is already `CONFIRMED` by the cited simulator tests.

### T1 — Machine identification & machine→MES mapping `PROPOSED`/`PENDING VENDOR`
- **Pre:** vendor device id mapped to `machines.machine_id` (via `machines.dc_id`/proposed `device_registry`). **In:** event for a mapped device; and a second for an **unmapped** device. **MES:** mapped → processed; unmapped → rejected to MANUAL_REVIEW, **no auto-create**. **DB:** no new `machines` row. **Audit:** rejection recorded. **Pass:** mapped accepted, unmapped quarantined; **Fail:** any machine auto-created.

### T2 — Running/stopped status `PROPOSED`
- **Pre:** machine mapped. **In:** RUNNING then STOP events. **MES:** `computeLiveStatus` reflects status; transition logged. **DB:** `machine_live_data` upsert, `machine_status_log` transition row. **Audit:** status-change log. **Pass:** status matches input; **Fail:** stale/incorrect status.

### T3 — Green-light & roll-completion events `PROPOSED`/`PENDING VENDOR`
- **Pre:** machine RUNNING. **In:** COMPLETION (stop+green). **MES:** `onCompletion` → COMPLETION_PENDING→AWAITING_OPERATOR; **stop-alone / green-alone does NOT create a roll**. **DB:** pending-roll (proposed table); no finalised roll yet. **Audit:** ESTIMATE_PLACEHOLDER entry. **Pass:** exactly one pending per completion; **Fail:** roll finalised without weight. *(If the cloud does not emit completion/green-light → `PENDING VENDOR`; completion becomes counter-derived, lower fidelity.)*

### T4 — Counter increments & resets `PROPOSED`
- **Pre:** known `kg_per_counter`. **In:** increasing counter, then a reset (new<old). **MES:** production delta computed; reset counts only the new value; implausible delta clamped (existing logic). **DB:** `machine_live_data.production_counter`/`session_production_kg`. **Audit:** counter readings (proposed `device_counter_readings`). **Pass:** no negative/huge spurious production on reset.

### T5 — Duplicate events & replay `CONFIRMED` (engine) / `PENDING VENDOR` (source)
- **Pre:** an event already processed. **In:** same `(source,device_id,event_id)` again. **MES:** ignored idempotently; a duplicate COMPLETION never opens a second pending roll. **DB:** no duplicate rows/rolls. **Audit:** DUPLICATE outcome. **Pass:** one roll, one finalisation (ref: `event-processor.js`, `completion-manager` dedup; tests report 31 §4/§12).

### T6 — Delayed & out-of-order events `CONFIRMED` (engine)
- **Pre:** last observed_at recorded per machine. **In:** an event older than the last. **MES:** flagged OUT_OF_ORDER, not applied. **DB:** none. **Audit:** rejection with reason. **Pass:** stale event never rewrites newer state.

### T7 — Network outage & historical recovery `PROPOSED`/`PENDING VENDOR`
- **Pre:** adapter cursor stored (`device_sync_state`, proposed). **In:** outage, then recovery; vendor replays events since cursor. **MES:** `fetchEvents(since)` replays in observed_at order; processor dedups. **DB:** no gaps/dupes. **Audit:** replay batch logged. **Pass:** state identical to no-outage; **PENDING VENDOR:** retention window/history API.

### T8 — Multiple machines concurrently `CONFIRMED`
- **Pre:** several mapped machines. **In:** interleaved events. **MES:** independent per-machine state. **DB:** per-machine rows isolated. **Audit:** per-machine history. **Pass:** no cross-contamination (ref: report 31 §1).

### T9 — Operator attribution & wrong-operator `CONFIRMED`
- **Pre:** assigned operator per pending roll. **In:** correct vs wrong operator confirms removal. **MES:** correct → AWAITING_WEIGHT; wrong → MANUAL_REVIEW. **DB:** operator recorded on roll. **Audit:** WRONG_OPERATOR exception. **Pass:** mismatch never silently accepted (ref: report 31 §2).

### T10 — Scale association & measured-weight validation `CONFIRMED`
- **Pre:** scale↔station/machine mapping; capacity/unit configured. **In:** readings — valid stable; and invalid (zero/negative/over-capacity/unstable/wrong-unit/wrong-scale). **MES:** valid → net=gross−tare (no double-tare), WEIGHT_CAPTURED; invalid → EXCEPTION/MANUAL_REVIEW, not finalised. **DB:** measured weight → `rolls.actual_weight_kg` at finalise; reading rows (proposed `scale_readings`). **Audit:** SCALE_READING + reasons. **Pass:** only valid stable weight finalises (ref: report 31 §7/§8).

### T11 — Completion before shift boundary, weighed after `CONFIRMED`
- **Pre:** completion in shift A near boundary. **In:** weigh after boundary (shift B clock). **MES:** roll stays allocated to **shift A**; both completion and weighing timestamps retained. **DB:** `rolls.shift='A'`; `production_records` to A (`rolls.routes.js:102`). **Audit:** both timestamps. **Pass:** late weighing never reassigns shift (ref: report 31 §11). *(Any change to this = `PENDING MGMT`.)*

### T12 — Machine replacement / reassignment `PROPOSED`/`PENDING VENDOR`
- **Pre:** a device remapped to a different/replacement `machine_id`. **In:** events before and after remap. **MES:** events route by current mapping; no orphan/duplicate rolls. **DB:** mapping change audited (proposed `device_registry`). **Audit:** remap record. **Pass/Fail:** no misattributed production; **PENDING VENDOR:** stability of vendor device id across replacement.

### T13 — Vendor-cloud auth expiry & API errors `PENDING VENDOR`
- **Pre:** adapter configured with a vendor credential. **In:** expired token / 401 / 5xx. **MES:** adapter refreshes/retries per vendor lifecycle; no partial/garbage ingest; connection marked stale. **DB:** none on failure. **Audit:** auth/connection error logged (no secret). **Pass:** failures are visible and non-corrupting. *(Auth lifecycle = `PENDING VENDOR`.)*

### T14 — Rate limiting & retry `PENDING VENDOR`
- **Pre:** vendor rate limits known. **In:** 429 / throttling. **MES:** backoff within limits; bounded retries; permanent → MANUAL_REVIEW. **DB:** none until success. **Audit:** retry/backoff logged. **Pass:** no limit breach, no lost events. *(Limits = `PENDING VENDOR`.)*

### T15 — Missing events & reconciliation `PROPOSED`/`PENDING MGMT`
- **Pre:** reconciliation job (design in report 36). **In:** a gap (expected completion absent). **MES:** reconciliation flags the discrepancy; no fabricated roll. **DB:** reconciliation record (proposed). **Audit:** MISSING flagged. **Pass:** gaps surfaced, never invented. *(Tolerance = `PENDING MGMT`.)*

### T16 — Duplicate-source prevention (cloud + local collector) `PROPOSED`
- **Pre:** a machine has both a cloud feed and an ESP32/mes-bridge feed. **In:** both deliver the same production. **MES:** one **authoritative source per machine** (mapping); the non-authoritative source is ignored/deduped. **DB:** no double counting. **Audit:** source recorded on each event. **Pass:** production counted once (design in report 36).

### T17 — Audit trail & manual exception recovery `CONFIRMED`
- **Pre:** a roll in EXCEPTION/MANUAL_REVIEW. **In:** authorised manual weight (`onManualWeight`, `authorised:true`). **MES:** recovers to weight-captured → finalise; weight marked **MANUAL** (never shown as auto); unauthorised rejected. **DB:** `rolls.actual_weight_kg` with manual source. **Audit:** MANUAL_WEIGHT entry with by/reason. **Pass:** only authorised manual entry finalises, always labelled MANUAL (ref: report 31 §10).

---
## Scope & safety
Read-only specification. No code/schema/migration/firmware change; no ESP32/mes-bridge/live-data removal; no vendor or production connection; no BUSY change; no vendor API detail invented. The `CONFIRMED` behaviours are already covered by the existing simulator tests; `PENDING VENDOR` cases become executable only when the manufacturer's API docs and a sandbox (report 35) are supplied.
