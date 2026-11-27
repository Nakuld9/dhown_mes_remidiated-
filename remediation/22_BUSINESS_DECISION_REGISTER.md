# 22 — Business & Operational Decision Register (Phase 2.2)

**Date:** 2026-11-27 · **For management + vendor sign-off.** No decision here is implemented; the integration feature flags remain **OFF**, no real BUSY connection/write occurs, factory workflows are preserved.

Each row: the decision, the options, our **◻ recommendation**, and **Status** (⏳ pending approval). Verified facts are marked **✅**; vendor-dependent items **❓**.

---

## Part D — Business ownership decisions

| # | Decision | Options | ◻ Recommendation | Status |
|---|---|---|---|---|
| D1 | **Party master** source-of-truth (customer/vendor) | MES / BUSY / per-field | **BUSY** authoritative for accounting identity (GSTIN/PAN/ledger); MES holds operational contact. Sync BUSY→MES; conflicts → `MANUAL_REVIEW`. | ⏳ |
| D2 | **Item master** source-of-truth | MES / BUSY | **MES** owns the manufacturing SKU; **BUSY** owns the ledger/stock item. Map MES SKU ↔ BUSY item; MES→BUSY sync for new items. | ⏳ |
| D3 | **Warehouse / material-centre** ownership | MES / BUSY | **✅ built: BUSY authoritative.** 1:1 mapping, exact; unmapped → **reject** (`MANUAL_REVIEW`); **no auto-create, no auto-remap**; conflicts never silently merged. | ⏳ (confirm) |
| D4 | **Statutory invoice authority** | MES / BUSY | **BUSY authors all statutory (tax) invoices.** MES pushes the **operational** document (dispatch/issue) only; **dispatch is NOT auto-combined with sales invoicing.** → retire MES in-app invoice authoring **later** (Phase 7), not now. | ⏳ |
| D5 | **Purchase & receipt initiation** rules | MES-only / BUSY-only / both | **Both may initiate**, with **document-origin** recorded and **circular-sync prevented** (a BUSY-originated doc is mirrored to MES, not re-pushed). Define which side initiates in which real-world case. | ⏳ |
| D6 | **Cancellation / amendment** handling | overwrite / reversal / new-correlated | **No silent overwrite.** An amendment creates a **new correlated document** (linked by original reference); cancellation follows BUSY's supported mechanism (❓ vendor). Reconciliation flags divergence. | ⏳ |
| D7 | **External-party outstanding** reconciliation | MES-authoritative / BUSY / both | **MES authoritative** for party-wise issued/recovered/**outstanding** (subcontract module); BUSY receives the accounting document. Outstanding = Σ issued − Σ recovered, correlated by `original_ref` (**✅ built & tested**). | ⏳ |

## Part E — Security & operational design decisions

| # | Decision | Options | ◻ Recommendation | Status |
|---|---|---|---|---|
| E1 | **Credential storage** | env / secret store / source | **Environment / network-secret only, never source.** `.bds` Jet password + any partner-API key injected at runtime; keys requested via the secure secret flow. | ⏳ |
| E2 | **Connection security** | — | ACE-OLEDB **read-only** on the BUSY PC; MES↔BUSY over LAN only; **never expose** BUSY's PC / the drop-folder / DB ports publicly. | ⏳ |
| E3 | **Least-privilege access** | — | A dedicated read account for the `.bds`/share; the write drop-folder writable only by the MES-side renderer, importable only by BUSY. | ⏳ |
| E4 | **Audit logging** | — | **✅ built:** append-only `busy_audit_log` for every event outcome; MES-side `audit_logs` for operator actions. Retention policy (❓ how long). | ⏳ |
| E5 | **Monitoring & alerting** | — | Dashboard for queue states + `busy_connection_state`; **alert** on: connection stale, `AWAITING_BUSY` past threshold, `FAILED`/`MANUAL_REVIEW` growth, reconciliation mismatches. Channel (❓ email/WhatsApp). | ⏳ |
| E6 | **Retry limits** | — | ◻ `BUSY_MAX_ATTEMPTS=5` with exponential backoff (cap 1 h); then → `MANUAL_REVIEW`. Confirm the numbers. | ⏳ |
| E7 | **Dead-letter handling** | — | Rows in `FAILED`/`MANUAL_REVIEW` are the dead-letter set — surfaced, never auto-discarded; manual resolve/retry after fixing the mapping/cause. | ⏳ |
| E8 | **Reconciliation schedule** | — | ◻ read-mirror refresh + a reconciliation run every N minutes/hours (business-driven); plus an on-demand run. Confirm cadence + who reviews mismatches. | ⏳ |
| E9 | **Recovery & rollback strategy** | — | Bridge tables are **integration state only** and droppable/rebuildable; a bad run is fixed by re-mirroring + re-reconciling (no business data touched). **No rollback of BUSY** (BUSY owns its books); corrections follow BUSY's own reversal process. Feature flags provide an instant **off switch**. | ⏳ |

---

## Separation of concerns (as required)
- **✅ Verified BUSY capabilities:** ACE-OLEDB read of `.bds` (masters, postings, TB — validated on COMP0004); no public REST API; XML/Excel import is BUSY's documented write path (edition-gated); direct DB write forbidden.
- **❓ Vendor-dependent unknowns:** edition/licence, deployment topology, XML/Excel schema + who imports, voucher-reference readback field, item/warehouse table columns, cancellation/amendment behaviour, partner-API availability (see reports 19–21).
- **◻ Proposed design decisions:** the recommendations above + the read/write adapter designs — **all pending management approval and vendor documentation.**

**Stop. Request management approval of this register and the vendor documentation/samples (report 19 §8) before implementing any real adapter or enabling outward-facing integration.**
