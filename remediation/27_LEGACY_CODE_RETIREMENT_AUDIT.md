# 27 — Legacy Code Retirement Audit

**Date:** 2026-11-27 · **Branch:** `claude/mes-busy-remediation` · **HEAD:** `6956db9`
**Investigation only.** No file was deleted, disabled, refactored or modified. No database, feature flag, deployment, BUSY connection or production access was touched. This document identifies candidates and classifies them; **retirement is a separately authorised task.**

**Evidence labels:** `[FACT]` verified this session (grep/require/ls) · `[REPORTED]` from an earlier committed doc · `[INFERRED]` reasoned from facts.
**Classifications:** **1 SAFE TO REMOVE** · **2 RETIRE AFTER BUSY INTEGRATION** · **3 RETIRE AFTER MIGRATION** · **4 KEEP** · **5 INVESTIGATE**.
**Rule observed:** nothing is called unused on "no direct import" alone — route registration, `require()` resolution, scheduled jobs, dynamic `require`, ESM `import`, and string/config references were checked. (Two libraries, `openai` and `pdf-parse`, initially looked unused and were confirmed **used** via ESM/dynamic import — both KEEP.)

---

## 1. Executive summary
- `[FACT]` The backend runs a **single live architecture**: `backend/server.js` mounts **88/88** `src/routes/*.routes.js` and requires the layered `src/{controllers,services,repositories,lib}`. The pre-refactor top-level `backend/{routes,controllers,services,models}` is **orphaned** (server.js comments say "migrated to layered architecture").
- `[FACT]` **Clear safe-to-remove set exists:** 6 orphaned legacy backend files, 3 scratch/diagnostic files, 1 stale tracked frontend build (43 files), 1 superseded frontend component.
- `[FACT]` **Two retirement-gated sets exist and must NOT be removed now:** (a) the **MES secondary accounting engine** (`src/lib/accounting/*`, incl. the manual `outbox.js`) — actively used, retires only after BUSY is the proven accounting authority (`[REPORTED]` decision D4, Phase 7); (b) the **legacy BUSY read mirror** (`busy-bridge.js`, `accounting/busy-mirror.js`, `busy-sync` route) — actively used, retires only after the approved read adapter is built and proven.
- `[FACT]` **One-off historical DB migrations** (20 `backend/migration_*.js`, 3 root `*.sql`, `run_migration.js`) are not invoked by the live boot path (`src/db/migrate.js` + `src/db/schema.js` + `boot-ensure.js`) but may be needed to reconstruct older production DBs → **RETIRE AFTER MIGRATION**.
- **No production workflow, accounting module, auth, audit trail or DB-compatibility artefact is proposed for removal.** The large retirements are explicitly deferred.

## 2. Architecture & dependency overview `[FACT]`
| Layer | Live path | Evidence |
|---|---|---|
| Entrypoint | `backend/server.js` (`main` in package.json) | 88 `require('./src/routes/*')`; serves top-level `frontend/build` |
| Routing/logic | `backend/src/{routes(88),controllers(31),services(31),repositories(31)}` | all 88 routes mounted |
| Shared libs | `backend/src/lib/*` (incl. `busy/`, `accounting/`, scheduled-job modules) | required by server.js |
| DB lifecycle | `src/db/migrate.js`, `src/db/schema.js` (ensure* fns), `src/lib/boot-ensure.js` | required+run at boot |
| Scheduled jobs | `src/lib/{pm-scheduler,retention,backup,wa-followups,morning-briefing,import-tracking-sync,...}` via `jobLock.schedule(...)`/`setInterval` | wired in server.js boot block |
| Frontend | top-level `frontend/src` (App.js imports 112 pages) served from top-level `frontend/build` | `express.static(__dirname/../frontend/build)` |
| BUSY (new) | `src/lib/busy/` connector (mock-first) | `[REPORTED]` Phase 2 |
| BUSY (legacy) | `src/lib/busy-bridge.js`, `src/lib/accounting/busy-mirror.js`, `src/routes/busy-sync.routes.js`, `src/lib/busy-reconcile.js` | still required |

## 3. Exact candidate file inventory (summary)
| # | Path(s) | Class |
|---|---|---|
| C1 | `backend/routes/{downtime,machines,operators,rolls}.js` | **1 SAFE** |
| C2 | `backend/controllers/machineController.js` | **1 SAFE** |
| C3 | `backend/services/rollGenerationService.js` | **1 SAFE** |
| C4 | `backend/models/README.txt` | **1 SAFE** |
| C5 | `backend/check_sj01.js`, `backend/diag.tmp.js`, `backend/test_rollid.js` | **1 SAFE** |
| C6 | `backend/frontend/build/**` (43 tracked files) | **1 SAFE** |
| C7 | `frontend/src/components/MachineGrid.jsx` | **1 SAFE** (verify dynamic) |
| C8 | `backend/migration_*.js` (20), root `migration_phase8/9/10*.sql` (3), `backend/run_migration.js` | **3 RETIRE AFTER MIGRATION** |
| C9 | `backend/src/lib/accounting/*` (MES accounting engine incl. `outbox.js`) | **2 RETIRE AFTER BUSY** |
| C10 | `backend/src/lib/busy-bridge.js`, `src/lib/accounting/busy-mirror.js`, `src/routes/busy-sync.routes.js`, `src/lib/busy-reconcile.js` | **2 RETIRE AFTER BUSY** |
| C11 | `xlsx` + `exceljs` (both deps used); `MachineCard`/`MachineCardV2`; `services/api.js` vs `utils/authFetch.js` | **5 INVESTIGATE** |

### Per-candidate evidence
**C1–C4 — Pre-refactor backend (orphaned)**
- Purpose: original non-layered machine/roll/operator/downtime routes, one controller, one service; `models/` holds only a README.
- References/imports: `[FACT]` **none** — no `require()` resolves to these paths from `server.js` or `src/` (precise path grep returned NONE); server.js mounts `src/routes/{machines,operators,rolls}.routes.js` instead (comments: "migrated to layered architecture").
- API/route deps: superseded 1:1 by `src/routes/*`. DB deps: none of their own. External deps: none. Tests: none specific. Prod use: `[INFERRED]` no (not wired). Replacement: the `src/` equivalents (already live). Risks: negligible. Action: remove after a grep-confirm + boot/test pass.

**C5 — Scratch/diagnostic scripts**
- `check_sj01.js`, `diag.tmp.js` (`.tmp` in name), `test_rollid.js`: one-off diagnostics. References: `[FACT]` 0 each. Not in jest/e2e runners (those use `test/` and `tests/`). Action: remove.

**C6 — Stale committed frontend build**
- `backend/frontend/build/**`: `[FACT]` 43 tracked files; server serves **top-level** `frontend/build` (`__dirname/../frontend/build`), not this copy. Generated output that should not be in VCS. Risk: none (not served). Action: remove (and consider git-ignoring build output).

**C7 — Superseded component**
- `frontend/src/components/MachineGrid.jsx`: `[FACT]` imported in **0** files; `MachineGridV2.jsx` is the one imported. No string/lazy reference found. Action: remove after a quick dynamic-usage confirm. Classification kept at SAFE with a verify note.

## 4. Duplicate accounting analysis (C9) — **RETIRE AFTER BUSY INTEGRATION**
- `[FACT]` `backend/src/lib/accounting/` contains a full secondary accounting engine: `outbox.js` (the manual transactional outbox), `mes-events.js`, `mes-posting.js`, `posting-rules.js`, `rules.js`, `service.js`, `documents.js`, `allocations.js`, `depreciation.js`, `interest.js`, `stock-valuation.js`, `ai-accountant.js`, `xml-lite.js`, `ops-link.js`, `migration.js`, `schema.js`, plus BUSY-facing `busy-inbox.js`, `busy-masters-import.js`, `busy-mirror.js`.
- References: `[FACT]` required by `server.js` and `src/routes/accounting.routes.js` (and others) — **actively used in production today**.
- DB deps: `[INFERRED]` owns accounting tables/ledgers + the outbox table; holds **existing accounting history and reports** that must be preserved.
- External deps: none required at runtime (self-contained ledger); overlaps conceptually with BUSY's role.
- What depends on it / what must replace it before retirement: in-app ledgers, financial dashboards, tax-invoice authoring, reports. Per `[REPORTED]` decision **D4**, BUSY becomes the sole statutory/accounting authority and MES invoice authoring retires in **Phase 7** — only **after** the BUSY integration is live and proven, and after accounting history is migrated/retained.
- Tests: `[FACT]` extensive e2e coverage (`financial`, `gst-returns`, `gstr1`, `bank-recon`, `profitability`, `cfo-dashboard`, `matrix-valuation`, etc.) — proves it is load-bearing.
- Prod use: **yes.** Replacement: BUSY (not yet connected). Risks of removal now: **severe** — loss of ledgers, reports, invoice authoring, dashboards. Action: **KEEP until BUSY integration proven; do not retire in this cleanup.** (Task constraint: "No accounting module retirement.")

## 5. Legacy BUSY integration analysis (C10) — distinguish approved vs legacy
- **Approved / keep:** `src/lib/busy/` — the mock-first replaceable `BusyConnector` (connector.js, adapters/, identity.js, mapping.js, queue.js, schema.js, operational-events.js), `[REPORTED]` Phase 2; **flags OFF**, mock default. **KEEP.**
- **Legacy (still wired, retire after the approved read adapter is proven):**
  - `[FACT]` `src/lib/busy-bridge.js` — a **read-only mirror** of BUSY figures (its header: "READ-ONLY MIRROR… never writes back to Busy"); required by `server.js`, `src/lib/busy-reconcile.js`, `src/lib/finance.js`, `src/routes/ai.routes.js`.
  - `[FACT]` `src/lib/accounting/busy-mirror.js` — overlapping read-mirror used by the AI accountant/reconciliation (`busy-mirror.e2e.js` covers it).
  - `[FACT]` `src/routes/busy-sync.routes.js` — manual sync route; required by `server.js` and `src/ai/tools/voucher.tools.js`.
  - `[FACT]` `src/lib/busy-reconcile.js` — reconciliation on top of the mirror.
- Overlap: the planned **BUSY read adapter** (`[REPORTED]` doc 20) is intended to supersede these read-mirror paths. Until that adapter is built and proven against a real BUSY test company, they remain the only source of mirrored figures.
- DB deps: `busy_*` mirror tables (droppable/re-importable per the header). External deps: BUSY export files / future ACE-OLEDB read. Tests: `busy-mirror.e2e.js`, `busy-production.e2e.js`. Prod use: **yes** (AI accountant shows these numbers). Replacement: approved read adapter (pending vendor). Risks now: loss of mirrored BUSY figures + reconciliation. Action: **RETIRE AFTER BUSY INTEGRATION**; flag `busy-bridge.js` vs `busy-mirror.js` overlap as **INVESTIGATE** for consolidation during that phase.

## 6. Database migration analysis (C8) — **RETIRE AFTER MIGRATION**
- `[FACT]` Live DB lifecycle = `src/db/migrate.js` + `src/db/schema.js` (`ensure*` functions) + `src/lib/boot-ensure.js`, all required and run at boot; baseline = `backend/schema/00_baseline_schema.sql`; provisioning = `backend/scripts/db-provision.js`. **KEEP all of these.**
- `[FACT]` **Not referenced by the live path:** 20 `backend/migration_*.js` (e.g. `migration_warehouse.js`, `migration_costing.js`, `migration_erp_phase*.js`), root `migration_phase8.sql`/`phase9.sql`/`phase10_security.sql`, and `backend/run_migration.js` (ad-hoc index creation). No live module `require()`s any `migration_*.js`.
- Risk: these are **historical one-off migrations already applied to production**. Removing them is harmless to a running DB but loses the ability to reconstruct/trace an older DB from scratch. 
- Action: **RETIRE AFTER MIGRATION** — remove only once it is confirmed (a) every production DB is at/ahead of these migrations and (b) the baseline + `ensure*`/`migrate.js` fully reproduce the schema (the provisioning work already demonstrates 185 tables from baseline — `[REPORTED]`). Preserve `backend/migrations/knitting_structures.sql` until its content is confirmed folded into baseline/ensure (**INVESTIGATE**).

## 7. Frontend & backend cleanup candidates
**Backend:** C1–C6 (safe), C8 (after migration), C9/C10 (after BUSY). No orphaned `src/routes` (88/88 mounted). Scheduled jobs all resolve to live `src/lib/*`.
**Frontend:** `[FACT]` no orphan **pages** (all referenced from `App.js`/components). Candidates:
- C7 `MachineGrid.jsx` — unreferenced (SAFE, verify dynamic).
- `[FACT]` `MachineCard.jsx` (1 import) **and** `MachineCardV2.jsx` (1 import) **and** `MachineGridV2.jsx` (1 import) are all used in different places → **INVESTIGATE** consolidation; **do not remove.**
- `[FACT]` Two client helpers: `frontend/src/services/api.js` and `frontend/src/utils/authFetch.js` (token injection) — both present; possible overlap → **INVESTIGATE** (authFetch is the documented token wrapper; `[REPORTED]` CLAUDE.md).
- Unused CSS/assets: not individually proven this pass → **INVESTIGATE** (requires a bundler/coverage check, not import grep).

## 8. Duplicate utilities & dependencies (C11) — **INVESTIGATE**
- `[FACT]` **Two Excel libraries both in use:** `xlsx` (1 backend file) and `exceljs` (2 backend files). Candidate to standardise on one — but both are currently referenced, so **not removable** without a code change (out of scope here).
- `[FACT]` Confirmed **used** (keep): `pdfkit` (6), `pdf-to-png-converter` (2), `pdf-parse` (invoice-ocr.js), `qrcode` (1), `socket.io` (1), `node-windows` (1), `openai` (ESM `import` in `src/ai/glm.js`).
- No backend dependency was proven unused this pass.

## 9. Risk classification (roll-up)
| Class | Candidates | Removal risk |
|---|---|---|
| **1 SAFE TO REMOVE** | C1, C2, C3, C4, C5, C6, C7 | Low — orphaned/scratch/stale-artifact; verify dynamic use for C7 |
| **2 RETIRE AFTER BUSY** | C9 (accounting engine), C10 (legacy BUSY read mirror/sync) | High now — load-bearing until BUSY proven |
| **3 RETIRE AFTER MIGRATION** | C8 (one-off migrations/SQL) | Medium — needs prod-schema confirmation |
| **4 KEEP** | `src/*` live architecture, `src/lib/busy/`, backup feature, scheduled jobs, both test dirs, auth, deploy scripts, all confirmed-used deps | — |
| **5 INVESTIGATE** | xlsx/exceljs, MachineCard vs V2, api.js vs authFetch, busy-bridge vs busy-mirror overlap, unused CSS/assets, `migrations/knitting_structures.sql` | Needs more evidence before classing |

## 10. Recommended retirement sequence (when separately authorised)
1. **Batch A (SAFE, lowest risk):** C5 scratch files → C4 README → C1–C3 orphaned backend → C6 stale build → C7 component. After each batch: boot the server + run unit (24) and e2e (48) suites; confirm green; confirm no route/asset 404.
2. **Batch B (after migration confirmation):** C8 — only once every prod DB is confirmed at/ahead and baseline+ensure reproduce the schema. Keep the files in Git history for traceability.
3. **Batch C (INVESTIGATE resolutions):** consolidate xlsx/exceljs, MachineCard variants, api.js/authFetch, and the busy-bridge/busy-mirror overlap — each as its own small, test-backed change.
4. **Batch D (after BUSY integration proven, Phase 7):** C10 legacy BUSY read mirror, then C9 MES accounting authoring — **only** after BUSY is the proven authority and accounting history is retained/migrated. Out of scope for any near-term cleanup.

## 11. Tests required before and after removal
- **Before:** capture the current green baseline — unit **24** (`backend/test/*.test.js`), e2e **48** (`backend/tests/*.e2e.js`), plus a clean server boot and a frontend build. `[REPORTED]` baselines: 262 unit / 14 BUSY / 48 e2e.
- **After each batch:** re-run the identical suites + boot + frontend build; diff route list (88 mounted) and provisioned table count (185); for frontend, load the app and confirm no missing-module/asset errors. Any suite that was green must stay green with **no weakened assertions**.
- **Never** retire a module whose e2e suite would have to be deleted or skipped to pass (that is a signal it is load-bearing).

## 12. Items that must remain untouched
All factory production workflows (shift-wise production, machine/material issue, GRN/purchase, dispatch, external-party issue & recovery), production dashboards, **the MES accounting engine and its history/reports** (C9 — defer only), authentication/authorisation (`src/middleware/auth.js`), audit trails (`busy_audit_log`, `audit_logs`), existing DB compatibility (baseline + `ensure*`/`migrate.js`), the approved `src/lib/busy/` connector (flags stay OFF), backup feature, and all deployment scripts. **DHOWN MES remains the manufacturing source of truth; BUSY 21 remains the sole core accounting/financial source of truth.**

---
## Safety restrictions observed by this task
Investigation only. No file deleted/modified; no code, DB, feature flag, deployment, BUSY connection, production access, workflow or accounting module changed; no Git history rewritten. All evidence gathered read-only. Retirement must not begin until separately authorised.
