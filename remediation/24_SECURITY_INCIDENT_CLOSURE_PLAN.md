# 24 — Security Incident Closure Plan (SEC-1, SEC-7, JWT)

**Date:** 2026-11-27 · **Branch:** `claude/mes-busy-remediation` · **HEAD:** `59046f6` · **Working tree:** clean.
**This is an investigation and preparation document only.** No credentials rotated, no repository visibility changed, no Git history rewritten, no force-push, no deletion, no deployment, no production access. No BUSY connection; integration flags remain OFF.

> **No secrets, database records, password hashes or partner personal information are reproduced in this document.** Only file paths, commit identifiers, dates and repository metadata are recorded as evidence.

**Status vocabulary:** `OPEN` · `PENDING HUMAN ACTION` · `PENDING VERIFICATION` · `VERIFIED CLOSED`.
**Evidence labels:** `[FACT]` verified this session · `[REPORTED]` from an earlier committed report · `[UNVERIFIED]` requires evidence not obtainable from here.

---

## 1. Executive summary
- `[FACT]` **Two repositories are PUBLIC** (list_repos, 2026-11-27): the original `Nakuld9/DHOWN_LIVE_PRODUCTION_DASHBOARD` and the remediation `Nakuld9/dhown_mes_remidiated-`. `Nakuld9/dhown-mes` is private.
- `[FACT] 🔴 NEW — SEC-1 is also live in the remediation repo.` `backend/.env` is reachable in **this** public repo via the mirrored branch `claude/dhown-busy-bridge-5whntb` (tip `b379c25`). Previously SEC-1 was tracked only against the original. **Both** repositories must be cleaned.
- `[FACT]` **SEC-1 (Groq key)** — `backend/.env` reachable on: original `server-refractor` (`8f257f3`), original `claude/dhown-busy-bridge-5whntb` (`b379c25`), and remediation `claude/dhown-busy-bridge-5whntb` (`b379c25`). First added `a967156` (2026-07-06), also in `dec5183`. **Status: OPEN.**
- `[FACT]` **SEC-7 (prod DB dumps)** — four `backend/backups/*.sql` reachable on original `server-refractor` (`8f257f3`), introduced `dec5183` (2026-07-06). **Not present** in the remediation repo. **Status: OPEN.**
- `[FACT]` **JWT fail-closed code** — present and tested (`auth.js`, commit `dc0740e`, test `jwt-fail-closed.test.js`). **Status (code): VERIFIED CLOSED.** Production secret **rotation** is a human action with no evidence — **PENDING HUMAN ACTION / PENDING VERIFICATION.**
- `[FACT]` **Current working tree is clean**: `.env` is git-ignored and untracked; Groq/OpenAI keys are read from `process.env.*`; no key-like literal exists in any tracked file; no report reproduces a secret.
- **No incident can be marked closed:** exposed material remains publicly reachable and all human containment/rotation actions are unverified.

## 2. SEC-1 — Exposed Groq API key
### Evidence `[FACT]`
| Item | Finding |
|---|---|
| Exposed artefact | `backend/.env` (contains a Groq API key — value not inspected/printed) `[REPORTED]` for the key's nature |
| Introducing commit | `a967156` "Initial commit…" (2026-07-06); also present in `dec5183` |
| Reachable in **original** (PUBLIC) | branches `server-refractor` (`8f257f3`) and `claude/dhown-busy-bridge-5whntb` (`b379c25`) |
| Reachable in **remediation** (PUBLIC) | branch `claude/dhown-busy-bridge-5whntb` (`b379c25`) — **NEW** |
| Not reachable from | `main` (`a8ef1bb`) in either repo; remediation `claude/mes-busy-remediation` (`59046f6`) |
| Current config hygiene | `.gitignore` covers `backend/.env`/`.env`/`.env.*`; `.env` untracked; keys via `process.env.GROQ_API_KEY`; no hardcoded key literal in tracked code |
| Key rotated/revoked? | `[UNVERIFIED]` — no evidence |
| Logs/reports expose key? | `[FACT]` no — no key-like literal in any tracked file including `remediation/` |

### Containment checklist (human — do not execute here)
- [ ] Make **both** public repos **Private** (or confirm the intended visibility).
- [ ] Treat the key as **compromised** (public since 2026-07-06): proceed to rotation regardless of cleanup.

### Rotation & verification checklist (human)
- [ ] **Revoke/rotate** the Groq key in the Groq console; issue a new key.
- [ ] Store the new key only in environment/secret config (never in source).
- [ ] Verify the application reads the new key from `process.env.GROQ_API_KEY`.
- [ ] Evidence: screenshot/log of the old key revoked + new key active (value not recorded here).

### Git-history cleanup plan (human — coordinated, not performed here)
- [ ] Inventory every clone/fork (GitHub → **Insights → Forks**, and any local clones).
- [ ] Remove `backend/.env` from **all reachable history** in **both** repos — delete the stale `server-refractor` and `claude/dhown-busy-bridge-5whntb` branches if retired, and/or purge the path with `git filter-repo`/BFG, then force-update with collaborator coordination.
- [ ] After cleanup, verify the raw path **404s** on github.com for every affected branch.

### Evidence required for closure
Repos Private (or intended state) · key revoked + rotated · path 404 on all branches/forks · fork/clone inventory reviewed.

## 3. SEC-7 — Production database dumps in Git history
### Evidence `[FACT]` / `[REPORTED]`
| Item | Finding |
|---|---|
| Exposed artefacts | `backend/backups/dhown_mes_2026-07-01.sql`, `-07-02`, `-07-03`, `-07-05` (full `pg_dump` **with data**) |
| Introducing commit | `dec5183` "Phase 1 backend architecture setup" (2026-07-06) |
| Reachable in **original** (PUBLIC) | branch `server-refractor` (`8f257f3`) |
| Present in remediation repo? | `[FACT]` **No** — 0 on all three remediation branches |
| Sensitive content | `[REPORTED]` dumps include `users.password_hash` (bcrypt) and partner PII (GSTIN/PAN/bank/email). **Not reproduced here.** |
| Other branches/tags | `[FACT]` original has **no tags**; dumps not on `main` or the bridge branch — only `server-refractor` |
| Clones/forks | `[UNVERIFIED]` — cannot enumerate forks from here; must be checked in GitHub Insights |

### Controlled remediation plan (human — do not execute here)
- **Repository visibility:** make the original **Private** (or confirm intended state).
- **Coordinated history rewrite:** notify collaborators first; then delete the stale `server-refractor` branch and/or purge `backend/backups/` via `git filter-repo`/BFG; force-update under coordination (not performed by this task).
- **Removal verification:** confirm each `*.sql` path **404s** on all branches after cleanup.
- **Collaborator notification & clean clones:** instruct everyone to delete old clones and re-clone the rewritten repo (old clones retain the data).
- **Credential rotation (exposure-based):** rotate any secret that appeared inside the dump data (e.g. values stored in `app_settings`) in addition to SEC-1.
- **Account protection:** **force a password reset for all users** (bcrypt hashes are offline-crackable once public).
- **Privacy / incident-response review:** record the partner-PII exposure for DPDP/privacy obligations; assess notification duties; log the incident timeline.

### Evidence required for closure
Repo Private (or intended) · all `*.sql` paths 404 on every branch/fork · password reset executed · exposed in-data secrets rotated · privacy review recorded.

## 4. JWT — Production fallback secret exposure
### Evidence `[FACT]`
| Item | Finding |
|---|---|
| Code location | `backend/src/middleware/auth.js` |
| Behaviour | `JWT_SECRET = process.env.JWT_SECRET`; **throws "Refusing to start"** if unset/empty; **throws** if set to the former built-in value (kept only as a denylist entry to reject it) |
| Other fallbacks | `[FACT]` none — no hardcoded/`||`-fallback JWT secret in `backend/src` |
| Tests | `backend/test/jwt-fail-closed.test.js` present |
| Fix commit | `dc0740e` (2026-11-26) |
| Rejects missing/invalid secret? | `[FACT]` **Yes** (missing/empty → refuse; former public value → refuse) |

> The former built-in value is already public; retaining it in code **solely to reject it** is correct and is **not** a new exposure. It is not reproduced here.

### Closure checklist
- **Code remediation — `VERIFIED CLOSED`** (fail-closed + test, `dc0740e`).
- Separately tracked **human actions** (not performed here):
  - [ ] **Rotate the production `JWT_SECRET`** to a new random value (must not be the former built-in value).
  - [ ] Store it in secure environment config only.
  - [ ] **Token/session impact:** rotation invalidates all existing tokens — plan a re-login window (8-hour expiry means natural drain, or force immediately).
  - [ ] **Deployment verification:** confirm the app boots with the new secret and rejects tokens signed with the old one.
- Evidence: prod env shows a new secret (value not recorded) · boot log clean · old tokens rejected.

## 5. Verified facts vs unverified human actions
| Verified this session `[FACT]` | Unverified / human action |
|---|---|
| Both named repos PUBLIC; third private | Whether/when repos will be made Private |
| Exact branches/commits/paths for SEC-1 & SEC-7 | Whether history has been/will be purged |
| SEC-1 reachable in remediation repo via bridge branch | Fork/clone inventory and exposure |
| Current tree clean (.env ignored, env-based keys, no literals) | Groq key rotation/revocation |
| JWT fail-closed code + test present (`dc0740e`) | Prod JWT secret rotation + deploy verification |
| Dumps include hashes+PII (reported, not reproduced) | User password reset; privacy/DPDP review |

## 6. Prioritised remediation sequence (recommended)
1. **Rotate/revoke the Groq key now** (SEC-1) — independent of cleanup; assume compromised.
2. **Make both public repos Private** (SEC-1 + SEC-7) — immediate blast-radius reduction.
3. **Force user password reset** (SEC-7) — hashes are public.
4. **Rotate production `JWT_SECRET`** + verify deploy (JWT).
5. **Coordinated history purge** of `backend/.env` (both repos) and `backend/backups/` (original), with collaborator notification and clean re-clones; verify 404s.
6. **Fork/clone inventory** and **privacy/incident-response review**; record closure evidence.

## 7. Required owners and approvals
| Action | Owner | Approver |
|---|---|---|
| Groq key rotation | IT / key holder | Management |
| Repo visibility change | Repo owner (Nakuld9) | Management |
| History rewrite + force-update | Repo owner / Git admin | Management (coordinated) |
| User password reset | Application/DB admin | Management |
| JWT secret rotation + deploy | IT / deploy owner | Management |
| Privacy/DPDP review | Management / data owner | Management |

## 8. Evidence required to mark each incident closed
- **SEC-1 → VERIFIED CLOSED when:** key revoked+rotated (console evidence) **and** `backend/.env` 404s on all branches/forks of **both** repos **and** repos at intended visibility.
- **SEC-7 → VERIFIED CLOSED when:** all four `*.sql` 404 on every branch/fork **and** password reset done **and** in-data secrets rotated **and** privacy review recorded.
- **JWT → VERIFIED CLOSED when:** (code already closed) prod secret rotated to a new value **and** deploy verified (boots + old tokens rejected).

## 9. Residual risks
- **Public exposure window is long** (since 2026-07-06): the Groq key, password hashes and partner PII may already be scraped, cached, or forked — **cleanup cannot undo past access**; rotation/reset is the real mitigation.
- **Forks/clones** of a public repo retain history after a rewrite — unverifiable from here.
- **GitHub/search caches** may serve old content briefly after a purge.
- **Bridge branch in the remediation repo** keeps SEC-1 live even though the baseline branch is clean — easy to overlook.
- **Password hashes offline-crackable** — weak passwords are at risk until reset.

## 10. Explicit production safety restrictions (observed by this task)
This task performed **investigation only**. It did **not**, and this plan does not authorise this assistant to: rotate/revoke credentials · modify production configuration · change repository visibility · rewrite Git history · force-push · delete files or branches · modify the original repository · deploy · access production databases · connect to BUSY · activate integration flags · implement Phase 3. All remediation actions above are for the named human owners, pending management review.

---
*Evidence gathered read-only (list_repos + blobless Git fetches of public branches; no blob contents, secrets, hashes or PII retrieved or reproduced). Awaiting management review; no remediation action taken.*
