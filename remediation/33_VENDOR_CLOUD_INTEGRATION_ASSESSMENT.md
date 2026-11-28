# 33 — Vendor-Cloud Machine Integration — Architecture Impact Assessment

**Date:** 2026-11-28 · **Branch:** `claude/mes-busy-remediation` · **HEAD:** `8cf3369` (verified clean, in sync).
**Read-only assessment.** No code / schema / migration / firmware changed; no ESP32, mes-bridge or `live-data` route removed; no vendor-cloud connection; nothing deployed. **Not committed.**

**Intended change:** DHOWN MES fetches machine data from the **Chinese manufacturer's cloud platform**, rather than relying on ESP32/local-firmware collectors.

**Labels:** `[EXISTS]` verified in current code · `[CONFIRMED]` factory/architecture intent · `[PROPOSED]` design, not built · `[VENDOR?]` depends on vendor API docs not yet supplied. **No vendor endpoint, auth method or field is invented** — every such item is `[VENDOR?]`.

---

## 1. Current integration surfaces (verified)
- `[EXISTS]` **Ingest sink:** `POST /api/live-data` on `DC_PORT` (default 8090), guarded by `dcApiKeyGuard` (now **fail-closed**, commit `8cf3369`). Payload: `{machine_id, rpm, dc_status, production_counter, operator_id, operator_name, shift, working_hours, total_minutes, work_time, stoppage_reason, rolls}` (`live-data.routes.js:39/44`). It converts `production_counter → kg` via `machines.kg_per_counter`, upserts `machine_live_data`, logs `machine_status_log`, and records downtime. **Source-agnostic** — it does not care who posts.
- `[EXISTS]` **Collectors that post there:** ESP32 Ethernet + ESP32 WiFi firmware (`x-api-key` header) and the external **mes-bridge** poller (reads the vendor's on-prem DB `CM_Data_Acquisition` and pushes every ~10s).
- `[EXISTS]` **Canonical event envelope** (`production-sim/events.js`): `{ event_id, device_id, machine_id, type∈[RUNNING,COMPLETION,STOP,RESTART,FAULT,COUNTER,GREEN_LIGHT], counter, green_light, observed_at, received_at, source, payload, validation_status }`.
- `[EXISTS]` **Replaceable connector contract** (`MachineConnector`): `{ capabilities(), subscribe(cb)→unsub, fetchEvents(sinceIso), health() }` — **already supports both webhook push (`subscribe`) and polling (`fetchEvents(since)`)**. The simulator's processor/state-machine/weighing consume canonical events regardless of source.
- `[EXISTS]` **Downstream (unchanged by source):** `src/lib/rolls.js` auto-doff + estimate placeholder, scale weighing as the primary weight, shift fixed at completion (`rolls.routes.js:102`), operator attribution, `busy_audit_log`/`audit_logs`.

## 2. Revised target architecture `[PROPOSED]`
```
Vendor cloud [VENDOR?]  ──(poll fetchEvents / webhook subscribe)──┐
ESP32 firmware (x-api-key) ──POST /api/live-data (:8090)──┐       │
mes-bridge poller          ──POST /api/live-data (:8090)──┤       │
                                                          ▼       ▼
                        (existing sink + NEW VendorCloudMachineAdapter)
                                                          │
                                 canonical MachineEvent (events.js)
                                                          ▼
                 Device Event Processor → Roll Completion state machine
                   (idempotency, ordering, offline replay)      │
                                                          ▼
          existing roll engine (rolls.js) · scale weighing (primary) ·
          shift allocation (completion-shift) · operator attribution · audit
```
A **new `VendorCloudMachineAdapter`** implements the existing `MachineConnector` interface and becomes one more **source** feeding the same canonical pipeline — it does **not** replace the roll/weighing/shift/audit layers. The vendor cloud is an **outbound** integration (MES pulls/receives from the vendor); `/api/live-data` remains the **inbound push** path for on-prem collectors. They coexist.

## 3. Component keep / replace / retire-later
| Component | Decision | Rationale |
|---|---|---|
| `POST /api/live-data` route + sink | **KEEP** | source-agnostic; still used by ESP32 + mes-bridge; cloud data can also normalise into the same canonical pipeline |
| `dcApiKeyGuard` (fail-closed) | **KEEP** | protects the push endpoint while **any** collector posts; unrelated to vendor-cloud auth |
| `machine_live_data` / `machine_status_log` / `kg_per_counter` logic | **KEEP** | shared, source-agnostic telemetry sink |
| `production-sim` (adapters, processor, state machine, weighing, validation) | **KEEP + extend** | add `VendorCloudMachineAdapter` as a new `MachineConnector`; mock stays the default |
| `rolls.js` / weighing / shift / operator / audit | **KEEP unchanged** | only the event **source** changes, never the business layer |
| **ESP32 firmware collectors** | **KEEP (fallback) → retire-later per machine** | they were built because the vendor collector→cloud path was unproven; keep for machines not covered by the cloud and as a fallback; retire only for a machine once the cloud is proven for it |
| **mes-bridge** (on-prem vendor-DB poller) | **KEEP → retire-later** | if the vendor **cloud** supplies everything the on-prem `CM_Data_Acquisition` DB did, the cloud adapter supersedes mes-bridge — but only after it is proven across the fleet |
| `backend/loadtest/run.js` | **KEEP** | dev tool only |

### 3.1 Answers to the specific questions
1. **Unnecessary if cloud provides all data:** the **mes-bridge on-prem poller** (its vendor-DB-polling role is superseded by the cloud adapter) and the **ESP32 collectors for cloud-covered machines**. Neither is removed now — both become **retire-later**, per-machine, only after the cloud is proven.
2. **Must remain:** `/api/live-data` + `dcApiKeyGuard`, the telemetry sink, and the ESP32/mes-bridge paths for **any machine the cloud does not cover** (mixed fleet / older or other-brand machines) and as fallback.
3. **Do `/api/live-data` + `dcApiKeyGuard` stay necessary?** **Yes** — as long as even one on-prem collector (ESP32 or mes-bridge) posts. They are independent of the vendor-cloud (outbound) path and should not be removed.

## 4. `VendorCloudMachineAdapter` design `[PROPOSED]` / `[VENDOR?]`
Implements `MachineConnector`:
- `capabilities()` → `{ kind: 'vendor-cloud', mode: 'poll'|'webhook', writes_to_real_machine: false }` — mode chosen from what the vendor actually supports `[VENDOR?]`.
- **Polling** (`fetchEvents(since)`): on an interval (via the existing `jobLock.schedule`) call the vendor REST API `[VENDOR?]` for events since a stored cursor; normalise to canonical events; hand to the Device Event Processor.
- **Webhook** (`subscribe(cb)`): a new inbound endpoint receives vendor push `[VENDOR?]`, verifies a signature `[VENDOR?]`, normalises, and invokes `cb`.
- `health()` → connection/cursor/last-sync state.
- **Flag-gated OFF by default** (reuse the `production-sim` flag pattern, e.g. `PRODSIM_VENDOR_CLOUD`); mock remains the default; never writes to the vendor.

## 5. Non-functional requirements `[PROPOSED]` (shapes known; vendor specifics `[VENDOR?]`)
| Concern | Requirement | Vendor-dependent? |
|---|---|---|
| Authentication | outbound credential via secret store, least-privilege, never in source | method/format `[VENDOR?]` |
| Pagination | cursor/offset by event-id or time window | style `[VENDOR?]` |
| Rate limits | respect vendor caps; backoff on 429 | limits `[VENDOR?]` |
| Retries | exponential backoff, bounded; transient→retry, permanent→MANUAL_REVIEW | — |
| Event timestamps | keep **observed_at** (device/cloud) vs **received_at** (MES) distinct | zone/format `[VENDOR?]` |
| Deduplication | idempotency key `(source, device_id, event_id)` — already enforced by the processor | whether cloud supplies a stable event id `[VENDOR?]` |
| Historical recovery | `fetchEvents(since)` replays from the stored cursor (`device_sync_state`, proposed in report 29 §10) | retention/window `[VENDOR?]` |
| Offline replay | buffer + resume from cursor after an outage; processor dedups replays | — |

## 6. Vendor-event → canonical envelope mapping `[PROPOSED]` / `[VENDOR?]`
| Canonical field | Source (to be confirmed from vendor docs) |
|---|---|
| `event_id` | vendor event id `[VENDOR?]`; else synthesised `(device_id, observed_at, seq)` |
| `device_id` → `machine_id` | vendor machine/device id mapped via `device_registry`/`machines.dc_id` `[EXISTS mapping]` |
| `type` | vendor event type → one of RUNNING/COMPLETION/STOP/RESTART/FAULT/COUNTER/GREEN_LIGHT `[VENDOR? which exist]` |
| `counter` | vendor production counter `[VENDOR?]` (secondary validation only; never the roll weight) |
| `green_light` | vendor completion/lamp signal `[VENDOR? if exposed]` |
| `observed_at` / `received_at` | vendor timestamp `[VENDOR?]` / MES ingest time |
| `source` | `'vendor-cloud'` |
Unmapped device → reject to MANUAL_REVIEW (no auto-create), mirroring the existing warehouse-mapping rule.

## 7. Preserved behaviour (must not change)
`[CONFIRMED]` The cloud adapter changes only the **event source**. Unchanged: roll-ID format and one-open-roll-per-machine (`rolls.js`), **actual scale weight stays the primary quantity** (counter only secondary), **shift fixed at completion** (established rule, `rolls.routes.js:102` — late weighing never reassigns it), operator attribution (RFID/login), and the audit trail. The state machine's guards (stop-alone/green-alone/restart-alone never create a roll; duplicate deduped) apply identically to cloud-sourced events.

## 8. Cannot be designed until vendor API docs arrive `[VENDOR?]`
Transport (REST poll vs webhook vs both); base URLs/endpoints; **authentication method**; exact field names/types; **which events the cloud actually emits** (completion / green-light / stop / restart / fault / counter) — if none, completion must be **MES-derived** from counters (lower fidelity); counter semantics (per-roll vs cumulative, reset/rollover, units); pagination style; rate limits; historical-retrieval window; timestamp format/zone; whether a stable event id exists for dedup; webhook signature/verification. **No adapter code can be finalised before these are supplied.**

## 9. Migration risks & backward-compatibility plan
- **Dual-source double counting:** if both the cloud and an ESP32/mes-bridge feed the **same** machine, counters/rolls could be duplicated. → **One authoritative source per machine** via `device_registry`; processor idempotency is a second line of defence.
- **Event gaps:** if the cloud lacks completion/green-light, doff detection degrades to counter-derived (risk of false/missed rolls). → keep ESP32 as the higher-fidelity fallback where needed.
- **Cutover safety:** run the cloud adapter in **shadow/parallel** (ingest + reconcile, no roll finalisation) against the existing path before switching a machine.
- **No regression to the push path:** `/api/live-data` + `dcApiKeyGuard` stay; the recently hardened fail-closed guard is unaffected.
- **Flag-gated, mock-default:** cloud adapter OFF by default; enabling it activates only the adapter, never a write to the vendor.

## 10. Recommended implementation sequence `[PROPOSED]`
A. **Obtain + review vendor cloud API documentation** (hard blocker — §8).
B. Define the concrete vendor→canonical mapping from the real docs.
C. Build `VendorCloudMachineAdapter` (polling first if REST), flag OFF, tested against a **mock vendor-cloud** fixture — no real connection.
D. **Shadow-run** on one pilot machine (SJ03): ingest + reconcile cloud counters against the existing path; finalise no rolls yet.
E. Per-machine **cutover** with ESP32/mes-bridge retained as fallback.
F. **Retire-later** superseded collectors only after the cloud is proven across the whole fleet; keep `/api/live-data` + `dcApiKeyGuard` as long as any collector remains.

---
## Safety confirmation
Read-only assessment. No code / schema / migration / firmware modified; no ESP32, mes-bridge or `live-data` route removed; no vendor endpoint/auth/field invented; no vendor-cloud connection; nothing deployed. Existing roll-generation, operator attribution, scale weighing, shift allocation and audit behaviour are preserved by design. File saved, **not committed**, pending review.
