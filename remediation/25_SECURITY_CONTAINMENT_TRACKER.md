# 25 — Security Containment Execution Tracker

**Date opened:** 2026-11-27 · **Branch:** `claude/mes-busy-remediation` · **HEAD:** `08a84ff`
**Source of findings:** `remediation/24_SECURITY_INCIDENT_CLOSURE_PLAN.md` (findings preserved, not restated in full).

> **This is a tracking document only.** No security action has been performed by this assistant. No secrets, password hashes or personal data are accessed or displayed. No repository, repository setting, Git history, credential, password, deployment or application code is modified by this task.
> **All actions below are for the named human owners.** This assistant only records and verifies evidence of completion.

**Status vocabulary:** `NOT STARTED` · `IN PROGRESS` · `BLOCKED` · `PENDING VERIFICATION` · `VERIFIED CLOSED`.
**How to use:** the owner performs the action, records the evidence reference, sets the status and fills the completion date. An action is `VERIFIED CLOSED` only when its stated verification evidence exists.

---

## 0. Completed code fixes vs outstanding human actions
| | Item | Where | Status |
|---|---|---|---|
| ✅ **Code fix — done** | JWT fail-closed (no fallback secret; refuses missing/former-public value) + regression test | `backend/src/middleware/auth.js`, `backend/test/jwt-fail-closed.test.js`, commit `dc0740e` | **VERIFIED CLOSED (code)** |
| ✅ **Code hygiene — done** | `.env` git-ignored & untracked; keys read from `process.env.*`; no key literal in tracked files | current tree @ `08a84ff` | **VERIFIED CLOSED (code)** |
| ⬜ **Human actions — outstanding** | Items 1–8 below (key rotation, repo privacy, password reset, prod JWT rotation, history purge, fork inventory, privacy review, final verification) | GitHub / Groq console / production env | **NOT STARTED** |

**Nothing in items 1–8 is code; none can be completed by this assistant.** The code column above is the only part that is already closed.

---

## 1. Groq API key — revocation & replacement
| Field | Detail |
|---|---|
| Owner | IT / key holder |
| Approval | Management |
| Exact action | In the Groq console, **revoke** the exposed key and **issue a new one**; set the new value only in environment/secret config (never in source). |
| Dependencies | None — do this first; independent of history cleanup. Exposed material: `backend/.env` (per report 24). |
| Verification evidence | Console view/log showing old key **revoked** and a new key **active**; app reads `process.env.GROQ_API_KEY` (new value **not** recorded here). |
| Status | `NOT STARTED` |
| Completion date | ____ |

## 2. Make both exposed repositories private
| Field | Detail |
|---|---|
| Owner | Repo owner (Nakuld9) |
| Approval | Management |
| Exact action | Set **`Nakuld9/DHOWN_LIVE_PRODUCTION_DASHBOARD`** and **`Nakuld9/dhown_mes_remidiated-`** to **Private** (or confirm the intended visibility). |
| Dependencies | None — immediate blast-radius reduction. (Both confirmed PUBLIC in report 24.) |
| Verification evidence | GitHub settings showing both repos **Private**; anonymous access returns 404. |
| Status | `NOT STARTED` |
| Completion date | ____ |

## 3. Password reset & account-protection response
| Field | Detail |
|---|---|
| Owner | Application / DB admin |
| Approval | Management |
| Exact action | **Force a password reset for all users** (production DB `users`); review for any additional account protections (e.g. lockout, admin re-verification). |
| Dependencies | Driven by SEC-7 exposure (bcrypt hashes public). Independent of history purge — do not wait for cleanup. |
| Verification evidence | Reset executed (admin log / count of users reset); confirmation users must set new passwords. **No hash or credential recorded here.** |
| Status | `NOT STARTED` |
| Completion date | ____ |

## 4. Production `JWT_SECRET` rotation & old-token invalidation
| Field | Detail |
|---|---|
| Owner | IT / deploy owner |
| Approval | Management |
| Exact action | Set a **new random `JWT_SECRET`** in production env (must **not** be the former built-in value); restart the app so old tokens are rejected; plan the re-login window (8-hour natural drain or force immediately). |
| Dependencies | Code already fail-closed (`dc0740e`) — this is the **operational** rotation only. |
| Verification evidence | Prod env shows a new secret (value **not** recorded); boot log clean; a token signed with the old secret is **rejected**; users can re-login. |
| Status | `NOT STARTED` |
| Completion date | ____ |

## 5. Coordinated Git history cleanup (both repos, all affected branches)
| Field | Detail |
|---|---|
| Owner | Repo owner / Git admin |
| Approval | Management (coordinated with all collaborators) |
| Exact action | Notify collaborators first; then remove exposed paths from **all reachable history** and force-update: **`backend/.env`** on original `server-refractor` (`8f257f3`) + original & remediation `claude/dhown-busy-bridge-5whntb` (`b379c25`); **`backend/backups/*.sql`** on original `server-refractor`. Delete retired branches and/or purge paths with `git filter-repo`/BFG. Instruct everyone to delete old clones and **re-clone**. |
| Dependencies | **Do after items 1–4** (rotation/reset first, since cleanup cannot undo past exposure). Branch/commit map from report 24. |
| Verification evidence | Each exposed path **404s** on github.com for every affected branch in **both** repos; collaborators confirmed re-cloned. |
| Status | `NOT STARTED` |
| Completion date | ____ |

## 6. Fork & clone inventory
| Field | Detail |
|---|---|
| Owner | Repo owner |
| Approval | Management |
| Exact action | Enumerate forks (GitHub → **Insights → Forks**) and known local clones for **both** repos; for any fork still exposing the material, request deletion or coordinate cleanup. |
| Dependencies | Informs item 5 scope; residual risk if forks exist (a rewrite does not touch forks). |
| Verification evidence | Fork list reviewed (count + disposition recorded); no fork continues to expose `backend/.env` or `backups/*.sql`. |
| Status | `NOT STARTED` |
| Completion date | ____ |

## 7. Privacy & incident-response review
| Field | Detail |
|---|---|
| Owner | Management / data owner |
| Approval | Management |
| Exact action | Record the exposure timeline (public since **2026-07-06**); assess **partner PII** (GSTIN/PAN/bank/email) and password-hash exposure against DPDP/privacy obligations; determine any notification duties; log the incident. |
| Dependencies | Draws on SEC-7 findings in report 24. **Do not reproduce any personal data** in the review record beyond what policy requires. |
| Verification evidence | Written incident record + privacy assessment on file; notification decision documented. |
| Status | `NOT STARTED` |
| Completion date | ____ |

## 8. Final verification & closure evidence
| Field | Detail |
|---|---|
| Owner | Management (with IT) |
| Approval | Management |
| Exact action | Confirm every item 1–7 has its stated evidence; mark each incident in report 24 as `VERIFIED CLOSED` only then. |
| Dependencies | All of items 1–7. |
| Verification evidence | Consolidated checklist: key rotated · both repos Private · passwords reset · JWT rotated+verified · all paths 404 on every branch/fork · fork inventory done · privacy review recorded. |
| Status | `NOT STARTED` |
| Completion date | ____ |

---

## Incident closure roll-up (mirrors report 24 — update as evidence lands)
| Incident | Blocking items | Current status |
|---|---|---|
| **SEC-1 — Groq key** | 1, 2, 5, 6 | `OPEN` (exposed material still public; rotation pending) |
| **SEC-7 — Prod DB dumps (hashes + PII)** | 2, 3, 5, 6, 7 | `OPEN` (still public in original `server-refractor`) |
| **JWT — fallback secret** | code ✅ done; operational 4 | code `VERIFIED CLOSED`; prod rotation `PENDING HUMAN ACTION` |

## Recommended execution order
1 (Groq rotate) → 2 (repos Private) → 3 (password reset) → 4 (JWT rotate+verify) → 5 (history purge) → 6 (fork inventory) → 7 (privacy review) → 8 (final verification).

## Safety restrictions observed by this task
Preparation of this tracker only. This assistant did **not**: rotate/revoke credentials · reset passwords · change repository visibility · modify repositories or settings · rewrite Git history · force-push · delete files/branches · modify the original repository · deploy · access production/databases · modify application code · access or display secrets/hashes/PII. All actions above are owned by the named humans, pending management review.
