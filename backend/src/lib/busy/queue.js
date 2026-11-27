// Sync queue (Phase 2) — the heart of the bridge. Enqueue is idempotent on the
// external_reference; processing is concurrency-safe via an atomic claim; failures
// retry with backoff; every outcome is written to the append-only audit log.
//
// Nothing here writes to BUSY directly — it calls the active BusyConnector, which
// is the mock in dev/tests. Physical stock & production stay in the MES; this
// carries only the integration handoff.

const { makeExternalReference } = require('./identity');

const MAX_ATTEMPTS = parseInt(process.env.BUSY_MAX_ATTEMPTS || '5');
const BACKOFF_BASE_MS = parseInt(process.env.BUSY_BACKOFF_BASE_MS || '1000');
const BACKOFF_CAP_MS = parseInt(process.env.BUSY_BACKOFF_CAP_MS || '3600000');

module.exports = (pool, connector) => {
  async function audit(row, final_status, extra = {}) {
    await pool.query(
      `INSERT INTO busy_audit_log (queue_id, entity_type, dhown_entity_id, external_reference, operation,
         payload_version, payload_snapshot, attempt_count, actor, busy_response, busy_reference, final_status, error_code, error_message)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)`,
      [row.id, row.entity_type, row.dhown_entity_id, row.external_reference, row.operation,
        row.payload_version || 1, row.payload || null, row.attempt_count || 0, extra.actor || row.created_by || 'system',
        extra.busy_response || null, extra.busy_reference || null, final_status, extra.error_code || null, extra.error_message || null]).catch(() => {});
  }

  // Idempotent enqueue. A second submission of the same logical event (same
  // external_reference) is a no-op that returns the existing row — the UNIQUE
  // index makes this safe under concurrency and replay.
  async function enqueue({ entity_type, dhown_entity_id, operation, payload, document_origin = 'MES',
                           direction = 'MES_TO_BUSY', payload_version = 1, created_by = 'DASHBOARD' }) {
    const external_reference = makeExternalReference({ document_origin, entity_type, dhown_entity_id, operation });
    const ins = await pool.query(
      `INSERT INTO busy_sync_queue (entity_type, dhown_entity_id, operation, document_origin, direction,
         payload, payload_version, external_reference, status, created_by)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'PENDING',$9)
       ON CONFLICT (external_reference) DO NOTHING
       RETURNING *`,
      [entity_type, String(dhown_entity_id), operation, document_origin, direction, payload || {}, payload_version, external_reference, created_by]);
    if (ins.rows[0]) return { ok: true, queued: true, external_reference, row: ins.rows[0] };
    const existing = (await pool.query(`SELECT * FROM busy_sync_queue WHERE external_reference=$1`, [external_reference])).rows[0];
    return { ok: true, queued: false, duplicate: true, external_reference, row: existing };
  }

  // Atomic claim: flips PENDING/RETRY -> PROCESSING and bumps the attempt in one
  // statement. Two concurrent processors cannot both claim the same row.
  async function claim(id) {
    return (await pool.query(
      `UPDATE busy_sync_queue SET status='PROCESSING', attempt_count=attempt_count+1, last_attempt_at=NOW(), updated_at=NOW()
        WHERE id=$1 AND status IN ('PENDING','RETRY') RETURNING *`, [id])).rows[0] || null;
  }

  function backoff(attempts) {
    return new Date(Date.now() + Math.min(BACKOFF_BASE_MS * 2 ** Math.max(0, attempts - 1), BACKOFF_CAP_MS));
  }

  async function finish(id, status, fields = {}) {
    const sets = ['status=$2', 'updated_at=NOW()'];
    const vals = [id, status];
    for (const [k, v] of Object.entries(fields)) { vals.push(v); sets.push(`${k}=$${vals.length}`); }
    return (await pool.query(`UPDATE busy_sync_queue SET ${sets.join(', ')} WHERE id=$1 RETURNING *`, vals)).rows[0];
  }

  // Process one queue row. Idempotent: an already-SUCCESS row is returned as-is
  // (never re-pushed). A row that cannot be claimed (already terminal / in flight)
  // is returned unchanged.
  async function process(id) {
    const current = (await pool.query(`SELECT * FROM busy_sync_queue WHERE id=$1`, [id])).rows[0];
    if (!current) return { ok: false, error: 'not found' };
    if (current.status === 'SUCCESS') return { ok: true, status: 'SUCCESS', row: current, replay: true };

    const row = await claim(id);
    if (!row) return { ok: false, status: current.status, row: current, note: 'not claimable (terminal or in flight)' };

    let res;
    try {
      res = await connector.pushDocument({
        external_reference: row.external_reference, entity_type: row.entity_type,
        operation: row.operation, direction: row.direction, payload: row.payload,
      });
    } catch (e) {
      const terminal = row.attempt_count >= MAX_ATTEMPTS;
      const out = await finish(id, terminal ? 'MANUAL_REVIEW' : 'RETRY',
        { error_code: e.code || 'CONNECTOR_THREW', error_message: e.message, next_retry_at: backoff(row.attempt_count) });
      await audit(row, out.status, { error_code: e.code || 'CONNECTOR_THREW', error_message: e.message });
      return { ok: false, status: out.status, row: out, error: e.message };
    }

    if (res.ok && res.status === 'AWAITING_BUSY') {
      const out = await finish(id, 'AWAITING_BUSY', { busy_reference: null, error_code: null, error_message: null });
      await audit(row, 'AWAITING_BUSY', { busy_response: res.response });
      return { ok: true, status: 'AWAITING_BUSY', row: out };
    }
    if (res.ok) {
      const out = await finish(id, 'SUCCESS', { busy_reference: res.busy_reference || null, error_code: null, error_message: null });
      await audit(row, 'SUCCESS', { busy_reference: res.busy_reference, busy_response: res.response });
      return { ok: true, status: 'SUCCESS', busy_reference: res.busy_reference, row: out };
    }
    // Failure: retry if retryable and attempts remain, else terminal.
    const terminal = !res.retryable || row.attempt_count >= MAX_ATTEMPTS;
    const status = terminal ? (res.retryable ? 'MANUAL_REVIEW' : 'FAILED') : 'RETRY';
    const out = await finish(id, status, { error_code: res.error_code || 'PUSH_FAILED', error_message: res.error_message || 'push failed', next_retry_at: terminal ? null : backoff(row.attempt_count) });
    await audit(row, status, { error_code: res.error_code, error_message: res.error_message });
    return { ok: false, status, row: out };
  }

  // Process all due rows (PENDING, or RETRY whose next_retry_at has passed). The
  // atomic claim makes it safe to run several of these concurrently.
  async function processDue({ limit = 50 } = {}) {
    const due = (await pool.query(
      `SELECT id FROM busy_sync_queue WHERE status IN ('PENDING','RETRY')
         AND (next_retry_at IS NULL OR next_retry_at <= NOW()) ORDER BY id LIMIT $1`, [limit])).rows;
    const out = { processed: 0, success: 0, awaiting: 0, retry: 0, failed: 0, manual_review: 0, results: [] };
    for (const { id } of due) {
      const r = await process(id);
      out.processed++;
      if (r.status === 'SUCCESS') out.success++;
      else if (r.status === 'AWAITING_BUSY') out.awaiting++;
      else if (r.status === 'RETRY') out.retry++;
      else if (r.status === 'FAILED') out.failed++;
      else if (r.status === 'MANUAL_REVIEW') out.manual_review++;
      out.results.push({ id, status: r.status });
    }
    return out;
  }

  // Reconcile MES's record of each handled document against BUSY (via the
  // connector). Writes MATCH / MISMATCH / MISSING_IN_BUSY rows for review.
  async function reconcile({ run_id = `recon-${Date.now()}` } = {}) {
    const rows = (await pool.query(
      `SELECT * FROM busy_sync_queue WHERE status IN ('SUCCESS','AWAITING_BUSY')`)).rows;
    const summary = { run_id, match: 0, mismatch: 0, missing_in_busy: 0 };
    for (const row of rows) {
      const busyRef = await connector.getDocumentReference(row.external_reference).catch(() => null);
      let result, differences = null;
      if (!busyRef) { result = 'MISSING_IN_BUSY'; summary.missing_in_busy++; }
      else if (row.busy_reference && row.busy_reference !== busyRef) {
        result = 'MISMATCH'; differences = { mes: row.busy_reference, busy: busyRef }; summary.mismatch++;
      } else { result = 'MATCH'; summary.match++; }
      await pool.query(
        `INSERT INTO busy_reconciliation (run_id, entity_type, dhown_entity_id, external_reference, busy_reference, result, differences)
         VALUES ($1,$2,$3,$4,$5,$6,$7)`,
        [run_id, row.entity_type, row.dhown_entity_id, row.external_reference, busyRef, result, differences]);
    }
    return summary;
  }

  async function updateConnectionHealth() {
    const h = await connector.health().catch((e) => ({ online: false, adapter: 'unknown', detail: e.message }));
    await pool.query(
      `UPDATE busy_connection_state SET online=$1, adapter=$2, last_checked_at=NOW(),
         last_success_at=CASE WHEN $1 THEN NOW() ELSE last_success_at END WHERE id=1`,
      [!!h.online, h.adapter || connector.capabilities().method]);
    return h;
  }

  return { enqueue, process, processDue, reconcile, updateConnectionHealth, MAX_ATTEMPTS, _audit: audit };
};
