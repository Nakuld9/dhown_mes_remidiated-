# 19 — BUSY Vendor & Environment Requirements (Phase 2.2)

**Date:** 2026-11-27 · Branch `claude/mes-busy-remediation`. **Documentation only — no BUSY connection, no writes, no deployment.**
**Purpose:** the exact information to obtain from the BUSY vendor / channel partner and DHOWN management before any real adapter is built. **Do not assume a generic REST API.**

Legend: **✅ VERIFIED** (established from the `busy21-re` reverse-engineering on the real company `COMP0004`, or from the committed `tools/busy-bridge/` read tooling) · **❓ UNKNOWN** (must be confirmed) · **◻ PROPOSED** (our design assumption pending confirmation).

---

## 1. Edition, licence & company configuration
| Item | Status | What we need |
|---|---|---|
| BUSY **edition** (Basic / Standard / Enterprise) | ❓ | Confirm — **XML import/export is excluded from Basic**; this gates the primary write path. |
| BUSY **version / build** (the "BUSY 21" line = 2021 release) | ❓ | Exact version + latest patch level. |
| **Licence type** & seats | ❓ | Single-user / multi-user / LAN; whether a partner/API add-on is licensed. |
| **Company files** | ✅ one is `COMP0004` (DHOWN, FY 26-27: Dr=Cr ₹26.54 cr, 835 ledgers) | Full list of company codes + which maps to `dhown_mes` vs `vdknits_mes`. |
| **Financial-year files** | ✅ `.bds` per FY (e.g. `db1<yy>.bds`) | The current + historical FY files to mirror. |

## 2. Deployment topology
| Item | Status | What we need |
|---|---|---|
| Install location | ✅ `C:\BusyWin\...\COMP####\*.bds` (MS-Access JET 4.0) | The exact path on the production/accounts PC. |
| Topology | ❓ | **Single PC / LAN server / BUSY-on-cloud** — decides where the bridge reads/writes files and whether an API is reachable. |
| Who runs BUSY | ❓ | The accounts machine's OS, uptime, and whether the MES/bridge host can reach its filesystem or a shared folder. |
| Backup regime | ❓ | BUSY's own backup schedule (so reads never race a backup/restore). |

## 3. Supported integration methods (confirm what EXISTS)
| Method | Status | Notes |
|---|---|---|
| Official public **REST API** | ✅ **does not exist** | Confirmed; the design assumes none. |
| **ACE-OLEDB read** of the `.bds` | ✅ **works, read-only, validated** | `Mode=Read`, SELECT-only; Windows-only; needs the 64-bit ACE Database Engine + the fixed Jet password. **This is the confirmed READ path.** |
| **XML Data Export/Import** (`Administration → Data Export/Import`) | ❓ (first-party, documented by BUSY; **not in Basic**) | The **primary WRITE candidate**. Need a real export sample for the schema. |
| **Excel/CSV voucher import** (`Import Voucher from Excel`) | ❓ | WRITE fallback; account names must match existing BUSY names; no import preview. |
| **Channel-partner / dev API** | ❓ | Exists only via a partner arrangement (source + API key). Is one licensed for DHOWN? Partner contact? |
| Third-party REST wrappers (BusyNotify/RootFi/etc.) | ◻ optional | Not first-party; config-dependent; only after a real proof. |
| **Direct writes to the `.bds` / internal DB** | ✅ **FORBIDDEN** | Corrupts BUSY, voids support — never done (enforced in code). |

## 4. Read capabilities (confirm scope)
| Capability | Status |
|---|---|
| Masters: groups + ledgers (`Master1`: MasterType 1=group, 2=ledger; `ParentGrp` tree) | ✅ readable |
| Party details (GSTIN/PAN/address on ledgers) | ✅ readable |
| Postings / day book (`Tran2`, `RecType=1`; `Value1<0`=Dr, `>0`=Cr) | ✅ readable |
| Trial balance / P&L / Balance sheet (derived) | ✅ validated |
| **Warehouse / material-centre master** table + fields | ❓ confirm the exact table/columns in the `.bds` |
| **Voucher reference** fields (voucher no., type, date, series) | ❓ confirm the exact columns to read a reference back |

## 5. Write / import capabilities (confirm before any write adapter)
| Item | Status | What we need |
|---|---|---|
| XML voucher-import **schema** | ❓ | A **real sample export** of each needed voucher type, from the customer's own BUSY, to reverse-engineer tags. |
| Excel voucher-import **column spec** | ❓ | The exact columns + the requirement that **account/ledger names pre-exist**. |
| Who **triggers** the import (person vs scheduled BUSY job/agent) | ❓ | Decides whether the write path is interactive or automatable. |
| How the **voucher reference returns** (export file, screen, partner API) | ❓ | Needed to store `busy_reference` and reconcile. |
| Import **validation / preview** | ✅ BUSY help indicates **no preview** | So all validation + idempotency stays in our bridge. |
| Cancellation / amendment of an imported voucher | ❓ | Whether BUSY allows it and how it surfaces. |

## 6. Authentication & security requirements
| Item | Status | What we need |
|---|---|---|
| `.bds` **Jet password** | ✅ fixed, read via `BUSY_BDS_PASSWORD` **env only** | Confirm the customer's value is stored in environment config, never source. |
| Partner-API credentials (if any) | ❓ | Key handling — stored as a network secret, never committed. |
| File-share access (for the drop-folder) | ❓ | Least-privilege account for read + the write drop-folder. |
| Network path MES↔BUSY | ❓ | LAN segment / firewall rules; keep off any public interface. |

## 7. Vendor support & licensing
| Item | Status | What we need |
|---|---|---|
| Channel partner contact | ❓ | Who sold/maintains the licence; whether they provide a dev API + docs. |
| BUSY support channel | ❓ | `support@busy.in` / partner — to confirm XML schema + edition limits in writing. |
| Licence terms for integration | ❓ | Any licence/add-on needed for XML import/export or a dev API. |

---

## 8. Vendor/management questionnaire (hand this over)
1. BUSY **edition, version, licence type** and seat count?
2. Is **XML Data Export/Import** available on this licence (not Basic)? If not, is **Excel voucher import** or a **partner dev API** available?
3. Deployment: single PC / LAN / cloud? Where are the `.bds` files and can the MES host reach that filesystem or a shared folder?
4. Provide a **sample XML export** of a purchase, a receipt and a sales/dispatch voucher from the real company.
5. Who performs the BUSY-side import, and how is the **voucher number** surfaced back?
6. Confirm the **warehouse/material-centre** master table + how centres are coded.
7. Channel-partner contact + whether a **dev/API** is licensed.
8. Any licence/add-on cost for the chosen integration method?

**Nothing proceeds to a real adapter until §1–§7 are answered and the §8 samples are provided.**
