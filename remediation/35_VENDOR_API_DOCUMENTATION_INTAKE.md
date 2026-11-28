# 35 — Machine-Vendor Cloud API — Documentation Intake Checklist

**Date:** 2026-11-28 · **Branch:** `claude/mes-busy-remediation` · **HEAD:** `2055c94`.
**Read-only.** No code/schema/firmware change; no vendor connection. This lists the **exact** information required from the Chinese machine manufacturer before any `VendorCloudMachineAdapter` work begins. **Nothing here assumes a vendor endpoint, field, auth method or capability exists** — each item is a question to the vendor.

**Legend:** **[M]** mandatory (adapter cannot be built/accepted without it) · **[O]** optional (enhances fidelity; absence has a defined fallback). Status column is filled when the vendor responds.

## Why this gates everything
The MES side is built and tested (connector interface, event processor, state machine, weighing, operator/shift/audit — report 34 Phase 1). The adapter maps vendor data onto the **canonical `MachineEvent`** envelope (`backend/src/lib/production-sim/events.js`): `{event_id, device_id→machine_id, type∈[RUNNING,COMPLETION,STOP,RESTART,FAULT,COUNTER,GREEN_LIGHT], counter, green_light, observed_at, received_at}`. Each checklist item below maps a required field/behaviour of that envelope to a vendor question.

## Checklist
| # | Item | M/O | What we need | Maps to / fallback |
|---|---|---|---|---|
| 1 | **API documentation + base URL** | [M] | Full REST (or other) API reference and the production/sandbox base URLs | the adapter's transport |
| 2 | **Authentication method + token lifecycle** | [M] | Auth type, how to obtain/refresh a credential, token TTL, expiry/refresh/revocation behaviour | credential storage (report 36); test T13 |
| 3 | **Machine/device identifiers** | [M] | The stable id each machine is known by in the cloud, and whether it survives machine replacement | `device_id`→`machines.machine_id` mapping; tests T1, T12 |
| 4 | **Available machine-status fields** | [M] | Which status/running/stopped/RPM fields exist and their meanings/enums | RUNNING/STOP mapping; test T2; else status is derived |
| 5 | **Green-light & roll-completion event support** | [O] | Whether the cloud emits a doff/completion and/or green-light signal | COMPLETION/GREEN_LIGHT; test T3. **Fallback:** completion **MES-derived from counter** (lower fidelity) |
| 6 | **Counter semantics & units** | [M] | Is the counter cumulative or per-roll; reset/rollover behaviour; units; relation to kg | counter→kg (`kg_per_counter`); tests T4, T15. **Rule:** counter is secondary validation, never the roll weight |
| 7 | **Historical event retrieval** | [O] | Whether past events can be fetched, the retention window, and the query (since-cursor/time range) | offline recovery; test T7. **Fallback:** gaps flagged by reconciliation (report 36) |
| 8 | **Event IDs & timestamps** | [M] | Whether each event has a stable unique id; timestamp format and time zone | dedup `(source,device_id,event_id)`; observed_at vs received_at; tests T5, T6. **Fallback:** synthesise an id, with weaker dedup |
| 9 | **Pagination** | [M if polling] | Page/cursor style and page size limits | polling loop; tests T7, T14 |
| 10 | **Rate limits** | [M] | Request caps, throttling response (e.g. 429), any quotas | backoff/retry; test T14 |
| 11 | **Webhooks or polling** | [M] | Whether push webhooks exist (+ signature/verification) or only polling | `subscribe` vs `fetchEvents`; both already supported by `MachineConnector` |
| 12 | **Offline buffering & replay** | [O] | Does the cloud buffer during a machine/network outage and replay on reconnect | test T7 |
| 13 | **Sandbox / test account + test machine** | [M] | A non-production environment and a test machine/device to run report-34 acceptance tests | all `PENDING VENDOR` tests |
| 14 | **API versioning & support contacts** | [M] | Version/compatibility policy and a technical support/escalation contact | long-term maintenance |
| 15 | **Read-only access scope** | [M] | Confirmation that a least-privilege, **read-only** credential is available (no control commands to machines) | security (report 36) |
| 16 | **Error model** | [M] | Error codes/shapes for auth failure, not-found, server errors | tests T13, T14 |

## Mandatory vs optional summary
- **Mandatory [M]:** 1, 2, 3, 4, 6, 8, 10, 11, 13, 14, 15, 16 (and 9 if polling). Without these the adapter cannot be built or accepted.
- **Optional [O] (defined fallback):** 5 (completion → counter-derived), 7 (history → reconciliation flags gaps), 12 (buffering → cursor replay).

## On receipt (intake procedure)
1. Record each item's answer + status in this file. 2. Resolve the report-33 `[VENDOR?]` unknowns and the report-34 `PENDING VENDOR` cases. 3. Only then design the concrete vendor→canonical mapping and begin the adapter (separate approval required). **Do not start adapter code until every [M] item is answered.**

---
*Read-only. No vendor connection; no code/schema/firmware change. Nothing here presumes any vendor capability exists — all are questions pending the manufacturer's documentation.*
