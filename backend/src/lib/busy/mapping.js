// Master mapping (Phase 2) — the cross-reference between DHOWN masters and BUSY
// masters. IDs are never assumed equal. Warehouse/material-centre is the first
// and most critical mapping: BUSY is authoritative for it, it must be 1:1, and an
// unmapped centre HARD-FAILS a push (no auto-create, no auto-remap).

module.exports = (pool) => {
  // Upsert a mapping idempotently on (entity_type, dhown_id). A BUSY id already
  // claimed by a DIFFERENT dhown_id is a conflict → MANUAL_REVIEW, never a silent
  // merge (the partial unique index also enforces this at the DB level).
  async function upsert({ entity_type, dhown_id, dhown_name = null, busy_id = null, busy_code = null, sync_status = null }) {
    if (busy_id) {
      const clash = (await pool.query(
        `SELECT dhown_id FROM busy_master_mapping WHERE entity_type=$1 AND busy_id=$2 AND dhown_id <> $3`,
        [entity_type, busy_id, String(dhown_id)])).rows[0];
      if (clash) {
        await pool.query(
          `INSERT INTO busy_master_mapping (entity_type, dhown_id, dhown_name, sync_status, error, updated_at)
           VALUES ($1,$2,$3,'MANUAL_REVIEW',$4,NOW())
           ON CONFLICT (entity_type, dhown_id) DO UPDATE SET sync_status='MANUAL_REVIEW', error=EXCLUDED.error, updated_at=NOW()`,
          [entity_type, String(dhown_id), dhown_name, `BUSY id ${busy_id} already mapped to DHOWN ${clash.dhown_id}`]);
        return { ok: false, status: 'MANUAL_REVIEW', reason: `BUSY ${busy_id} already mapped to DHOWN ${clash.dhown_id}` };
      }
    }
    const status = sync_status || (busy_id ? 'SYNCED' : 'PENDING');
    const row = (await pool.query(
      `INSERT INTO busy_master_mapping (entity_type, dhown_id, dhown_name, busy_id, busy_code, sync_status, last_synced_at, updated_at)
       VALUES ($1,$2,$3,$4::text,$5,$6, CASE WHEN $4::text IS NULL THEN NULL ELSE NOW() END, NOW())
       ON CONFLICT (entity_type, dhown_id) DO UPDATE SET
         dhown_name=COALESCE(EXCLUDED.dhown_name, busy_master_mapping.dhown_name),
         busy_id=COALESCE(EXCLUDED.busy_id, busy_master_mapping.busy_id),
         busy_code=COALESCE(EXCLUDED.busy_code, busy_master_mapping.busy_code),
         sync_status=EXCLUDED.sync_status,
         last_synced_at=CASE WHEN EXCLUDED.busy_id IS NULL THEN busy_master_mapping.last_synced_at ELSE NOW() END,
         error=NULL, updated_at=NOW()
       RETURNING *`,
      [entity_type, String(dhown_id), dhown_name, busy_id, busy_code, status])).rows[0];
    return { ok: true, status: row.sync_status, mapping: row };
  }

  async function get(entity_type, dhown_id) {
    return (await pool.query(
      `SELECT * FROM busy_master_mapping WHERE entity_type=$1 AND dhown_id=$2`, [entity_type, String(dhown_id)])).rows[0] || null;
  }

  // Resolve a DHOWN id to its BUSY id, or HARD-FAIL. Used before any push that
  // references the master (e.g. a dispatch's warehouse/material-centre).
  async function requireBusyId(entity_type, dhown_id) {
    const m = await get(entity_type, dhown_id);
    if (!m) throw new MappingError(`No ${entity_type} mapping for DHOWN id '${dhown_id}'`, 'MAP_MISSING', entity_type, dhown_id);
    if (!m.busy_id || m.sync_status !== 'SYNCED') {
      throw new MappingError(`${entity_type} '${dhown_id}' is not synced to BUSY (status ${m.sync_status})`, 'MAP_UNSYNCED', entity_type, dhown_id);
    }
    return m.busy_id;
  }

  // Warehouse/material-centre is authoritative in BUSY — pull its masters via the
  // connector and reconcile into the mapping (match by busy_code to a DHOWN id).
  async function syncWarehousesFromBusy(connector, dhownWarehouses = []) {
    const caps = connector.capabilities();
    if (!caps.can_read_masters) return { ok: false, reason: 'connector cannot read masters' };
    const res = await connector.listMasters('WAREHOUSE');
    const byCode = new Map((res.records || []).map((r) => [String(r.busy_code || r.busy_id), r]));
    let mapped = 0, review = 0;
    for (const w of dhownWarehouses) {
      const match = byCode.get(String(w.code));
      if (match) {
        const r = await upsert({ entity_type: 'WAREHOUSE', dhown_id: w.id, dhown_name: w.name, busy_id: String(match.busy_id), busy_code: String(match.busy_code || match.busy_id), sync_status: 'SYNCED' });
        r.ok ? mapped++ : review++;
      } else {
        await upsert({ entity_type: 'WAREHOUSE', dhown_id: w.id, dhown_name: w.name, sync_status: 'MANUAL_REVIEW' });
        review++;
      }
    }
    return { ok: true, mapped, manual_review: review, busy_count: res.records ? res.records.length : 0 };
  }

  async function conflicts() {
    return (await pool.query(`SELECT * FROM busy_master_mapping WHERE sync_status='MANUAL_REVIEW' ORDER BY entity_type, dhown_id`)).rows;
  }

  return { upsert, get, requireBusyId, syncWarehousesFromBusy, conflicts };
};

class MappingError extends Error {
  constructor(message, code, entity_type, dhown_id) { super(message); this.name = 'MappingError'; this.code = code; this.entity_type = entity_type; this.dhown_id = dhown_id; }
}
module.exports.MappingError = MappingError;
