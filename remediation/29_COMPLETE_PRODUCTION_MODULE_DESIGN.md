# 29 — Complete Machine-Connected Production, Automated Roll Generation & Digital Weighing Module

**Date:** 2026-11-27 · **Branch:** `claude/mes-busy-remediation` · **HEAD:** `ed6a1cd`
**Design & discovery only.** No application code, route, service, schema, migration, flag, deployment, machine, scale or BUSY connection was created or changed. Existing machine, roll, operator and downtime functionality is left intact. **No implementation is authorised** until this design is accepted and vendor documentation is received.

**Labels:** `[CONFIRMED]` factory-confirmed requirement · `[EXISTS]` verified in the current code this session (path/column cited) · `[PROPOSED]` new design, not built · `[ASSUMPTION]` reasoned, to be validated · `[VENDOR?]` depends on manufacturer/scale documentation not yet supplied. **No API endpoint, protocol or hardware capability is invented** — every vendor-specific detail is marked `[VENDOR?]`.

---

## 1. Executive summary
- `[EXISTS]` DHOWN MES **already ingests machine telemetry**: `POST /api/live-data` (`backend/src/routes/live-data.routes.js`, auth `dcApiKeyGuard`) writes `machine_live_data` and `machine_status_log`, and converts the machine **production counter → kg** using `machines.kg_per_counter`, with counter-reset/implausible-delta handling. The `mes-bridge` is the existing collector that feeds it.
- `[EXISTS]` It **already auto-generates rolls on doff**: `backend/src/lib/rolls.js` (`openRoll` / `closeOpenRoll`) closes the open roll at the current counter and fills an **estimated** weight from `kg_per_counter` **as a placeholder**, with the explicit design intent (code comment) that *"the operator overwrites it with the real scale weight on approval."* Approval happens in `backend/src/routes/rolls.routes.js`.
- `[EXISTS]` **No digital-scale integration exists.** Roll weight today is a single manual `rolls.actual_weight_kg` entered at supervisor approval. There is **no** scale registry, no gross/tare/net, no stable-reading capture, no scale readings table.
- **The target module fills exactly that gap** while reusing the existing counter/roll/telemetry spine: a replaceable **Machine Connectivity Adapter** and a vendor-independent **Digital Weighing Adapter**, a **Device Event Processor**, an explicit **machine/roll state machine**, a **Roll Completion Manager** that makes measured scale weight the primary quantity, and the existing **Roll Generation Engine** reused unchanged.
- **Mock-first and vendor-pending:** because neither the Chinese knitting-machine cloud nor the weighing-scale protocol is documented, Phases B–D build against **simulators** and canonical data contracts; the real vendor adapters (Phases E–F) are implemented **only after** their questionnaires (§14) are answered.
- **Independent of BUSY.** This module does not connect to, or depend on, the BUSY integration.

## 2. Existing MES architecture & exact source references `[EXISTS]`
### Machine management
| Concern | Where | Notes |
|---|---|---|
| Machine master/registry | table `public.machines` (`backend/schema/00_baseline_schema.sql`) | columns incl. `machine_id` (PK), `machine_name`, `machine_type`, `diameter`, `gauge`, `feeders`, `needles_count`, `fabric`, `fabric_code`, `dc_id`, `rpm_target`, `kg_per_counter`, `machine_status`, `dc_status`, **`manufacturer`, `model`, `serial_number`**, `installation_date` |
| Machine routes/screens | `backend/src/routes/machines.routes.js`, `machine-settings.routes.js`; frontend `frontend/src/components/MachineCard*.jsx`, `MachineGridV2.jsx` | machine config/status |
| Machine→product mapping | `machines.fabric`/`fabric_code` (+ roll-time fabric resolution) | drives roll ID |
| Live status | `machine_live_data` (one row/machine: `rpm`, `status`, `dc_status`, `production_counter`, `previous_counter`, `session_production_kg`, `last_status`); `computeLiveStatus(dcStatus,rpm)` in `backend/src/lib/machine.js` | |
| Downtime | `machine_status_log` (`status`,`start_time`,`end_time`,`duration_minutes`); `backend/src/routes/downtime.routes.js` | status-transition log |
| Maintenance/fault | `backend/src/routes/maintenance-records.routes.js`, `maintenance-schedule.routes.js`; `src/lib/pm-scheduler.js` | PM auto-scheduler |

### Production management
| Concern | Where |
|---|---|
| Production recording / entry | `backend/src/routes/production.routes.js`, `production-entry.routes.js` |
| Planning / orders | `production-plans.routes.js` (+ controller/service/repository), `sales-orders.routes.js`, `work-orders.routes.js` |
| Shift management | `backend/src/lib/shift.js` (`detectCurrentShift`, `getShiftSettings`) |
| Operator assignment / identity | `operators.*` (controller/service/repository), `operators` table (`rfid_tag`, `operator_code`, `skill_level`), `backend/src/routes/rfid.routes.js` |
| OEE | `updateOEE(...)` in `backend/src/lib/machine.js`; `src/lib/dashboard-kpi.js`; `analytics.routes.js` |
| Dashboards | `dashboard.routes.js`, `command-center.routes.js`; frontend `frontend/src/pages/*` |

### Device integration (existing)
| Concern | Where | Gap |
|---|---|---|
| Telemetry ingestion | `POST /api/live-data` (`live-data.routes.js`) | single endpoint; HTTP push |
| Device auth | `dcApiKeyGuard` (`backend/src/middleware/auth.js`) — `DC_API_KEY` via `x-api-key`/`?api_key=` | **fails OPEN** if `DC_API_KEY` unset (logs a warning) → harden for new ingestion |
| Event storage | `machine_live_data` (snapshot), `machine_status_log` (transitions) | **no raw-event log, no device registry, no idempotency key, no offline buffer** |
| Duplicate/out-of-order | partial: counter delta clamps resets/implausible jumps | not a general event-dedup mechanism |
| MQTT/WebSocket | none for devices; `socket.io` used only for **browser** live updates (`io.emit`) | device transport is HTTP push only |

## 3. Existing roll-generation analysis `[EXISTS]`
- **Table `public.rolls`:** `roll_id` varchar(50) **PK**, `machine_id`, `fabric_type`, `fabric_item_id`, `shift`, `operator_id`, `supervisor_id`/`supervisor_name`, `start_counter`/`current_counter` (bigint), **`weight_kg` / `roll_weight_kg` / `actual_weight_kg`** (three numeric weight columns), `status`, `warehouse_status` (default `GREIGE`), `qr_image`, `lot_id`, `issue_id`, `source`, timestamps (`created_at`,`verified_at`,`closed_at`,`approved_at`).
- **Roll ID format** (`src/lib/rolls.js` `resolveRollDefaults`, mirrored in `rolls.routes.js`): `"{prefix}-{machine_id}{fabricPart}{gaugePart}-{YYMMDD}-{shift}-{seq}"`, where `prefix` = `app_settings['roll_prefix']` (default `DHM-`), fabric/gauge from `machines`, `seq` = per-day sequence.
- **Lifecycle (verified):** `OPEN` → (close at counter) → (supervisor approve sets `actual_weight_kg`, `status=APPROVED`, `warehouse_status=GREIGE`, generates QR) → downstream; `CANCELLED` path exists; **one `OPEN` roll per machine enforced** (409 on second open).
- **Automated doff (verified):** `src/lib/rolls.js` `closeOpenRoll` fills an **ESTIMATED** weight from counter delta × `kg_per_counter` as a **placeholder**, preserving any existing weight; the comment states the operator overwrites it with the **real scale weight** on approval. → **This is the exact integration seam for the digital scale.**
- **Downstream consumers (do not redesign):** approval posts to costing/knitting rate and ledger (`addCostEntry`, `postToLedger`), sets `warehouse_status=GREIGE`, emits `inventory:greige_update`; rolls feed `batch_rolls`, greige/finishing, quality, warehouse and dispatch.
- **Legacy:** `backend/services/rollGenerationService.js` is **orphaned** (superseded by `src/lib/rolls.js`) per audit report 27 — reused rules now live in `src/lib/rolls.js`; **do not resurrect the legacy file.**

## 4. Confirmed factory workflow `[CONFIRMED]`
1. Machine knits hosiery. 2. On a completed physical roll the machine **stops**. 3. A **green completion light** activates. 4. Operator removes the roll. 5. Operator restarts the machine. 6. The roll is **weighed on an integrated digital scale**. 7. The **actual measured weight** is recorded in MES. 8. MES saves the unique roll record. 9. Dashboards and shift reports update.

**Distinctions carried into the design:** machine-stop and green-light are **observed** behaviours; their availability via the manufacturer cloud is **`[VENDOR?]`**. The digital scale is **required** but its protocol/manufacturer is **`[VENDOR?]`**. **Measured weight is the primary roll quantity;** counters are **secondary validation** only. **A stop alone must not create a roll; a restart alone must not create a roll.**

## 5. Target system architecture `[PROPOSED]`
Seven replaceable components, each behind an interface, reusing the existing roll/telemetry spine:
- **A. Machine Connectivity Adapter** — one of: manufacturer cloud API, webhook, or on-prem gateway `[VENDOR?]`. Interface `MachineConnector { subscribe(), fetchEvents(since), health() }`. Default = **MockMachineConnector**.
- **B. Device Event Processor** — normalises adapter output to the canonical **MachineEvent** contract (§9); does machine identification, timestamp & schema validation, **idempotent** dedup, out-of-order ordering, offline recovery, and status tracking (reusing `computeLiveStatus`).
- **C. Roll Completion Manager** — consumes validated completion/stop events + green-light (where available) + operator confirmation to drive the **state machine** (§8) and the **pending-roll** lifecycle; never creates a roll from a bare stop/restart.
- **D. Digital Weighing Adapter** — vendor-independent `WeighingConnector { readStable(), stream(), health() }` `[VENDOR?]`; scale registry, stable-reading detection where supported, unit conversion, gross/tare/net, validation, disconnection handling, authorised manual fallback. Default = **MockScaleConnector**.
- **E. Roll Generation Engine** — the **existing** `src/lib/rolls.js` + `rolls.routes.js`, reused; extended only to attach measured weight + device/scale references via the Completion Manager (design-time; not built here).
- **F. Production Reporting Engine** — existing OEE/shift/downtime/production reports (`machine.js`, `shift.js`, `analytics.routes.js`, `reports.routes.js`), extended with weighing/exception views.
- **G. Live Production Dashboard** — existing dashboards extended with pending-weighing, scale/device connectivity, and exception panels.

**Boundary:** A/D are the only vendor-coupled parts; everything else consumes canonical contracts, so swapping a mock for a real adapter changes no downstream code.

## 6. Machine integration design `[PROPOSED]` / `[VENDOR?]`
- **Transport:** to be chosen from what the manufacturer actually supports — cloud REST poll, push webhook, or a **local gateway** on the factory LAN. **Not assumed.** Until known, the adapter is the mock + a pull-style `fetchEvents(since)` contract that fits either poll or webhook.
- **Identification:** map vendor machine/device id → MES `machines.machine_id` via `machines.dc_id` (existing) or a new `device_registry` row (§10). Reject events whose device is unmapped → `MANUAL_REVIEW` (never auto-create a machine).
- **Events consumed (if the vendor emits them `[VENDOR?]`):** roll-completion, machine stop, restart, fault/downtime, production counter, green-light. Each must carry a vendor **event id** + **timestamp** for idempotency/ordering; where absent, MES derives state from counter/status transitions and marks those states **MES-derived** (not observed).
- **Security:** device auth **fail-closed** (unlike the current `dcApiKeyGuard` default), least-privilege key per gateway, TLS where supported, optional payload signature `[VENDOR?]`.

## 7. Digital weighing integration design `[PROPOSED]` / `[VENDOR?]`
### Scale registry (proposed table `weighing_scales`, §10)
`scale_id, manufacturer, model, serial_number, capacity, resolution, supported_units, comm_method [VENDOR?: serial/USB/Ethernet/API], workstation_id, calibration_status, calibration_due, active`.
### Weight-capture workflow (maps to the state machine)
1 roll completion pending → 2 operator removes roll → 3 operator identifies/confirms the **pending roll** (RFID via `rfid.routes.js` or UI) → 4 roll placed on the **registered** scale → 5 MES receives reading(s) via the adapter → 6 MES detects a **stable** reading **if the scale provides a stability flag `[VENDOR?]`** (else operator confirms) → 7 validate against limits → 8 operator confirms where required → 9 save weight to the pending roll → 10 finalise the roll record (reusing `rolls.js`/approval).
### Weight data (proposed `scale_readings`, §10)
`raw_reading, unit, stable_flag [VENDOR?], gross_weight, tare_weight, net_weight, scale_id, read_at, operator_id, pending_roll_id, validation_status`.
- **Net = Gross − Tare**, **but if the scale already reports net, do not subtract tare again** `[CONFIRMED rule]`. A `weight_basis` field records whether the device returned gross or net.
- **Primary quantity = measured net weight** → written to `rolls.actual_weight_kg` (existing), replacing the counter **estimate** placeholder.
### Weight validation (reject, never silently accept)
zero, negative, over-capacity, unstable, repeated/duplicate reading, disconnected scale, wrong unit, outside product-configured min/max, wrong scale for the station → `validation_status` set, event → `MANUAL_REVIEW`; operator sees the reason.
### Manual fallback (authorised only)
Permitted only for authorised roles; record `entered_by`, `reason`, approval where configured; **preserve original + corrected** values; flag the weight as **MANUAL** in every report. **Never present manual weight as automatic scale data** `[CONFIRMED rule]`. (`rolls.source`/a new `weight_source` field carries `SCALE`|`MANUAL`.)

## 8. Roll lifecycle & machine event state machine `[PROPOSED]`
States: `RUNNING → COMPLETION_PENDING → AWAITING_OPERATOR → AWAITING_WEIGHT → WEIGHT_CAPTURED → ROLL_RECORDED → RUNNING_AGAIN`, plus `EXCEPTION` and `MANUAL_REVIEW`.
### Allowed transitions
| From | Event | To |
|---|---|---|
| RUNNING | completion/stop+green (observed) | COMPLETION_PENDING |
| COMPLETION_PENDING | operator acknowledges removal | AWAITING_OPERATOR → AWAITING_WEIGHT |
| AWAITING_WEIGHT | valid stable reading (or confirmed) | WEIGHT_CAPTURED |
| WEIGHT_CAPTURED | roll saved (weight attached) | ROLL_RECORDED |
| ROLL_RECORDED | machine restart (observed) | RUNNING_AGAIN → RUNNING |
| any | validation failure / timeout / conflict | EXCEPTION or MANUAL_REVIEW |
### Invalid / guarded (must not happen silently)
- **Stop alone → no roll** (stays COMPLETION_PENDING until operator + weight). `[CONFIRMED]`
- **Restart alone → no new roll** (restart only closes the lifecycle of an already-recorded roll). `[CONFIRMED]`
- **Duplicate completion** (same vendor event id) → ignored idempotently (no second pending roll).
- **Operator timeout** (no acknowledgement within T) → EXCEPTION, supervisor alert; roll held.
- **Scale timeout / disconnect** → AWAITING_WEIGHT held → MANUAL_REVIEW or authorised manual entry.
- **Restart before weight confirmed** → pending roll preserved; next production continues on a **new** open roll only after the pending one is resolved (mirrors existing one-open-roll-per-machine).
- **Delayed / out-of-order events** → ordered by device timestamp + sequence; stale events dropped with audit.
- **Internet interruption / power failure / MES restart** → recovered from the persisted pending-roll + raw-event/sync-state tables (§10); nothing depends on in-memory state.
**Observed vs derived:** states driven by a real vendor event are tagged **observed**; states inferred from counters/status are tagged **MES-derived**; operator steps are tagged **operator-confirmed**. The design does **not** assume the cloud provides every state.

## 9. Data contracts `[PROPOSED]`
**MachineEvent** `{ event_id [VENDOR? else synthesised], device_id, machine_id, type: RUNNING|COMPLETION|STOP|RESTART|FAULT|COUNTER|GREEN_LIGHT, counter?, green_light?, observed_at, received_at, source, raw }`.
**ScaleReading** `{ reading_id, scale_id, workstation_id, raw_reading, unit, stable?, weight_basis: GROSS|NET, gross?, tare?, net?, read_at, operator_id, pending_roll_id, validation_status }`.
**PendingRoll** `{ pending_id, machine_id, device_event_id, opened_at, state, operator_id, shift, expected_product, scale_id?, weight?, weight_source, exception? }`.
All three are transport-agnostic; adapters translate vendor payloads into these. Idempotency key = `(source, device_id, event_id)` and `(scale_id, reading_id)`.

## 10. Proposed database impact `[PROPOSED]` — not executed
Reuse first: `rolls`, `machines`, `machine_live_data`, `machine_status_log`, `operators` are **kept as-is**; measured weight continues to land in `rolls.actual_weight_kg`. New tables **proposed only** (no migration here):
| Table | Purpose | Keys / constraints |
|---|---|---|
| `device_registry` | vendor device ↔ `machines.machine_id` | PK `device_id`; FK `machine_id`; `UNIQUE(vendor, serial_number)`; `active` |
| `device_connection_config` | per-device transport/credentials ref (no secrets inline) | PK `device_id`; secret via env/secret store |
| `device_raw_events` | append-only raw machine events | PK `id`; `UNIQUE(source, device_id, event_id)` idempotency; index `(machine_id, observed_at)`; retention policy |
| `device_counter_readings` | counter snapshots for reconciliation | PK `id`; `(machine_id, read_at)` index; handles reset/rollover |
| `device_sync_state` | last-seen cursor/offset per device | PK `device_id`; `last_event_id`, `last_sync_at` |
| `weighing_scales` | scale registry (§7) | PK `scale_id`; `UNIQUE(serial_number)`; `workstation_id` |
| `scale_readings` | every reading incl. invalid | PK `reading_id`; `UNIQUE(scale_id, vendor_reading_id)`; FK `pending_roll_id`; index `(read_at)` |
| `pending_roll_completion` | PendingRoll lifecycle | PK `pending_id`; `UNIQUE(machine_id) WHERE state<>closed` (one pending/machine); FK `machine_id`, `device_event_id` |
| `roll_generation_audit` | full completion audit | PK `id`; FK `roll_id`; immutable append |
| `production_event_linkage` | ties roll ↔ device event ↔ reading | FKs; `UNIQUE(roll_id)` |
Cross-cutting: timestamps `TIMESTAMPTZ` (observed vs received distinguished), append-only audit, retention per table, FK indexes, idempotency uniques, clear data ownership (MES owns all of these; devices are sources).

## 11. Operator & supervisor interfaces `[PROPOSED]`
**Operator screen:** assigned machine, live status, **pending roll completion**, roll-removal confirmation, live scale reading + stability, weight confirmation, generated roll number, production order/product, current shift. Operator identity via existing **RFID** (`rfid.routes.js`)/login. 
**Supervisor screen:** all machines; completed + pending rolls; **unweighed** rolls; scale failures; **manual** weight entries; abnormal readings; missing device events; production exceptions; **approval queue**. 
**Permissions:** reuse existing auth/roles (`verifyToken`, `requireRole`); **weight edit / manual entry restricted** — not every operator may edit recorded weights. `[CONFIRMED rule]`

## 12. Dashboard design `[PROPOSED]`
Extend existing dashboards (`dashboard.routes.js`, `command-center.routes.js`, frontend pages) to show: machine running/stopped/fault, current order/operator/shift, roll-completion events, rolls awaiting weighing, completed roll count, **actual production weight**, machine/shift/product output, downtime, OEE, **device connectivity**, **scale connectivity**, pending exceptions. Visual rule: label each value **live** / **historical** / **calculated** / **unverified** (e.g. counter-estimated weight shown as unverified until the scale value lands).

## 13. Security & reliability `[PROPOSED]`
- **Device auth fail-closed** (contrast current `dcApiKeyGuard` default-open) — per-device least-privilege keys; credentials in env/secret store only; TLS and payload signature where the vendor supports them `[VENDOR?]`.
- **Never expose PostgreSQL to the internet** for device connectivity (devices talk to the MES API/gateway, never the DB) `[CONFIRMED rule]`; keep 5432 on `127.0.0.1` (project rule).
- **Never trust device payloads** — schema/timestamp/range validation before persistence; idempotency uniques; offline buffering + bounded retry/backoff; out-of-order ordering; append-only audit; backup/recovery via existing backup feature; **restricted manual corrections** with full before/after retention.

## 14. Supplier questionnaires
### A. Chinese knitting-machine manufacturer `[VENDOR?]`
Manufacturer & model · firmware version · cloud platform · API documentation · authentication · **green-light signal availability** · roll-completion events · machine stop/restart events · fault/downtime events · production counters (meaning, units, reset/rollover behaviour) · event IDs · timestamps (zone/format) · historical event retrieval · offline recovery · rate limits · **test account + test machine**.
### B. Digital weighing-scale supplier `[VENDOR?]`
Manufacturer & model · capacity & resolution · accuracy spec · calibration requirements · supported units · communication interface (serial/USB/Ethernet/API) · protocol documentation · **sample output** · **stable-reading indicator** · gross/net/tare support (does it report net?) · multi-scale support · driver/software requirements · SDK/API · **test hardware**.
**Decisions that stay pending until these arrive** are listed in §18.

## 15. Testing & acceptance criteria `[PROPOSED]`
- **Contract/unit:** state-machine transitions (all allowed + every guarded-invalid case), net/tare math (incl. "scale already reports net"), validation rejections, idempotency, out-of-order ordering, counter reset/rollover.
- **Simulator e2e:** MockMachineConnector + MockScaleConnector drive a full RUNNING→…→ROLL_RECORDED cycle; failure injections: duplicate completion, operator timeout, scale disconnect, delayed event, MES restart recovery, manual fallback with approval.
- **Regression:** existing baselines unchanged — unit **24**/e2e **48** (`[REPORTED]` 262/14/48) stay green with no weakened assertions; roll ID format, one-open-roll-per-machine, and approval→costing/ledger/greige behaviour preserved.
- **Acceptance per phase** defined in §16; pilot acceptance = measured weights match a reference scale within the scale's resolution and every roll is traceable to a device event + reading.

## 16. Phased implementation roadmap `[PROPOSED]`
| Phase | Scope | Acceptance |
|---|---|---|
| **A** Discovery & workflow validation | this document + factory sign-off of §4/§8 | factory confirms the state machine & distinctions |
| **B** Canonical data contracts | §9 contracts + proposed schema (design) | contracts reviewed; no code/DB change |
| **C** Mock simulators | MockMachineConnector + MockScaleConnector | simulators replay full + failure scenarios |
| **D** Device-independent event processing | Processor + Completion Manager + state machine (behind flags OFF) | all §15 contract/simulator tests green |
| **E** Machine vendor adapter | **after** questionnaire A | adapter maps real events to contract; parity with mock |
| **F** Digital scale adapter | **after** questionnaire B | real readings validated; net/tare correct |
| **G** Roll completion & weight capture | wire measured weight into `rolls.js`/approval | measured weight becomes primary; estimate shown as unverified |
| **H** Live dashboard integration | pending-weighing, connectivity, exceptions | dashboards show live/historical/calculated/unverified |
| **I** Single-machine + single-scale pilot (SJ03) | one machine, one scale, supervised | weights within resolution; full traceability; rollback = flag OFF |
| **J** Factory acceptance & controlled expansion | staged rollout | per-machine sign-off; exceptions handled |

## 17. Risks & unresolved questions
- `[VENDOR?]` The machine cloud may **not** expose completion/green-light/stop events at all — then completion is **MES-derived** from counter/status, lowering fidelity (risk: false/missed doffs).
- `[VENDOR?]` The scale may be a **dumb serial indicator** with no stability flag and no net/tare — then stability/net are MES/operator responsibilities.
- `[ASSUMPTION]` One scale per weighing station near each machine; multi-machine-per-scale mapping is configurable but unproven.
- `[EXISTS→risk]` `dcApiKeyGuard` **fails open** today; new device ingestion must fail closed or telemetry is spoofable.
- Counter semantics (per-roll vs cumulative, units) are only partially known — **never** use counter deltas as actual weight `[CONFIRMED rule]`.
- Clock skew between machine cloud, scale and MES affects ordering → rely on received-at + sequence as well as observed-at.

## 18. Explicit vendor-dependent decisions (pending documentation)
1. Machine transport (cloud API vs webhook vs local gateway). 2. Whether completion/green-light/stop/restart/fault are real events or must be derived. 3. Counter meaning, reset/rollover, units. 4. Event id/timestamp availability (idempotency/ordering design). 5. Historical retrieval & offline recovery support. 6. Scale comm interface + protocol. 7. Stable-reading indicator availability. 8. Whether the scale reports gross or net (tare handling). 9. Multi-scale support & driver/SDK needs. 10. Auth/encryption/signature capabilities on both devices. **Until these are answered, Phases E–F are not started and the mock adapters remain the only connectors.**

---
## Safety restrictions observed by this task
Design & discovery only. No application code/route/service deleted or modified; no roll-generation functionality retired; no database/migration/schema change; no feature flag activated; no connection to any production machine, weighing scale, manufacturer cloud, BUSY, or production system; no deployment; no factory-workflow change. Existing machine, roll, operator, downtime and accounting history preserved. All discovery was read-only. **No implementation is authorised until this design is accepted and vendor documentation is received.**
