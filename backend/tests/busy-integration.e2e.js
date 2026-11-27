// BUSY integration bridge (Phase 2) — mock-first integration tests.
//
// Exercises the bridge against the MockBusyConnector on a scratch DB: idempotency
// & duplicate prevention, retries/interrupted sync, partial failures, mapping
// mismatches, concurrent & replayed events, invalid warehouse references, and
// party-wise outstanding. The mock proves the BRIDGE is correct — NOT real BUSY
// compatibility.
//
//   DB_NAME=<scratch> node tests/busy-integration.e2e.js

require('dotenv').config({ quiet: true });
const { Pool } = require('pg');
const DB = process.env.DB_NAME || 'dhown_mes_staging';
if (['dhown_mes', 'vdknits_mes'].includes(DB)) { console.error(`Refusing to run on production DB "${DB}"`); process.exit(1); }
const pool = new Pool({ host: process.env.DB_HOST || 'localhost', user: process.env.DB_USER, password: process.env.DB_PASSWORD, database: DB, port: process.env.DB_PORT || 5432 });

const makeBridge = require('../src/lib/busy');
const makeMock = require('../src/lib/busy/adapters/mock');

let fails = 0;
const ok = (c, m, extra = '') => { console.log((c ? '  PASS  ' : '  FAIL  ') + m + (extra ? '   ' + extra : '')); if (!c) fails++; };
const bridgeWith = (behavior = {}) => makeBridge(pool, { connector: makeMock(pool, { behavior }) });

(async () => {
  try {
    await makeBridge(pool, { connector: makeMock(pool) }).ensure();
    // Clean slate for repeatable runs on a shared scratch DB.
    await pool.query('TRUNCATE busy_sync_queue, busy_audit_log, busy_reconciliation, busy_master_mapping RESTART IDENTITY');

    // ── 1. Idempotent enqueue / duplicate documents ────────────────
    console.log('\nDuplicate prevention');
    const b = bridgeWith();
    const e1 = await b.enqueue({ entity_type: 'TRANSACTION', dhown_entity_id: 'DISP-1', operation: 'DISPATCH', payload: { qty: 10 } });
    const e2 = await b.enqueue({ entity_type: 'TRANSACTION', dhown_entity_id: 'DISP-1', operation: 'DISPATCH', payload: { qty: 10 } });
    ok(e1.queued === true && e2.queued === false && e2.duplicate === true, 'the same document enqueues once, the duplicate is a no-op');
    const cnt = (await pool.query(`SELECT COUNT(*)::int n FROM busy_sync_queue WHERE external_reference=$1`, [e1.external_reference])).rows[0].n;
    ok(cnt === 1, 'exactly one queue row for the external_reference', `rows=${cnt}`);

    // ── 2. Concurrent enqueue of the same event ────────────────────
    console.log('\nConcurrent events');
    const conc = await Promise.allSettled(Array.from({ length: 5 }, () => b.enqueue({ entity_type: 'TRANSACTION', dhown_entity_id: 'DISP-CC', operation: 'DISPATCH', payload: { qty: 1 } })));
    ok(conc.every(r => r.status === 'fulfilled'), 'five concurrent enqueues all resolve');
    const ccRows = (await pool.query(`SELECT COUNT(*)::int n FROM busy_sync_queue WHERE dhown_entity_id='DISP-CC'`)).rows[0].n;
    ok(ccRows === 1, 'concurrent enqueues still produce exactly one row', `rows=${ccRows}`);

    // ── 3. Successful push + reference stored + replay ─────────────
    console.log('\nPush, reference, replay');
    const p1 = await b.processDue();
    const refRow = (await pool.query(`SELECT status, busy_reference FROM busy_sync_queue WHERE external_reference=$1`, [e1.external_reference])).rows[0];
    ok(refRow.status === 'SUCCESS' && !!refRow.busy_reference, 'a pushed document becomes SUCCESS with a stored BUSY reference', refRow.busy_reference);
    const replay = await b.queue.process((await pool.query(`SELECT id FROM busy_sync_queue WHERE external_reference=$1`, [e1.external_reference])).rows[0].id);
    ok(replay.replay === true && replay.status === 'SUCCESS', 'reprocessing a SUCCESS row is an idempotent no-op (no second push)');

    // ── 4. Concurrent process of one row ───────────────────────────
    const r2 = await b.enqueue({ entity_type: 'TRANSACTION', dhown_entity_id: 'DISP-RACE', operation: 'DISPATCH', payload: {} });
    const id2 = r2.row.id;
    const races = await Promise.allSettled([b.queue.process(id2), b.queue.process(id2), b.queue.process(id2)]);
    ok(races.every(r => r.status === 'fulfilled'), 'three concurrent processes of one row all resolve');
    const pushed = (await pool.query(`SELECT COUNT(*)::int n FROM busy_audit_log WHERE external_reference=$1 AND final_status='SUCCESS'`, [r2.external_reference])).rows[0].n;
    ok(pushed === 1, 'concurrent processing pushes exactly once (one SUCCESS audit row)', `success_audits=${pushed}`);

    // ── 5. Retries / interrupted sync (transient then success) ─────
    console.log('\nRetry & recovery');
    const flakyRef = 'MES:TRANSACTION:DISP-FLAKY:DISPATCH';
    const bf = bridgeWith({ flakyRefs: { [flakyRef]: 2 } });   // fail twice, then succeed
    const fe = await bf.enqueue({ entity_type: 'TRANSACTION', dhown_entity_id: 'DISP-FLAKY', operation: 'DISPATCH', payload: {} });
    let st = (await bf.queue.process(fe.row.id)).status;
    ok(st === 'RETRY', 'first transient failure → RETRY (not FAILED)', st);
    // Clear the backoff so the test can re-process immediately.
    await pool.query(`UPDATE busy_sync_queue SET next_retry_at=NOW() WHERE id=$1`, [fe.row.id]);
    st = (await bf.queue.process(fe.row.id)).status; await pool.query(`UPDATE busy_sync_queue SET next_retry_at=NOW() WHERE id=$1`, [fe.row.id]);
    st = (await bf.queue.process(fe.row.id)).status;
    ok(st === 'SUCCESS', 'after the transient failures clear, it succeeds', st);
    const attempts = (await pool.query(`SELECT attempt_count FROM busy_sync_queue WHERE id=$1`, [fe.row.id])).rows[0].attempt_count;
    ok(attempts === 3, 'attempt_count reflects the retries', `attempts=${attempts}`);

    // ── 6. Partial / permanent failure ─────────────────────────────
    console.log('\nPartial failure');
    const failRef = 'MES:TRANSACTION:DISP-BAD:DISPATCH';
    const bfail = bridgeWith({ failRefs: [failRef] });
    const xe = await bfail.enqueue({ entity_type: 'TRANSACTION', dhown_entity_id: 'DISP-BAD', operation: 'DISPATCH', payload: {} });
    const xr = await bfail.queue.process(xe.row.id);
    ok(xr.status === 'FAILED', 'a permanent failure → FAILED (not retried forever)', xr.status);
    const failAudit = (await pool.query(`SELECT COUNT(*)::int n FROM busy_audit_log WHERE external_reference=$1 AND final_status='FAILED'`, [failRef])).rows[0].n;
    ok(failAudit >= 1, 'the failure is recorded in the audit log');

    // ── 7. Mapping mismatch + invalid warehouse reference ──────────
    console.log('\nMaster mapping');
    await b.mapping.upsert({ entity_type: 'WAREHOUSE', dhown_id: 'WH-YARN', dhown_name: 'Yarn Store', busy_id: 'BWH-1', busy_code: 'YARN', sync_status: 'SYNCED' });
    const clash = await b.mapping.upsert({ entity_type: 'WAREHOUSE', dhown_id: 'WH-OTHER', busy_id: 'BWH-1' });
    ok(clash.status === 'MANUAL_REVIEW', 'a BUSY warehouse already mapped to another DHOWN id → MANUAL_REVIEW (no silent merge)');
    const resolved = await b.mapping.requireBusyId('WAREHOUSE', 'WH-YARN');
    ok(resolved === 'BWH-1', 'a mapped warehouse resolves to its BUSY id', resolved);
    let threw = false;
    try { await b.mapping.requireBusyId('WAREHOUSE', 'WH-UNKNOWN'); } catch (e) { threw = e.code === 'MAP_MISSING'; }
    ok(threw, 'an unmapped warehouse/material-centre reference HARD-FAILS (no auto-create)');

    // ── 8. Warehouse master sync from BUSY (BUSY authoritative) ─────
    const bwh = bridgeWith({ masters: { WAREHOUSE: [{ busy_id: 'BWH-9', busy_code: 'GREIGE', name: 'Greige Store' }] } });
    const syncRes = await bwh.mapping.syncWarehousesFromBusy(bwh.connector, [{ id: 'WH-GREIGE', name: 'Greige', code: 'GREIGE' }, { id: 'WH-NOMATCH', name: 'X', code: 'ZZZ' }]);
    ok(syncRes.mapped === 1 && syncRes.manual_review === 1, 'BUSY→MES warehouse sync maps matches and flags unmatched for review', JSON.stringify(syncRes));

    // ── 9. Party-wise outstanding (issue → recovery → balance) ─────
    console.log('\nParty-wise outstanding (external-party issue/recovery)');
    await b.enqueue({ entity_type: 'TRANSACTION', dhown_entity_id: 'ISS-1', operation: 'PARTY_ISSUE', payload: { party: 'P1', qty: 100, original_ref: null } });
    await b.enqueue({ entity_type: 'TRANSACTION', dhown_entity_id: 'REC-1', operation: 'PARTY_RECOVERY', payload: { party: 'P1', qty: 60, original_ref: 'ISS-1' } });
    const outstanding = (await pool.query(`
      SELECT (payload->>'party') party,
             SUM(CASE WHEN operation='PARTY_ISSUE' THEN (payload->>'qty')::numeric ELSE 0 END)
             - SUM(CASE WHEN operation='PARTY_RECOVERY' THEN (payload->>'qty')::numeric ELSE 0 END) AS outstanding
        FROM busy_sync_queue WHERE operation IN ('PARTY_ISSUE','PARTY_RECOVERY') AND (payload->>'party')='P1'
       GROUP BY 1`)).rows[0];
    ok(Number(outstanding.outstanding) === 40, 'party-wise outstanding = issued − recovered (100 − 60 = 40)', `P1=${outstanding.outstanding}`);
    const linked = (await pool.query(`SELECT COUNT(*)::int n FROM busy_sync_queue WHERE operation='PARTY_RECOVERY' AND payload->>'original_ref'='ISS-1'`)).rows[0].n;
    ok(linked === 1, 'the recovery stays linked to the original issue');

    // ── 10. Reconciliation ─────────────────────────────────────────
    console.log('\nReconciliation');
    await b.processDue();
    const recon = await b.reconcile({ run_id: 'test-recon' });
    ok(recon.match >= 1 && recon.mismatch === 0, 'reconciliation reports MATCH for pushed documents, no mismatches', JSON.stringify(recon));

  } finally {
    await pool.query('TRUNCATE busy_sync_queue, busy_audit_log, busy_reconciliation, busy_master_mapping RESTART IDENTITY').catch(() => {});
    await pool.end();
  }
  console.log(fails ? `\n${fails} FAILED\n` : '\nAll BUSY integration checks passed (mock adapter — not a real-BUSY compatibility proof).\n');
  process.exit(fails ? 1 : 0);
})().catch((e) => { console.error('CRASH', e.message); process.exit(1); });
