# 14 — BUSY Connector Design (Phase 2, mock-first)

**Date:** 2026-11-27 · Branch `claude/mes-busy-remediation`.
**Scope:** replaceable BUSY connector abstraction + mock adapter + integration-state schema. **No live BUSY connection, no live writes, no voucher creation/posting, no deployment.** The mock proves the **bridge** is correct; it does **not** prove real BUSY compatibility.

---

## 1. Architecture

```
MES domain events ─▶ busy bridge (src/lib/busy/)
                     ├─ schema.js   integration-state tables (mapping/queue/audit/recon/health)
                     ├─ identity.js external_reference (deterministic idempotency key + origin)
                     ├─ mapping.js  DHOWN↔BUSY master mapping (warehouse-first, hard-fail)
                     ├─ queue.js    idempotent enqueue · atomic claim · retry/backoff · reconcile · audit
                     └─ connector.js  selectConnector() ─▶ BusyConnector (interface)
                                                            ├─ MockBusyConnector     (default — dev/tests)
                                                            ├─ AceOledbReadConnector (read; proven — to productionise)
                                                            ├─ XmlDocConnector       (write; PRIMARY candidate — unbuilt)
                                                            ├─ ExcelDocConnector     (write; fallback — unbuilt)
                                                            └─ PartnerApiConnector   (if ever licensed — unbuilt)
```
`require('./lib/busy')(pool)` returns `{ ensure, connector, capabilities, mapping, queue, enqueue, processDue, reconcile, health }`. The connector is chosen by `BUSY_CONNECTOR` (default `mock`); a real adapter is **never** selected silently — requesting an unbuilt one throws.

## 2. The `BusyConnector` contract
Every adapter implements: `capabilities()`, `health()`, `listMasters(entityType)`, `pushDocument({external_reference, entity_type, operation, direction, payload})`, `getDocumentReference(external_reference)`, `getPostingStatus(busy_reference)`. `assertConnector()` enforces the methods **and refuses any adapter whose `capabilities().writes_directly_to_busy_db === true`** — Condition 9 is enforced in code, not just prose.

**Capability descriptor** (the bridge consults this instead of assuming a method exists): `method`, `can_read_masters`, `can_push_document`, `can_return_reference`, `is_async_posting` (BUSY posts later → `AWAITING_BUSY`), `can_read_posting_status`, `writes_directly_to_busy_db` (must be false).

## 3. Vendor compatibility status (what is known / unknown)

| Topic | Status |
|---|---|
| Public REST API | **Does not exist** (confirmed). The design assumes none. |
| READ (BUSY→MES) | **Proven** via ACE-OLEDB read of the `.bds` (validated on COMP0004 in report 02); productionise `tools/busy-bridge/extract-busy.ps1` → `AceOledbReadConnector`. |
| WRITE (MES→BUSY) | **Primary candidate = XML / Excel voucher import** (`Administration → Data Export/Import`). Unbuilt; needs a real export schema + edition confirmation. Partner-dev API is the alternative if licensed. |
| Edition / licence | **UNKNOWN — must confirm.** XML import/export is **excluded from BUSY Basic**. |
| Authentication / connection | READ: ACE-OLEDB with the `.bds` Jet password (via `BUSY_BDS_PASSWORD` env, never source). WRITE: file drop-folder import (who triggers it — person vs scheduled job — **unknown**), or partner-API credentials (**unknown**). |
| Document creation | Via file import (XML/Excel) — **not** a synchronous API call in the likely path → model as `AWAITING_BUSY` until confirmed. |
| Reference retrieval | The BUSY voucher/doc number read back from an export file or the read-bridge — **mechanism to confirm**. |
| Posting / voucher behaviour | BUSY posts on import; semantics decoded for READ (Tran2 RecType=1). WRITE posting behaviour **to confirm** against a real import. |
| Error handling / reconciliation | No BUSY-side undo → the bridge stages, validates, is idempotent, and reconciles MES-outbound vs BUSY-confirmed. |

**Explicit unknowns (blocking a real connector):** exact BUSY edition/version/licence; the real XML/Excel voucher-import schema; who performs the BUSY-side import and how the reference is surfaced back; whether a partner-dev write API is licensed; the `.bds`/import file locations on the deployment (single PC / LAN / cloud).

## 4. Mock adapter (default)
`MockBusyConnector` is deterministic: `pushDocument` returns a **pure-function** BUSY reference (`BUSY-MOCK-<sha1(external_reference)>`), so replays/retries never create a duplicate. It supports test injection: `failRefs` (permanent), `flakyRefs` (N transient failures then success), `asyncRefs` (`AWAITING_BUSY`), and `masters` (mock BUSY masters for mapping). **It is labelled everywhere as not proving real-BUSY compatibility.**

## 5. Source-of-truth & safety (unchanged)
- **MES** = production/operations SoT. **BUSY** = accounting/financial SoT. **Bridge** = integration state only (never a second ledger).
- **Never** writes to BUSY's internal DB (enforced by `assertConnector`).
- Credentials (`BUSY_BDS_PASSWORD`, any partner-API key) live in **environment configuration only** — never in source. A real key would be requested as a network secret, not committed.

## 6. Remaining vendor/business decisions (before any real connector)
1. Confirm BUSY **edition/version/licence** and deployment topology.
2. Obtain a **real XML/Excel voucher-import sample** to build the write schema, or confirm a **partner-dev API**.
3. Confirm who triggers the BUSY-side import and how the **voucher reference** returns.
4. Confirm the **master source-of-truth** per entity (warehouse = BUSY authoritative is assumed and built).
