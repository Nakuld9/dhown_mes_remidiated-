// BUSY integration-state schema (Phase 2). Re-implemented from the carried-forward
// design (busy-bridge branch migration_phase11_busy_bridge.sql), as an idempotent
// ensure() in main's style. Holds INTEGRATION STATE ONLY — the mapping between
// DHOWN and BUSY records, the outbound queue, the append-only audit and the
// reconciliation results. It is NOT a copy of the production tables and NOT a
// copy of BUSY's books.
//
// Source-of-truth is unchanged: the MES owns production; BUSY owns accounting.
// These tables never become a second ledger. Distinct from the READ-mirror
// tables (busy_outstanding/busy_stock/busy_trial_balance/... in lib/busy-bridge.js).
//
// One MES database == one company (dhown_mes / vdknits_mes are separate DBs,
// each mapping to its own BUSY company file), so no company_id scoping is needed
// inside these tables.

module.exports = (pool) => {
  let ensured = false;

  async function ensure() {
    if (ensured) return;
    // ── Master mapping ─────────────────────────────────────────────
    // One row per DHOWN master per entity type. IDs are never assumed equal
    // across the two systems, so every reference crosses this table.
    await pool.query(`
      CREATE TABLE IF NOT EXISTS busy_master_mapping (
        id              SERIAL PRIMARY KEY,
        entity_type     TEXT NOT NULL
                          CHECK (entity_type IN ('CUSTOMER','VENDOR','ITEM','WAREHOUSE','TRANSACTION')),
        dhown_id        TEXT NOT NULL,
        dhown_name      TEXT,
        busy_id         TEXT,
        busy_code       TEXT,
        sync_status     TEXT NOT NULL DEFAULT 'PENDING'
                          CHECK (sync_status IN ('PENDING','SYNCED','FAILED','MANUAL_REVIEW')),
        last_synced_at  TIMESTAMPTZ,
        error           TEXT,
        created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        CONSTRAINT uq_busy_mapping_entity UNIQUE (entity_type, dhown_id)
      )`);
    // A BUSY record must not be claimed by two DHOWN records — that would merge
    // two ledgers. Partial unique so unmapped rows do not collide.
    await pool.query(`CREATE UNIQUE INDEX IF NOT EXISTS uq_busy_mapping_busy
      ON busy_master_mapping (entity_type, busy_id) WHERE busy_id IS NOT NULL`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_busy_mapping_status ON busy_master_mapping (sync_status)`);

    // ── Sync queue ─────────────────────────────────────────────────
    await pool.query(`
      CREATE TABLE IF NOT EXISTS busy_sync_queue (
        id                  SERIAL PRIMARY KEY,
        entity_type         TEXT NOT NULL,
        dhown_entity_id     TEXT NOT NULL,
        operation           TEXT NOT NULL,
        document_origin     TEXT NOT NULL DEFAULT 'MES'
                              CHECK (document_origin IN ('MES','BUSY')),
        direction           TEXT NOT NULL DEFAULT 'MES_TO_BUSY'
                              CHECK (direction IN ('MES_TO_BUSY','BUSY_TO_MES')),
        payload             JSONB NOT NULL,
        payload_version     INTEGER NOT NULL DEFAULT 1,
        external_reference  TEXT NOT NULL,
        status              TEXT NOT NULL DEFAULT 'PENDING'
                              CHECK (status IN ('PENDING','PROCESSING','AWAITING_BUSY',
                                                'SUCCESS','FAILED','RETRY','MANUAL_REVIEW')),
        attempt_count       INTEGER NOT NULL DEFAULT 0,
        last_attempt_at     TIMESTAMPTZ,
        next_retry_at       TIMESTAMPTZ,
        busy_reference      TEXT,
        error_code          TEXT,
        error_message       TEXT,
        error_details       JSONB,
        created_by          TEXT NOT NULL DEFAULT 'DASHBOARD',
        created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )`);
    // THE idempotency guarantee: the DB rejects a second row with the same
    // external_reference, so concurrent/replayed submissions cannot create two
    // BUSY transactions.
    await pool.query(`CREATE UNIQUE INDEX IF NOT EXISTS uq_busy_queue_external_ref
      ON busy_sync_queue (external_reference)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_busy_queue_claim ON busy_sync_queue (status, next_retry_at)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_busy_queue_entity ON busy_sync_queue (entity_type, dhown_entity_id)`);

    // ── Audit (append-only) ────────────────────────────────────────
    await pool.query(`
      CREATE TABLE IF NOT EXISTS busy_audit_log (
        id                  SERIAL PRIMARY KEY,
        queue_id            INTEGER REFERENCES busy_sync_queue(id) ON DELETE SET NULL,
        entity_type         TEXT NOT NULL,
        dhown_entity_id     TEXT NOT NULL,
        external_reference  TEXT,
        operation           TEXT NOT NULL,
        payload_version     INTEGER NOT NULL DEFAULT 1,
        payload_snapshot    JSONB,
        attempt_count       INTEGER NOT NULL DEFAULT 0,
        actor               TEXT NOT NULL DEFAULT 'system',
        busy_response       TEXT,
        busy_reference      TEXT,
        final_status        TEXT NOT NULL,
        error_code          TEXT,
        error_message       TEXT,
        created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_busy_audit_queue ON busy_audit_log (queue_id)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_busy_audit_ref ON busy_audit_log (external_reference)`);

    // ── Reconciliation ─────────────────────────────────────────────
    await pool.query(`
      CREATE TABLE IF NOT EXISTS busy_reconciliation (
        id                  SERIAL PRIMARY KEY,
        run_id              TEXT NOT NULL,
        entity_type         TEXT NOT NULL,
        dhown_entity_id     TEXT,
        external_reference  TEXT,
        busy_reference      TEXT,
        result              TEXT NOT NULL
                              CHECK (result IN ('MATCH','MISMATCH','MISSING_IN_BUSY',
                                                'MISSING_IN_MES','DUPLICATE')),
        differences         JSONB,
        resolved            BOOLEAN NOT NULL DEFAULT FALSE,
        created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_busy_recon_run ON busy_reconciliation (run_id)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_busy_recon_result ON busy_reconciliation (result, resolved)`);

    // ── Connection health (single row) ─────────────────────────────
    await pool.query(`
      CREATE TABLE IF NOT EXISTS busy_connection_state (
        id                  INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
        online              BOOLEAN NOT NULL DEFAULT FALSE,
        adapter             TEXT,
        last_checked_at     TIMESTAMPTZ,
        last_success_at     TIMESTAMPTZ,
        last_error_code     TEXT,
        last_error_message  TEXT
      )`);
    await pool.query(`INSERT INTO busy_connection_state (id, online) VALUES (1, FALSE) ON CONFLICT (id) DO NOTHING`);

    ensured = true;
    return { ok: true };
  }

  return { ensure };
};
