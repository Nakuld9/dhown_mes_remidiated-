# 02 — BUSY 21 Integration Feasibility (Deliverable #5, re-issued)

**Date:** 2026-11-26 · Supersedes the earlier generic draft. Grounded in the **actual** mechanism already reverse-engineered in this codebase and validated on real company data.

---

## 1. Headline

- **BUSY 21 has no official public REST API.** (Confirmed by research + the project's own history: *"Busy sync parked on BUSY PARTNER DEV API access."*) Do **not** design around an assumed API.
- **The READ path (BUSY→MES) is already solved and validated.** BUSY stores each company as a **password-protected MS-Access JET 4.0 `.bds`** (`C:\BusyWin\…\COMP0004\db1<yy>.bds`), read via **ACE-OLEDB (Windows-only), `Mode=Read`, SELECT-only**. Semantics decoded & verified on **COMP0004** (Dr=Cr **₹26.54 cr**, 835 ledgers; another FY mirror validated at Dr=Cr **₹36.85 cr**, net profit **₹1.24 cr**, by `busy-mirror.e2e` 14/14).
- **The WRITE path (MES→BUSY) is the real gap** — needed for workflows **D/E/F** and the new **bidirectional** Purchase/Receipt. Today it's only a **CSV export** (`busy-sync`), imported into BUSY manually.

## 2. What already exists in the codebase

| Piece | File(s) | Role | Disposition |
|---|---|---|---|
| ACE-OLEDB reader (batch) | `tools/busy-bridge/extract-busy.ps1` | Export BUSY masters + TB/P&L/BS → JSON drop-folder | KEEP / productionise |
| ACE-OLEDB reader (HTTP) | `tools/busy-bridge/busy-api.ps1` | Localhost read-only JSON API over BUSY | KEEP / optional |
| Read-mirror ingest | `lib/busy-bridge.js`, `busy-inbox.js`, `busy-masters-import.js`, `busy-mirror.js` | Ingest JSON → labelled `busy_*` mirror | KEEP / extend |
| Reconciliation | `lib/busy-reconcile.js`, `busy-mirror.e2e` | MES vs BUSY TB reconcile (✅ to the rupee) | KEEP |
| Write feed (CSV) | `busy-sync.{routes,service,repository}` | GRN + Dispatch → BUSY-import CSV | REFACTOR → DOC bridge |
| Bridge-state schema (design) | `migration_phase11_busy_bridge.sql` (carried-forward branch) | mapping/queue/audit/recon/connection | BUILD (fresh migration) |

## 3. Connector options, ranked (confirm vendor capability before locking)

| Option | Direction | Verdict |
|---|---|---|
| **A. ACE-OLEDB read of `.bds`** (existing) | BUSY→MES | ✅ **Primary READ.** Proven, validated. Windows-side, read-only, never writes. |
| **B. XML / Excel voucher import** (`Administration → Data Export/Import`) | MES→BUSY | ✅ **Primary WRITE candidate.** First-party, supported; needs name-matched masters, no preview → validation+idempotency in our bridge. **Excluded from BUSY Basic edition — confirm edition.** |
| **C. BUSY partner-dev API** | both | ⚠️ **If licensed.** True automated write. External blocker; design as a swappable adapter. |
| **D. 3rd-party REST wrappers** (BusyNotify/RootFi/Apideck) | both | ⚠️ Optional; vendor dependency; config-specific. Only after a real proof. |
| **E. Direct write to `.bds`/BUSY DB** | — | ❌ **FORBIDDEN** (Condition 9). Corrupts BUSY, voids support. |

## 4. Recommended architecture (one interface, swappable adapters)

```
BusyConnector (interface)
 ├─ AceOledbReadConnector     (A — live, read)      ← productionise extract-busy.ps1
 ├─ XmlExcelWriteConnector    (B — primary write)   ← evolve busy-sync CSV → validated DOC export
 ├─ PartnerApiConnector       (C — if licensed)
 ├─ ThirdPartyRestConnector   (D — optional)
 └─ MockBusyConnector         (default until a real BUSY is wired)
```
Connector-agnostic layer (from the carried-forward design): `busy_master_mapping`, `busy_sync_queue` (unique `external_reference` = idempotency), `busy_audit_log`, `busy_reconciliation`, `busy_connection_state`, + **document-reference tracking** (BUSY voucher no. ↔ MES txn) and **document-origin** flags for bidirectional Purchase/Receipt.

## 5. Bidirectional Purchase/Receipt (your updated workflow) — feasibility

- **MES→BUSY:** emit a validated DOC (XML/Excel) via the queue; store the returned BUSY ref after import; idempotent on `external_reference`. Feasible via Option B now; Option C later.
- **BUSY→MES:** already feasible via the ACE-OLEDB read mirror (purchase + receipt docs, posting status, **warehouse/material-centre master**, outstanding).
- **Conflict handling:** document-origin + unique integration IDs + source-of-truth per entity (your spec) → `busy_reconciliation` results (`MATCH/MISMATCH/MISSING_*/DUPLICATE`), unmatched → `MANUAL_REVIEW`. **Warehouse/material-centre must be 1:1 mapped both ways** (hard-fail on unmapped).

## 6. Open items to confirm with the vendor / you (blocking build)
1. **BUSY edition + version + licence** (Basic excludes XML import/export → changes the WRITE path).
2. Deployment: single PC / LAN / BUSY-on-cloud (where the bridge reads/writes files).
3. Is a **partner-dev API** licensed, or is XML/Excel the write path?
4. Who performs the BUSY-side import (person vs scheduled job), and how the voucher ref is surfaced back.
5. The fixed `.bds` Jet password handling (currently via `BUSY_BDS_PASSWORD` env — keep out of git).

## Sources (external)
- BUSY FAQ — [third-party integration](https://busy.in/faqs/third-party-services/integration/1/), [voucher import/export](https://busy.in/faqs/data-conversion/voucher-import-export/1/), [XML/PDF](https://busy.in/faqs/data-conversion/xml-pdf/1/). Aggregators ([Apideck](https://www.apideck.com/accounting-software/busy-accounting), [API2Cart](https://api2cart.com/supported-platforms/busy-accounting-integration/)) list BUSY as planned/not-live. Verify directly with BUSY/partner.
