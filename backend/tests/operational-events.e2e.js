// Operational-event integration (Phase 2.1) — mock-backed, feature-flagged.
//
// Verifies that real MES workflows (purchase, GRN/receipt, party issue/recovery,
// dispatch) feed the bridge correctly, that integration is OFF by default and a
// pure no-op when off, and the safety properties: transactional capture, duplicate
// prevention, concurrency, circular-sync prevention, unmapped-warehouse rejection,
// party-wise outstanding, dispatch≠invoice. Mock adapter — not a real-BUSY proof.
//
//   DB_NAME=<scratch> node tests/operational-events.e2e.js

require('dotenv').config({ quiet: true });
const { Pool } = require('pg');
const DB = process.env.DB_NAME || 'dhown_mes_staging';
if (['dhown_mes', 'vdknits_mes'].includes(DB)) { console.error(`Refusing to run on production DB "${DB}"`); process.exit(1); }
const pool = new Pool({ host: process.env.DB_HOST || 'localhost', user: process.env.DB_USER, password: process.env.DB_PASSWORD, database: DB, port: process.env.DB_PORT || 5432 });

const makeBridge = require('../src/lib/busy');
const makeMock = require('../src/lib/busy/adapters/mock');
const makeOpEvents = require('../src/lib/busy/operational-events');

let fails = 0;
const ok = (c, m, extra = '') => { console.log((c ? '  PASS  ' : '  FAIL  ') + m + (extra ? '   ' + extra : '')); if (!c) fails++; };
const ALL = ['purchase', 'grn_receipt', 'party_issue', 'party_recovery', 'dispatch'];
const rowCount = async (ref) => (await pool.query(`SELECT COUNT(*)::int n FROM busy_sync_queue WHERE external_reference=$1`, [ref])).rows[0].n;

(async () => {
  try {
    await makeBridge(pool, { connector: makeMock(pool) }).ensure();
    await pool.query('TRUNCATE busy_sync_queue, busy_audit_log, busy_reconciliation, busy_master_mapping RESTART IDENTITY');
    const op = makeOpEvents(pool);

    // ── Feature flags OFF by default → guaranteed no-op ────────────
    console.log('\nFeature flags (default OFF)');
    // No BUSY_EVENT_* env set, no override → every workflow disabled.
    const offResults = [];
    for (const w of ALL) offResults.push(await op.capture(pool, { workflow: w, record: { dhown_entity_id: `OFF-${w}` } }));
    ok(offResults.every(r => r.enabled === false), 'with flags OFF, capture() is a no-op for every workflow');
    const offRows = (await pool.query(`SELECT COUNT(*)::int n FROM busy_sync_queue`)).rows[0].n;
    ok(offRows === 0, 'OFF produces ZERO integration-queue side effects', `rows=${offRows}`);

    // ── Flags ON (explicit override) → each workflow captures ──────
    console.log('\nFeature flags ON — every supported workflow captures');
    const r = {};
    r.purchase = await op.capture(pool, { workflow: 'purchase', enabled: ALL, record: { dhown_entity_id: 'PO-1', supplier: 'ACME' } });
    r.grn = await op.capture(pool, { workflow: 'grn_receipt', enabled: ALL, record: { dhown_entity_id: 'GRN-1', warehouse_code: 'WH-YARN' } });
    r.issue = await op.capture(pool, { workflow: 'party_issue', enabled: ALL, record: { dhown_entity_id: 'SC-1', party: 'DyeHouse', qty: 100 } });
    r.recovery = await op.capture(pool, { workflow: 'party_recovery', enabled: ALL, record: { dhown_entity_id: 'REC-1', party: 'DyeHouse', qty: 60, original_ref: 'SC-1' } });
    r.dispatch = await op.capture(pool, { workflow: 'dispatch', enabled: ALL, record: { dhown_entity_id: 'DISP-1', customer: 'VD' } });
    ok(Object.values(r).every(x => x.enabled && x.queued), 'all five workflows enqueue a bridge event when enabled');
    const ops = (await pool.query(`SELECT operation FROM busy_sync_queue ORDER BY operation`)).rows.map(x => x.operation);
    ok(['DISPATCH', 'MATERIAL_RECEIPT', 'PARTY_ISSUE', 'PARTY_RECOVERY', 'PURCHASE'].every(o => ops.includes(o)), 'each maps to the correct BUSY operation', ops.join(','));

    // ── Dispatch separation from sales invoicing ──────────────────
    ok(!ops.some(o => /INVOICE|SALES/.test(o)), 'dispatch does NOT create a sales-invoice event (separation preserved)');

    // ── Duplicate + concurrent delivery ───────────────────────────
    console.log('\nDuplicate & concurrent delivery');
    const d1 = await op.capture(pool, { workflow: 'dispatch', enabled: ALL, record: { dhown_entity_id: 'DISP-DUP' } });
    const d2 = await op.capture(pool, { workflow: 'dispatch', enabled: ALL, record: { dhown_entity_id: 'DISP-DUP' } });
    ok(d1.queued && d2.duplicate && await rowCount(d1.external_reference) === 1, 'duplicate delivery of one event → one queue row');
    const conc = await Promise.allSettled(Array.from({ length: 6 }, () => op.capture(pool, { workflow: 'dispatch', enabled: ALL, record: { dhown_entity_id: 'DISP-CONC' } })));
    ok(conc.every(x => x.status === 'fulfilled') && (await pool.query(`SELECT COUNT(*)::int n FROM busy_sync_queue WHERE dhown_entity_id='DISP-CONC'`)).rows[0].n === 1, 'six concurrent deliveries → one row');

    // ── Transactional capture: interrupted (rolled-back) txn ───────
    console.log('\nTransaction safety');
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await op.capture(client, { workflow: 'dispatch', enabled: ALL, record: { dhown_entity_id: 'DISP-ROLLBACK' } });
      await client.query('ROLLBACK');
    } finally { client.release(); }
    ok((await pool.query(`SELECT COUNT(*)::int n FROM busy_sync_queue WHERE dhown_entity_id='DISP-ROLLBACK'`)).rows[0].n === 0,
      'a capture inside a ROLLED-BACK business transaction leaves NO event (transactional outbox)');

    // ── Circular-synchronisation prevention ───────────────────────
    console.log('\nCircular-sync prevention (bidirectional purchase/receipt)');
    const busyOrigin = await op.capture(pool, { workflow: 'purchase', enabled: ALL, record: { dhown_entity_id: 'PO-FROM-BUSY', document_origin: 'BUSY' } });
    ok(busyOrigin.skipped === 'origin_busy' && await rowCount('BUSY:TRANSACTION:PO-FROM-BUSY:PURCHASE') === 0,
      'a BUSY-originated purchase is NOT pushed back to BUSY (no circular sync)');

    // ── Unmapped warehouse reference is rejected at processing ─────
    console.log('\nWarehouse controls');
    const bridge = makeBridge(pool, { connector: makeMock(pool) });   // queue has mapping
    await bridge.mapping.upsert({ entity_type: 'WAREHOUSE', dhown_id: 'WH-YARN', busy_id: 'BWH-1', busy_code: 'YARN', sync_status: 'SYNCED' });
    const okRef = (await pool.query(`SELECT id FROM busy_sync_queue WHERE external_reference=$1`, [r.grn.external_reference])).rows[0].id;  // GRN-1 → WH-YARN (mapped)
    const okProc = await bridge.queue.process(okRef);
    ok(okProc.status === 'SUCCESS', 'an event on a MAPPED warehouse processes to SUCCESS', okProc.status);
    const badCap = await op.capture(pool, { workflow: 'grn_receipt', enabled: ALL, record: { dhown_entity_id: 'GRN-BAD', warehouse_code: 'WH-NOPE' } });
    const badProc = await bridge.queue.process(badCap.id);
    ok(badProc.status === 'MANUAL_REVIEW', 'an event on an UNMAPPED warehouse is REJECTED (MANUAL_REVIEW, no push, business untouched)', badProc.status);

    // ── Party-wise issued / recovered / outstanding ───────────────
    console.log('\nParty-wise outstanding');
    const outstanding = (await pool.query(`
      SELECT SUM(CASE WHEN operation='PARTY_ISSUE' THEN (payload->>'qty')::numeric ELSE 0 END)
           - SUM(CASE WHEN operation='PARTY_RECOVERY' THEN (payload->>'qty')::numeric ELSE 0 END) AS bal
        FROM busy_sync_queue WHERE operation IN ('PARTY_ISSUE','PARTY_RECOVERY') AND (payload->>'party')='DyeHouse'`)).rows[0];
    ok(Number(outstanding.bal) === 40, 'party-wise outstanding = issued − recovered (100 − 60 = 40)', `DyeHouse=${outstanding.bal}`);
    ok((await pool.query(`SELECT COUNT(*)::int n FROM busy_sync_queue WHERE operation='PARTY_RECOVERY' AND payload->>'original_ref'='SC-1'`)).rows[0].n === 1,
      'recovery stays correlated to the original issue');

    // ── Retry / failure end-to-end through the queue ──────────────
    console.log('\nRetry & failure (through the queue)');
    const flakyRef = 'MES:TRANSACTION:DISP-FLK:DISPATCH';
    const bflaky = makeBridge(pool, { connector: makeMock(pool, { behavior: { flakyRefs: { [flakyRef]: 1 } } }) });
    const fc = await op.capture(pool, { workflow: 'dispatch', enabled: ALL, record: { dhown_entity_id: 'DISP-FLK' } });
    let s = (await bflaky.queue.process(fc.id)).status; ok(s === 'RETRY', 'transient failure → RETRY', s);
    await pool.query(`UPDATE busy_sync_queue SET next_retry_at=NOW() WHERE id=$1`, [fc.id]);
    s = (await bflaky.queue.process(fc.id)).status; ok(s === 'SUCCESS', 'then SUCCESS after the transient clears', s);

  } finally {
    await pool.query('TRUNCATE busy_sync_queue, busy_audit_log, busy_reconciliation, busy_master_mapping RESTART IDENTITY').catch(() => {});
    await pool.end();
  }
  console.log(fails ? `\n${fails} FAILED\n` : '\nAll operational-event integration checks passed (mock adapter — not a real-BUSY proof).\n');
  process.exit(fails ? 1 : 0);
})().catch((e) => { console.error('CRASH', e.message); process.exit(1); });
