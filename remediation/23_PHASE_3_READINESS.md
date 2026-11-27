# 23 — Phase 3 Readiness Report (for Management Review)

**Date:** 2026-11-27 · **Branch:** `claude/mes-busy-remediation` · **HEAD at report time:** `b0c112a` · **Working tree:** clean.
**This is a readiness report only. No real BUSY integration is authorised or implemented. Feature flags remain OFF; no BUSY connection; no code/baseline change in this task.**

**Labels used:** `[FACT]` = verified this session with evidence · `[REPORTED]` = stated in an earlier committed deliverable · `[RECOMMENDATION]` = proposed, pending approval · `[UNVERIFIED]` = requires evidence not available to this session.

---

## 1. Executive summary
- `[FACT]` The remediation branch is intact at `b0c112a`, in sync with origin, working tree clean. The mock-first BUSY integration (Phases 2 / 2.1) and the Phase 2.2 specifications (docs 19–22) are all present. Integration feature flags are **OFF by default** and the connector **defaults to `mock`** and **throws on any real adapter** (unimplemented) — verified in code.
- `[FACT] 🔴 Security is NOT closed.` Both `Nakuld9/dhown_mes_remidiated-` and `Nakuld9/DHOWN_LIVE_PRODUCTION_DASHBOARD` are **currently PUBLIC**, and the `server-refractor` branch (which carries the exposed Groq key and the production DB dumps) **still exists** on the original — so SEC-1 and SEC-7 material remains **reachable in public git history**. These are the top Phase-3 blockers.
- `[FACT]` The JWT fail-closed **code** fix is present and tested; production secret **rotation** is a human action with **no evidence** of completion.
- `[FACT]` Every management decision in doc 22 (D1–D7, E1–E9) is **⏳ pending** — none carries approval evidence.
- `[FACT]` The confirmed read mechanism is ACE-OLEDB read of the `.bds`; **no vendor information from doc 19 has been received** (all `❓` items still open). A real BUSY read adapter **cannot** be finalised until the vendor confirms the interface and provides samples.
- **Phase-3 gate:** do not start Phase-3 implementation until §9's security, approval and vendor blockers are closed.

## 2. Verified Phase 2.2 closeout status
| Item | Evidence | Status |
|---|---|---|
| Branch/commit/remote | `git rev-parse HEAD` = `b0c112a`; `git ls-remote` server = `b0c112a`; tracking re-asserted | `[FACT]` in sync |
| Working tree | `git status --porcelain` (excl. node_modules) = clean | `[FACT]` clean |
| Deliverables 19–22 present | `ls` shows all four `.md` (6586/5530/5881/5410 bytes) | `[FACT]` present |
| Feature flags default | `operational-events.js` reads env; none set ⇒ OFF | `[FACT]` OFF |
| Connector default / safety | `connector.js`: default `mock`; real adapters `throw 'not implemented yet'`; `assertConnector` rejects `writes_directly_to_busy_db` | `[FACT]` mock-only, direct-write forbidden |
| No code/baseline change this task | only this report is added | `[FACT]` |

## 3. Security incident closure checklist
> No secret values or personal data are reproduced below — only locations and evidence.

### SEC-1 — Exposed Groq API key
| Field | Finding |
|---|---|
| What was exposed | `[REPORTED]` a live Groq API key in `backend/.env` |
| Where | `[FACT]` original repo, branch `server-refractor`, commit `dec5183` ("Phase 1 backend architecture setup") |
| Repo public/private | `[FACT]` `DHOWN_LIVE_PRODUCTION_DASHBOARD` = **PUBLIC** (list_repos, 2026-11-27) |
| Still in reachable history? | `[FACT]` **YES** — `ls-remote` shows `server-refractor` still exists on the public original |
| Containment / remediation | `[RECOMMENDATION]` (a) make the repo **Private** now; (b) delete the stale `server-refractor` branch and/or purge `backend/.env` from history (git filter-repo/BFG); (c) verify the file 404s |
| Credential rotation | `[RECOMMENDATION] [UNVERIFIED]` **rotate/revoke the Groq key** (assume compromised; public since the commit) |
| Verification evidence needed | repo shows Private; key revoked in the Groq console; the path 404s on github.com; fork/cache check |
| **Status** | **🔴 OPEN** (exposed material still public; rotation unverified) |

### SEC-7 — Production database dumps in git history
| Field | Finding |
|---|---|
| What was exposed | `[REPORTED]` four full `pg_dump` files **with data** (`backend/backups/dhown_mes_2026-07-01/02/03/05.sql`); DDL confirms columns including `users.password_hash` (bcrypt) and partner PII (GSTIN/PAN/bank/email) |
| Where | `[FACT]` original repo, `server-refractor`, all four added in commit `dec5183` |
| Repo public/private | `[FACT]` **PUBLIC** |
| Still in reachable history? | `[FACT]` **YES** — `server-refractor` still present on the public original |
| Containment / remediation | `[RECOMMENDATION]` make Private; purge `backend/backups/` from history (delete the stale branch + filter-repo/BFG); verify 404 |
| Credential rotation / reset | `[RECOMMENDATION] [UNVERIFIED]` **force a password reset for all users** (bcrypt hashes are offline-crackable); review any secrets that were inside `app_settings` data and rotate; note the **PII exposure** for DPDP/privacy records |
| Verification evidence needed | repo Private; files 404; password-reset executed; access-log/fork review |
| **Status** | **🔴 OPEN** (production data + hashes + PII still public) |

### JWT secret exposure (tracked as SEC-2)
| Field | Finding |
|---|---|
| **Code-level remediation** (fail-closed) | `[FACT]` present on the branch: `auth.js` no longer falls back to a built-in secret — throws if `JWT_SECRET` unset and refuses the former public value (`FORMER_BUILTIN_JWT_SECRET`); commit `dc0740e`; regression test `test/jwt-fail-closed.test.js` in the 262-unit baseline. **Status: VERIFIED CLOSED (code).** |
| **Human action — production secret rotation** | `[UNVERIFIED]` the former built-in JWT value is public; the production `JWT_SECRET` must be **rotated** and set in secure env config. No evidence of rotation. **Status: PENDING VERIFICATION.** |
| Verification evidence needed | prod env sets a new random `JWT_SECRET` (not the former value); the app boots with it; old tokens invalidated |

**Distinction:** the JWT fail-closed **code** is done and tested (closed); repo-privacy, history purge and **all credential rotations/resets** (Groq key, user passwords, JWT prod secret) are **human security actions** that remain **open/unverified**.

## 4. Exact management decisions (from `22_BUSINESS_DECISION_REGISTER.md`)
Reproduced with the source's titles/options/recommendations; all **Status = ⏳ PENDING** (no approval evidence exists in the repository). Approving role and evidence-required are this report's additions `[RECOMMENDATION]`.

### Part D — Business ownership
| # | Decision | Options | Recommendation (source) | Approving role | Status | Evidence to record approval |
|---|---|---|---|---|---|---|
| D1 | Party master SoT | MES / BUSY / per-field | BUSY authoritative (accounting identity); sync BUSY→MES; conflicts→MANUAL_REVIEW | Management (owner) | ⏳ PENDING | dated written sign-off |
| D2 | Item master SoT | MES / BUSY | MES owns SKU, BUSY owns ledger item; map + MES→BUSY sync | Management | ⏳ PENDING | sign-off |
| D3 | Warehouse/material-centre ownership | MES / BUSY | **BUSY authoritative** (built): 1:1, reject unmapped, no auto-remap, no silent merge | Management | ⏳ PENDING (confirm) | sign-off |
| D4 | Statutory invoice authority | MES / BUSY | BUSY authors all tax invoices; MES pushes operational doc only; dispatch ≠ invoice | Management + accountant | ⏳ PENDING | sign-off |
| D5 | Purchase & receipt initiation | MES-only / BUSY-only / both | Both may initiate; origin recorded; circular-sync prevented | Management | ⏳ PENDING | sign-off + case rules |
| D6 | Cancellation / amendment | overwrite / reversal / new-correlated | No silent overwrite; amendment = new correlated doc; cancellation per BUSY (❓) | Management + accountant | ⏳ PENDING | sign-off + vendor behaviour |
| D7 | External-party outstanding reconciliation | MES / BUSY / both | MES authoritative (issued−recovered, correlated) — built & tested | Management | ⏳ PENDING | sign-off |

### Part E — Security & operational
| # | Decision | Recommendation (source) | Approving role | Status | Evidence |
|---|---|---|---|---|---|
| E1 | Credential storage | Env/secret only, never source | IT/Security + Management | ⏳ PENDING | policy sign-off |
| E2 | Connection security | Read-only on BUSY PC; LAN only; never public | IT/Security | ⏳ PENDING | sign-off |
| E3 | Least-privilege access | Dedicated read account; restricted drop-folder | IT/Security | ⏳ PENDING | sign-off |
| E4 | Audit logging | Append-only `busy_audit_log` (built); retention ❓ | Management | ⏳ PENDING | retention decision |
| E5 | Monitoring & alerting | Queue/connection dashboard + alerts; channel ❓ | Management + IT | ⏳ PENDING | channel decision |
| E6 | Retry limits | Max 5 + backoff (cap 1h) → MANUAL_REVIEW | IT | ⏳ PENDING | confirm numbers |
| E7 | Dead-letter handling | FAILED/MANUAL_REVIEW surfaced, never auto-discarded | IT | ⏳ PENDING | sign-off |
| E8 | Reconciliation schedule | Mirror+recon every N; on-demand; reviewer ❓ | Management + IT | ⏳ PENDING | cadence + reviewer |
| E9 | Recovery & rollback | Bridge state droppable/rebuildable; no BUSY rollback; flags = off switch | IT/Security | ⏳ PENDING | sign-off |

## 5. BUSY vendor requirements & sample-file checklist (from docs 19/20/21)
Responsible: **V** = BUSY vendor/partner · **M** = DHOWN management · **D** = DHOWN MES team. "Blocks Phase 3 (read-only)?" marks items that gate the **read** adapter specifically.

| # | Requirement / question (source) | Why needed | Required response / sample | Owner | Status | Blocks P3? |
|---|---|---|---|---|---|---|
| 1 | BUSY **edition / version / licence / seats** (19§1) | XML import excluded from Basic; gates write path | edition+version+licence confirmation | V/M | ❓ open | No (read), Yes (write) |
| 2 | **Deployment topology** (single PC/LAN/cloud) + `.bds` path + MES reachability (19§2, 20§5) | decides where the read runs + file access | written confirmation + path | V/M | ❓ open | **YES** |
| 3 | **Supported methods** confirmation (19§3) | no assumed REST API | which of: `.bds` read / XML / Excel / partner API, with docs | V | ❓ open | **YES** (read method) |
| 4 | **Warehouse/material-centre master** table/columns (19§4, 20§5) | mapping is BUSY-authoritative | table/column spec or a sample extract | V | ❓ open | **YES** |
| 5 | **Item master** table/columns (20§5) | item mapping | table/column spec | V | ❓ open | **YES** |
| 6 | **Voucher reference** field + which field carries our integration id (19§4, 20§3/§5, 21§3) | reference readback + reconcile | confirmation of field(s) | V | ❓ open | Partial (read of refs) |
| 7 | **Sample XML/Excel exports** of purchase, receipt, dispatch vouchers (19§5/§8, 21§5) | reverse-engineer write + read schema | real sample files from DHOWN's BUSY | V/M | ❓ open | No (write); helps read |
| 8 | **Who imports** (person vs scheduled) + drop-folder (21§5) | write automation | confirmation | V | ❓ open | No (write) |
| 9 | **GST/tax-ledger mapping** on import (21§2) | correct vouchers | tax config confirmation | V | ❓ open | No (write) |
| 10 | **Cancellation/amendment** behaviour (19§5, 21§3, 22 D6) | correction policy | confirmation | V | ❓ open | No |
| 11 | **`.bds` Jet password** handling + least-privilege read account (19§6, 20§4) | secure read access | handling confirmation (value via secret flow, not here) | V/D | ❓ open | **YES** |
| 12 | **64-bit ACE Database Engine** installed on BUSY PC (20§5) | ACE-OLEDB read works | confirmation | V | ❓ open | **YES** |
| 13 | **Channel-partner contact** + licence/add-on/cost (19§7) | support + method licensing | contact + cost | V/M | ❓ open | Partial |

**Blocking the read adapter specifically:** items 2, 3, 4, 5, 11, 12 (and partially 6, 13). None can be assumed; **no vendor response has been received.**

## 6. Proposed Phase 3 read-only adapter plan `[RECOMMENDATION]` (do not implement yet)
- **Boundaries:** a new `AceOledbReadConnector` behind the **existing `BusyConnector` interface**; the **mock connector stays** the default and the test backend. Selected only via `BUSY_CONNECTOR=ace` once built; no write methods implemented (`can_push_document:false`).
- **Mechanism (pending vendor evidence, item 3/12):** Windows-side ACE-OLEDB reader (`Mode=Read`, SELECT-only) → normalised JSON to a read drop-folder → MES ingest into the existing read-mirror; the MES host never opens ACE-OLEDB.
- **Data retrieved (read-only):** company, party, item, warehouse/material-centre masters; voucher references; ledger balances/TB (per doc 20 §2).
- **Field mapping & validation:** map into `busy_master_mapping` (warehouse first, 1:1, reject unmapped); validate JSON schema before replacing the mirror; `as_of`/`source` on every row.
- **Pagination / incremental:** full master sets + **date-ranged** day book; incremental per FY — **final design pending confirmation** of table structure (items 4–6).
- **Error handling / health:** atomic extract (no partial mirror); `busy_connection_state` online/stale; timeouts (recommend 30s).
- **Logging / audit:** extractor run log + ingest audit; append-only.
- **Reconciliation:** extend the proven `busy-mirror` TB reconciliation (14/14) with document-reference reconciliation into `busy_reconciliation`.
- **Test strategy:** all development against **scratch PG18 + mock/fixtures**; a BUSY **read-only** test company only after the verification plan (§8); preserve 262/14/48 baselines + add read-adapter fixture tests.
- **Rollback/disable:** `BUSY_CONNECTOR=mock` reverts instantly; the read-mirror is droppable/rebuildable; **no business data touched**.
- **Cannot be finalised until vendor confirms:** the read method (ACE vs other), the warehouse/item/voucher table structures, the reference field, `.bds` access/password handling, and ACE-engine availability (items 2–6, 11, 12).

## 7. Read-only permission & credential requirements `[RECOMMENDATION]`
- **Read-only** access to a **vendor-approved BUSY TEST company** only. **No** voucher create/edit/cancel/post. **No** write to BUSY's internal DB. **No** access to the live accounting company for development.
- **No production credentials** in dev/test; **no real credentials requested, generated, stored or configured in this task.**
- Secrets (`.bds` password, any API key) via **secure secret storage / environment only**, restricted access; documented **rotation & revocation** procedure; connection/access **audit** enabled.

## 8. BUSY test-company verification plan `[RECOMMENDATION]` (no connection in this task)
Prerequisites: confirmed edition/licence/topology (items 1–3); a **vendor-approved read-only test company**; a **backup** of that company before any access; representative master + voucher samples.
Controlled steps (future, gated): read-only connect to the test company → validate field mappings against the samples → record **counts** and a **sample reconciliation** (TB to the rupee, as the mock proves) → **repeated-read consistency** checks → **error/timeout** handling checks. **Management acceptance evidence:** the counts, the reconciliation result, the consistency check, and confirmation that **no write/post** occurred (read-only account + audit).

## 9. Phase 3 blocker & dependency register
| Category | Blocker | Owner | Evidence to close | Impact if unresolved |
|---|---|---|---|---|
| **Security** | SEC-1 Groq key still public (`server-refractor`, public repo) | Management/IT | repo Private + history purged + key revoked | key abuse; cannot responsibly proceed |
| **Security** | SEC-7 prod dumps (hashes+PII) still public | Management/IT | repo Private + purged + user password reset | data-breach exposure; privacy/DPDP risk |
| **Security** | JWT prod secret rotation | IT | new random `JWT_SECRET` in prod env | forgeable tokens if unrotated |
| **Approval** | Doc 22 D1–D7, E1–E9 all pending | Management | dated sign-off recorded | integration semantics undecided |
| **Vendor** | Edition/method/topology unconfirmed (items 1–3) | Vendor/Mgmt | written confirmation + docs | read method cannot be finalised |
| **Vendor** | Warehouse/item/voucher table structure + ref field (items 4–6) | Vendor | table specs / samples | mapping + reference readback undefined |
| **Vendor (samples)** | XML/Excel samples (item 7) | Vendor/Mgmt | real export files | write schema unknown (later phase) |
| **Test-company** | Approved read-only test company + backup (§8) | Vendor/Mgmt | company name + backup evidence + read-only account | cannot validate safely |
| **Technical** | ACE engine + `.bds` access/password handling (items 11,12) | Vendor/IT | confirmation + secret via secure flow | read adapter cannot run |
| **Operational** | Monitoring/alerting, retention, recon cadence (E4,E5,E8) | Management/IT | decisions recorded | ops governance incomplete |

## 10. Explicit management approval gate
**Phase 3 (real read-only adapter) must NOT begin until ALL of the following are evidenced:**
1. **Security closed:** both repos **Private**, `server-refractor` purged (SEC-1/SEC-7), and **credentials rotated/reset** (Groq key, user passwords, prod JWT secret) — with verification evidence.
2. **Management sign-off** of doc 22 (D1–D7, E1–E9), recorded.
3. **Vendor confirmation** of edition/method/topology + warehouse/item/voucher structures + reference field + ACE/`.bds` access (checklist §5 read-blockers), with documentation.
4. A **vendor-approved read-only BUSY test company** with a backup and a **read-only** account.

Until then: flags stay OFF, connector stays `mock`, **no BUSY connection, no writes, no posting, no deployment.**

---
*Prepared from verified repository state and the committed deliverables 19–22. Facts are evidenced this session; human security actions and vendor responses are explicitly marked unverified/pending.*
