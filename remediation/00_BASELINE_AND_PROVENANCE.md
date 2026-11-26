# 00 — Baseline & Provenance (Deliverable B)

**Project:** DHOWN MES ↔ BUSY 21 Remediation
**Repo:** `Nakuld9/dhown_mes_remidiated-` (⚠️ rename to `DHOWN_MES_REMEDIATED`; ⚠️ set visibility **Private**)
**This branch:** `claude/mes-busy-remediation`
**Date:** 2026-11-26

---

## Source of truth (original — MUST REMAIN UNTOUCHED)

| | Value |
|---|---|
| Original repo | `Nakuld9/DHOWN_LIVE_PRODUCTION_DASHBOARD` (public) |
| Original `main` HEAD | `a8ef1bb601b705d03fc8a84ea24e033a17b2389` (2026-11-14) |
| Access used | **Read-only clone only.** No push, no branch, no change to the original. |

## Baseline (approved 2026-11-26)

- **Baseline commit:** `a8ef1bb` (branch `main` of the original).
- **Remediation working branch:** `claude/mes-busy-remediation`, cut from `a8ef1bb`.

## Copied branches (faithful mirror) — SHA-verified identical

| Branch | Original SHA | Copy SHA | Result |
|---|---|---|---|
| `main` | `a8ef1bb` | `a8ef1bb` | ✅ byte-identical |
| `claude/dhown-busy-bridge-5whntb` | `b379c25` | `b379c25` | ✅ byte-identical |

Identical SHAs ⇒ identical git objects ⇒ provably faithful copy.

## Excluded branch (deliberate)

| Branch | SHA | Date | Reason for exclusion |
|---|---|---|---|
| `server-refractor` | `8f257f3` | 2026-07-09 | (1) **Exposed secret** — a live **Groq API key** committed in `backend/.env` (commit `dec5183`); GitHub push-protection blocked it. (2) **Stale** — `PROJECT_STATE.md` records it was merged into `main` on 2026-08-03; nothing unique to carry forward. |

> 🔴 **Action required (independent of this repo):** the Groq key is in the **public** original repo's history — **rotate/revoke it now.** See `07_SECURITY_FINDINGS.md`.

## Carry-forward (approved)

Only the **BUSY-bridge schema *design*** from `claude/dhown-busy-bridge @ b379c25`
(`migration_phase11_busy_bridge.sql`: `busy_master_mapping`, `busy_sync_queue`,
`busy_audit_log`, `busy_reconciliation`, `busy_connection_state`) — to be
**re-implemented fresh** in `main`'s architecture **after** checking its
migrations, dependencies and compatibility. No code merge from that branch.

## Governing conditions (locked for this engagement)

1. Keep all existing accounting modules in place for now — **do not delete or disable**.
2. BUSY 21 becomes the **sole accounting authority only after** integration + migration are verified.
3. Preserve existing MES production workflows.
4. Preserve approved workflows: purchase, material receipt, warehouse/material-centre, machine issue, shift production, party issue, party recovery, dispatch.
5. Purchase & material receipt → **bidirectional** MES↔BUSY integration.
6. Machine issue & shift production → **internal MES**.
7. Party issue, party recovery, dispatch → **MES → BUSY**.
8. Use vendor BUSY **API or DOC Bridge**; final connector chosen by technical verification.
9. **Never write directly into BUSY's internal database.**
10. **Do not modify or deploy to the original live MES.**

## Finding-classification scheme (applied across all deliverables)

Every finding is tagged one of:
`CONFIRMED-DEFECT` · `HISTORICAL` · `POTENTIAL-RISK` · `UNUSED-CODE-CANDIDATE` · `NEEDS-BUSINESS-CONFIRMATION`.

No large-scale deletion or accounting replacement begins until these Phase-1
deliverables are reviewed and approved.
