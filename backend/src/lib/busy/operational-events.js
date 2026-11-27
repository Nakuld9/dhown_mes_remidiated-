// Operational-event capture (Phase 2.1) — connects real MES workflows to the
// BUSY bridge, FEATURE-FLAGGED OFF by default.
//
// Design (why this is safe to add to live workflows):
//   * capture() does ONE thing: an idempotent INSERT into busy_sync_queue. It
//     resolves NO mapping and calls NO connector here — those happen later at
//     queue PROCESS time, fully decoupled from the business write. So an unmapped
//     warehouse or a BUSY failure can NEVER roll back or change a factory
//     operation. Business behaviour is preserved exactly.
//   * When the workflow's flag is OFF, capture() returns immediately touching no
//     DB — a guaranteed no-op, zero side effects.
//   * capture() accepts a db (pool OR an open client), so it can join the
//     business transaction (transactional outbox) where a client is available,
//     and otherwise runs idempotently right after commit.
//   * Idempotency: UNIQUE(external_reference) → duplicate/concurrent/replayed
//     deliveries collapse to one queue row.
//   * Circular-sync: a PURCHASE/RECEIPT whose document_origin is BUSY is NOT
//     re-sent to BUSY (it came from there).

const { makeExternalReference } = require('./identity');

// workflow -> fixed integration shape.
const WORKFLOWS = {
  purchase:       { entity_type: 'TRANSACTION', operation: 'PURCHASE',         direction: 'MES_TO_BUSY', bidirectional: true },
  grn_receipt:    { entity_type: 'TRANSACTION', operation: 'MATERIAL_RECEIPT', direction: 'MES_TO_BUSY', bidirectional: true },
  party_issue:    { entity_type: 'TRANSACTION', operation: 'PARTY_ISSUE',      direction: 'MES_TO_BUSY', bidirectional: false },
  party_recovery: { entity_type: 'TRANSACTION', operation: 'PARTY_RECOVERY',   direction: 'MES_TO_BUSY', bidirectional: false },
  dispatch:       { entity_type: 'TRANSACTION', operation: 'DISPATCH',         direction: 'MES_TO_BUSY', bidirectional: false },
};

function envFlags() {
  const set = new Set();
  const all = (process.env.BUSY_EVENTS || '').toLowerCase();
  if (all === 'all') return new Set(Object.keys(WORKFLOWS));
  all.split(',').map((s) => s.trim()).filter(Boolean).forEach((w) => set.add(w));
  for (const w of Object.keys(WORKFLOWS)) {
    const v = process.env[`BUSY_EVENT_${w.toUpperCase()}`];
    if (v && /^(1|on|true|yes)$/i.test(v)) set.add(w);
  }
  return set;
}

module.exports = (pool) => {
  // `enabledOverride` (Set|array|{workflow:true}) lets tests control flags without
  // process-global env; otherwise the per-workflow env flags apply. Default: OFF.
  function isEnabled(workflow, enabledOverride) {
    if (enabledOverride) {
      if (enabledOverride instanceof Set) return enabledOverride.has(workflow);
      if (Array.isArray(enabledOverride)) return enabledOverride.includes(workflow);
      return !!enabledOverride[workflow];
    }
    return envFlags().has(workflow);
  }

  // record fields the mappers read (all optional except dhown_entity_id):
  //   dhown_entity_id, document_origin ('MES'|'BUSY'), warehouse_code, party,
  //   qty, original_ref, and any business detail (kept in payload).
  function buildEvent(workflow, record) {
    const spec = WORKFLOWS[workflow];
    if (!spec) throw new Error(`unknown operational workflow '${workflow}'`);
    const document_origin = record.document_origin || 'MES';
    const dhown_entity_id = record.dhown_entity_id;
    if (dhown_entity_id === undefined || dhown_entity_id === null || dhown_entity_id === '') {
      throw new Error(`${workflow}: dhown_entity_id required`);
    }
    // The payload is the integration snapshot — business detail, warehouse and
    // (for recovery) the correlation to the original issue.
    const payload = { ...record };
    delete payload.document_origin;
    const external_reference = makeExternalReference({ document_origin, entity_type: spec.entity_type, dhown_entity_id, operation: spec.operation });
    return { spec, document_origin, dhown_entity_id, payload, external_reference };
  }

  async function capture(db, { workflow, record = {}, actor = 'system', enabled } = {}) {
    if (!isEnabled(workflow, enabled)) return { enabled: false, workflow };
    const { spec, document_origin, dhown_entity_id, payload, external_reference } = buildEvent(workflow, record);

    // Circular-synchronisation guard: a bidirectional document that ORIGINATED in
    // BUSY is never pushed back to BUSY.
    if (spec.bidirectional && document_origin === 'BUSY') {
      return { enabled: true, skipped: 'origin_busy', external_reference };
    }

    const q = db && typeof db.query === 'function' ? db : pool;   // client (in-txn) or pool
    const ins = await q.query(
      `INSERT INTO busy_sync_queue (entity_type, dhown_entity_id, operation, document_origin, direction,
         payload, payload_version, external_reference, status, created_by)
       VALUES ($1,$2,$3,$4,$5,$6,1,$7,'PENDING',$8)
       ON CONFLICT (external_reference) DO NOTHING
       RETURNING id, status`,
      [spec.entity_type, String(dhown_entity_id), spec.operation, document_origin, spec.direction, payload, external_reference, actor]);
    return { enabled: true, queued: !!ins.rows[0], duplicate: !ins.rows[0], external_reference, id: ins.rows[0] && ins.rows[0].id };
  }

  // Defensive extractors: map a create handler's RESPONSE body (the created row)
  // to a capture record. Return null when the shape doesn't match → no capture
  // (safe). document_origin defaults to MES; a BUSY-originated row (if the handler
  // marks it) is skipped by the circular-sync guard in capture().
  const EXTRACTORS = {
    grn_receipt: (body) => (body && (body.grn_number || body.grn_id)) ? {
      dhown_entity_id: body.grn_number || body.grn_id, warehouse_code: body.warehouse_code || body.warehouse_id || null,
      supplier: body.supplier_name || null, amount: body.amount || null, document_origin: body.busy_origin ? 'BUSY' : 'MES' } : null,
    dispatch: (body) => (body && (body.dispatch_number || body.dispatch_id)) ? {
      dhown_entity_id: body.dispatch_number || body.dispatch_id, customer: body.customer_name || null, dispatch_type: body.dispatch_type || null } : null,
    purchase: (body) => (body && (body.po_number || body.po_id || body.order_number)) ? {
      dhown_entity_id: body.po_number || body.po_id || body.order_number, supplier: body.supplier_name || body.party_name || null,
      document_origin: body.busy_origin ? 'BUSY' : 'MES' } : null,
    party_issue: (body) => (body && (body.challan_number || body.challan_id)) ? {
      dhown_entity_id: body.challan_number || body.challan_id, party: body.vendor_name || null, qty: body.total_kg || null,
      warehouse_code: body.warehouse_code || null } : null,
    party_recovery: (body, req) => {
      const challan = (body && body.challan_id) || (req && req.params && req.params.id) || null;
      if (!challan) return null;
      const rid = (body && (body.receipt_id || body.id)) || null;
      return { dhown_entity_id: rid ? `REC-${rid}` : `REC-${challan}`, qty: (body && body.received_weight_kg) || null, original_ref: String(challan) };
    },
  };

  // Non-invasive capture middleware: inserted BEFORE a create handler in the route
  // chain (touches route registration only, never the handler body). It wraps
  // res.json so that AFTER a successful (2xx) response the created row is captured.
  // When the flag is OFF it is a pure pass-through. Capture is fire-and-forget and
  // wrapped so it can NEVER break the HTTP response or the business flow.
  function captureMw(workflow) {
    return (req, res, next) => {
      const origJson = res.json.bind(res);
      res.json = (body) => {
        try {
          if (res.statusCode >= 200 && res.statusCode < 300 && isEnabled(workflow)) {
            const rec = (EXTRACTORS[workflow] || (() => null))(body, req);
            if (rec) capture(pool, { workflow, record: rec, actor: (req.user && req.user.username) || 'system' }).catch(() => {});
          }
        } catch (_) { /* never break the response */ }
        return origJson(body);
      };
      next();
    };
  }

  return { capture, captureMw, isEnabled, WORKFLOWS, EXTRACTORS, _envFlags: envFlags };
};
