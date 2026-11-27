#!/usr/bin/env node
/*
 * db-provision.js — repeatable, headless clean-DB provisioning (remediation tooling).
 *
 * Purpose: stand up the MES schema on an EMPTY database deterministically, so
 * CI and e2e can run from zero. It reproduces the order that server.js performs
 * at boot (which is otherwise the only place provisioning happens), PLUS the
 * legacy root migration_*.js and an optional recovered baseline.
 *
 * SAFETY: refuses to run against known production DB names. Intended for scratch
 * DBs only. Never contacts the live system.
 *
 * Usage:  DB_NAME=dhown_scratch node scripts/db-provision.js
 *
 * NOTE (remediation finding): the oldest core tables (machines, rolls, operators,
 * machine_status_log, machine_downtime, rfid_events, …) have NO CREATE TABLE in
 * source — they can only be recreated from an authoritative schema dump placed at
 * backend/schema/00_baseline_schema.sql (produce it with:
 *   pg_dump --schema-only --no-owner --no-privileges -d <staging_db> > 00_baseline_schema.sql
 * on a NON-production copy). Until that file exists, provisioning is PARTIAL and
 * steps that depend on the missing core tables will report as SKIPPED/FAILED.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const DB = process.env.DB_NAME;
if (!DB) { console.error('Set DB_NAME to a scratch database.'); process.exit(1); }
if (['dhown_mes', 'vdknits_mes'].includes(DB)) {
  console.error(`REFUSING to provision production DB "${DB}".`); process.exit(1);
}
const BACKEND = path.join(__dirname, '..');
const log = [];
const mark = (step, status, detail = '') => { log.push({ step, status, detail }); console.log(`  [${status}] ${step}${detail ? ' — ' + detail : ''}`); };

// Boot-order ensure functions, copied from server.js (956–999).
const ENSURE_ORDER = [
  'ensureProductionHistory','ensureUsersSchema','ensureMaintenanceSchema','ensureOperatorsSchema',
  'ensurePurchaseOrdersSchema','ensureSalesOrdersSchema','ensureProductionPlansSchema','ensurePayrollSchema',
  'ensureTaxInvoicesSchema','ensureAlertAcksSchema','ensureCollectorRollSchema','ensureWaCrmSchema',
  'ensureLogisticsSchema','ensureAllocationSchema','ensureUomSchema','ensureFinancialViews',
  'ensureReferenceData','ensureKnittingSchema','ensureFinancialConstraints','ensureBankReconSchema',
  'ensureSoftDelete','ensureComplaintsSchema','ensureOrderLineWeights','ensureFinishedGoodsSchema','ensureBusyProductionSchema',
  'ensureFabricInspectionSchema','ensureAiAgentsSchema','ensureAiApprovalsSchema','ensureCapaSchema',
  'ensureShadeSwatchesSchema','ensureTimestamps','ensureCheckConstraints','ensureForeignKeyIndexes',
];

// Legacy root migrations, dependency-first (ERP masters before the rest).
const LEGACY_FIRST = ['migration_erp_phase0a.js','migration_erp_phase0b.js','migration_erp_phase0c.js','migration_erp_phase0def.js','migration_erp_phase1.js'];

(async () => {
  console.log(`\n=== db-provision on "${DB}" ===\n`);

  // 0) Optional recovered baseline schema (the missing core DDL).
  const baseline = path.join(BACKEND, 'schema', '00_baseline_schema.sql');
  if (fs.existsSync(baseline)) {
    try {
      execSync(`psql -h ${process.env.DB_HOST||'127.0.0.1'} -p ${process.env.DB_PORT||5432} -U ${process.env.DB_USER||'postgres'} -d ${DB} -v ON_ERROR_STOP=1 -f ${baseline}`,
        { stdio: 'pipe', env: { ...process.env, PGPASSWORD: process.env.DB_PASSWORD || '' } });
      mark('00_baseline_schema.sql', 'OK');
    } catch (e) { mark('00_baseline_schema.sql', 'FAIL', String(e.stderr || e.message).slice(0, 120)); }
  } else {
    mark('00_baseline_schema.sql', 'MISSING', 'recover core DDL via pg_dump --schema-only (see header)');
  }

  // 1) Legacy ERP migrations (dependency-first, then the rest alphabetically).
  const allLegacy = fs.readdirSync(BACKEND).filter(f => /^migration_.*\.js$/.test(f));
  const rest = allLegacy.filter(f => !LEGACY_FIRST.includes(f)).sort();
  for (const f of [...LEGACY_FIRST.filter(f => allLegacy.includes(f)), ...rest]) {
    try {
      execSync(`node ${path.join(BACKEND, f)}`, { stdio: 'pipe', env: { ...process.env, DB_NAME: DB } });
      mark(f, 'OK');
    } catch (e) { mark(f, 'FAIL', String(e.stdout || e.stderr || e.message).split('\n').filter(Boolean).pop()?.slice(0, 100)); }
  }

  // 2) schema.js ensures, in server.js boot order.
  const schema = require(path.join(BACKEND, 'src', 'db', 'schema'));
  for (const name of ENSURE_ORDER) {
    const fn = schema[name];
    if (typeof fn !== 'function') { mark(name, 'ABSENT'); continue; }
    try { await fn(); mark(name, 'OK'); }
    catch (e) { mark(name, 'FAIL', String(e.message).slice(0, 100)); }
  }

  // 3) runner migrations + acct/import-schema ensures + admin seed.
  const pool = require(path.join(BACKEND, 'config', 'database'));
  try { await require(path.join(BACKEND, 'src', 'db', 'migrate')).run({ by: 'provision' }); mark('migrate.run', 'OK'); }
  catch (e) { mark('migrate.run', 'FAIL', String(e.message).slice(0, 100)); }
  try { await require(path.join(BACKEND, 'src', 'lib', 'import-schema'))(pool).ensure(); mark('import-schema.ensure', 'OK'); }
  catch (e) { mark('import-schema.ensure', 'FAIL', String(e.message).slice(0, 100)); }
  try { await require(path.join(BACKEND, 'src', 'lib', 'accounting', 'schema')).ensureAccountingSchema(pool); mark('acct.ensure', 'OK'); }
  catch (e) { mark('acct.ensure', 'FAIL', String(e.message).slice(0, 100)); }
  // Seed the default admin (same step server.js runs at boot) so the DB has a
  // usable SUPER_ADMIN login. Password from ADMIN_DEFAULT_PASSWORD, else random.
  try { await require(path.join(BACKEND, 'src', 'db', 'schema')).seedDefaultAdmin(); mark('seedDefaultAdmin', 'OK'); }
  catch (e) { mark('seedDefaultAdmin', 'FAIL', String(e.message).slice(0, 100)); }

  // Additional boot-time provisioners that server.js runs after the ensures, so
  // the clean DB matches a booted app instead of relying on startup side effects.
  // wa-approvals.seedDefaults seeds the documented default approval matrix.
  const lib = (...p) => require(path.join(BACKEND, 'src', 'lib', ...p));
  const bootSteps = [
    ['audit.ensure',            () => lib('audit')(pool).ensure()],
    ['busy-bridge.ensure',      () => lib('busy-bridge')(pool).ensure()],
    ['wa-campaigns.ensure',     () => lib('wa-campaigns')({ pool, sendTemplate: async () => ({}), consent: {} }).ensure()],
    ['error-tracker.ensure',    () => lib('error-tracker')(pool).ensure()],
    ['ci.ensure',               () => lib('ci')(pool).ensure()],
    ['loans.ensure',            () => lib('loans')(pool, { nextSeq: async () => 'X' }).ensure()],
    ['budgets.ensure',          () => lib('budgets')(pool).ensure()],
    ['cashflow.ensure',         () => lib('cashflow')(pool).ensure()],
    ['profitability.ensure',    () => lib('profitability')(pool).ensure()],
    ['shade-approvals.ensure',  () => lib('shade-approvals')(pool).ensure()],
    ['morning-briefing.ensure', () => lib('morning-briefing')(pool).ensure()],
    ['busy-integration.ensure', () => lib('busy')(pool).ensure()],
    ['token-revocation.init',   () => lib('token-revocation').init(pool)],
    ['wa-approvals.seedDefaults',() => lib('wa-approvals')(pool).seedDefaults()],
  ];
  for (const [name, fn] of bootSteps) {
    try { await fn(); mark(name, 'OK'); } catch (e) { mark(name, 'FAIL', String(e.message).slice(0, 100)); }
  }

  // Summary.
  const r = await pool.query(`SELECT count(*)::int n FROM information_schema.tables WHERE table_schema='public'`);
  const acctR = await pool.query(`SELECT count(*)::int n FROM information_schema.tables WHERE table_schema='acct'`).catch(() => ({ rows: [{ n: 0 }] }));
  const ok = log.filter(l => l.status === 'OK').length, fail = log.filter(l => l.status === 'FAIL').length;
  console.log(`\n=== SUMMARY: ${ok} OK, ${fail} FAIL · public tables=${r.rows[0].n}, acct tables=${acctR.rows[0].n} ===`);
  await pool.end();
  process.exit(fail > 0 ? 2 : 0);
})().catch(e => { console.error('provision crashed:', e.message); process.exit(3); });
