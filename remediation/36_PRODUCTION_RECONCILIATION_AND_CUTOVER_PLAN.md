# 36 — Production Reconciliation & Cutover Plan (Vendor-Cloud Integration)

**Date:** 2026-11-28 · **Branch:** `claude/mes-busy-remediation` · **HEAD:** `2055c94`.
**Read-only plan.** No code/schema/migration/firmware change; no vendor or production connection; ESP32, mes-bridge, `live-data` routes, roll-generation, shift logic and BUSY integration untouched. **No vendor detail invented; no tolerance invented** — every threshold is a `PENDING MGMT` decision unless an existing rule already defines it.

**Labels:** `CONFIRMED` (current code) · `PROPOSED` (design) · `PENDING VENDOR` · `PENDING MGMT`.

---

## Phase 3 — Data reconciliation design
### Sources being compared `CONFIRMED` (existence) / `PROPOSED` (the comparison job)
| Source | Where it lives today |
|---|---|
| Vendor-cloud machine events | `PENDING VENDOR` (via `VendorCloudMachineAdapter`, not built) |
| MES machine status | `machine_live_data`, `machine_status_log` (`live-data.routes.js`, `machine.js`) `CONFIRMED` |
| MES roll-completion records | `rolls` table; `rolls.js`/`rolls.routes.js` `CONFIRMED` |
| Actual measured roll weights | `rolls.actual_weight_kg` (scale weight primary) `CONFIRMED` |
| Shift-wise production | `production_records` (allocated to `roll.shift`, `rolls.routes.js:102`) `CONFIRMED` |
| Counter-derived production estimate | counter×`kg_per_counter` (`live-data.routes.js`) — **secondary only** `CONFIRMED` |

### Reconciliation checks `PROPOSED`
1. **Event→status:** every vendor COMPLETION/STOP has a matching `machine_status_log`/live row. *Flag:* MISSING_IN_MES / MISSING_IN_CLOUD.
2. **Completion→roll:** every accepted completion has exactly one roll; no completion without a roll; no roll without a source event. *Flag:* ORPHAN_ROLL / UNLINKED_COMPLETION.
3. **Measured vs counter-estimate:** per roll, compare `actual_weight_kg` (scale) against the counter-derived estimate. *Flag:* WEIGHT_VS_COUNTER_DIVERGENCE when the gap exceeds a threshold `PENDING MGMT`.
4. **Shift totals:** `production_records` per shift vs the sum of that shift's roll weights. *Flag:* SHIFT_TOTAL_MISMATCH.
5. **Counter continuity:** monotonic counters per machine, resets accounted. *Flag:* COUNTER_GAP / UNEXPLAINED_RESET.
6. **Missing events:** expected-but-absent completions over a window. *Flag:* MISSING_EVENT (test T15).

### Outcomes & handling `PROPOSED`
Each check yields `MATCH | MISMATCH | MISSING`; mismatches are **surfaced, never auto-corrected**, and routed to MANUAL_REVIEW with full audit. **The scale-measured weight remains authoritative; the counter estimate is only a cross-check** (consistent with `rolls.js`).

### Tolerances & thresholds — `PENDING MGMT` (not invented here)
| Threshold | Needed for | Status |
|---|---|---|
| Max acceptable weight-vs-counter divergence (per roll) | check 3 | **PENDING MGMT** |
| Max acceptable shift-total variance | check 4 | **PENDING MGMT** |
| Missing-event detection window + alert threshold | check 6 | **PENDING MGMT** |
| Reconciliation run cadence (e.g. per shift / hourly) | scheduling | **PENDING MGMT** |
| `AWAITING_BUSY`-style staleness windows for cloud lag | checks 1/6 | **PENDING MGMT** |
*(No default values are assumed; management must set each before acceptance sign-off.)*

---

## Phase 5 — Security & deployment readiness
| Area | Requirement | Status |
|---|---|---|
| Secure credential storage | vendor credential in env/secret store only, never in source/logs; read via the environment | `PROPOSED` |
| Read-only vendor access | least-privilege, **read-only** cloud credential; no machine-control scope | `PENDING VENDOR` (item 15, report 35) |
| Network / outbound access | explicit allowlist of the vendor base URL(s); no inbound exposure of Postgres (port stays `127.0.0.1`) | `PROPOSED` |
| Retry / rate-limit protection | bounded backoff within vendor limits; permanent failures → MANUAL_REVIEW | `PROPOSED` / limits `PENDING VENDOR` |
| Logging without secrets | log connection/errors/cursors but **never** tokens or keys (mirrors `dcApiKeyGuard` which logs no key) | `PROPOSED` |
| Feature-flag rollout | `VendorCloudMachineAdapter` **OFF by default** (reuse `production-sim/flags.js` pattern); mock stays default | `PROPOSED` |
| Shadow mode | adapter ingests + reconciles but **finalises no rolls** until signed off | `PROPOSED` |
| Per-machine cutover | one authoritative source per machine via mapping; switch machine-by-machine | `PROPOSED` |
| Rollback / fallback | disable the flag → fall back to ESP32/mes-bridge; droppable bridge state; **ESP32 and mes-bridge are retained, not removed** | `PROPOSED` |

### Separate pending operational task (do not conflate)
**`dcApiKeyGuard` fail-closed hardening (commit `8cf3369`) is NOT deployed and NOT production-verified.** Its deployment (set `DC_API_KEY` in prod + confirm collectors send `x-api-key`, per report 32) is a **separate** operational task and a prerequisite for securing the push path — it is **not** part of this cutover and is not claimed as done.

---

## Cutover sequence `PROPOSED`
1. **Vendor docs intake** (report 35, all [M] answered) + sandbox. — blocker
2. **Mapping + adapter** built behind flag OFF, mock-tested (no real connection). — separate approval
3. **Duplicate-source policy** set: authoritative source per machine recorded in mapping (test T16).
4. **Shadow run** on pilot machine **SJ03**: ingest + reconcile vs the existing counter/collector path; finalise no rolls; review mismatches against `PENDING MGMT` tolerances.
5. **Management acceptance:** report-34 tests pass in sandbox; reconciliation within agreed tolerances.
6. **Per-machine cutover** with ESP32/mes-bridge retained as fallback; monitor reconciliation.
7. **Retire-later** superseded collectors only after the cloud is proven fleet-wide (report 33). `/api/live-data` + `dcApiKeyGuard` remain while any collector exists.

### Backward-compatibility guarantees
- ESP32, mes-bridge and `/api/live-data` remain operational throughout.
- Roll-ID format, one-open-roll-per-machine, scale-weight-primary, completion-shift allocation, operator attribution and audit are unchanged — the cloud only adds an event **source**.
- Rollback is a flag toggle; no data migration is required to fall back.

---
## Outstanding decisions & dependencies
- **PENDING VENDOR:** all report-35 [M] items (auth, ids, status fields, counter semantics, event ids/timestamps, rate limits, webhooks/polling, sandbox, read-only scope, error model); completion/green-light availability [O].
- **PENDING MGMT:** every reconciliation tolerance, the run cadence, staleness windows, and the duplicate-source authoritative-source policy per machine.
- **Separate operational task:** `dcApiKeyGuard` production deployment (report 32) — not part of this plan, not deployed.
- **PROPOSED (needs separate approval):** the DB persistence tables (report 29 §10) and the `VendorCloudMachineAdapter` itself.

## Scope & safety
Read-only plan. No code/schema/migration/firmware change; no vendor or production connection; ESP32/mes-bridge/live-data retained; roll-generation, shift and BUSY behaviour unchanged; no vendor detail or tolerance invented. Implementation remains blocked pending vendor documentation and separate management approval.
