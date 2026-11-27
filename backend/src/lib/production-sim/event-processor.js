// Device Event Processor (report 29 §B). Pure, in-memory, no DB.
//
// Responsibilities (all vendor-independent):
//   * schema/timestamp validation of canonical MachineEvents
//   * idempotency: a repeated (source, device_id, event_id) is ignored
//   * ordering: events are kept ordered by observed_at; a stale (older than the
//     last processed) event is flagged OUT_OF_ORDER and not applied
//   * offline recovery: events buffered during a disconnect are replayed in order
//
// It does NOT create rolls or touch any database — it hands clean, de-duplicated,
// ordered events to the caller (completion-manager).

function createEventProcessor(opts = {}) {
  const seen = new Set();                       // idempotency keys
  const perMachineLastObserved = new Map();     // machine_id -> last observed_at (ms)
  const accepted = [];
  const rejected = [];

  function key(e) { return `${e.source}|${e.device_id}|${e.event_id}`; }

  function ingest(e) {
    // 1. schema/validation
    if (e.validation_status === 'INVALID') {
      const rec = { event: e, outcome: 'REJECTED', reason: 'INVALID_SCHEMA' };
      rejected.push(rec); return rec;
    }
    // 2. idempotency
    const k = key(e);
    if (seen.has(k)) {
      const rec = { event: e, outcome: 'DUPLICATE', reason: 'IDEMPOTENT_SKIP' };
      rejected.push(rec); return rec;
    }
    // 3. ordering (per machine, by observed_at)
    const obs = new Date(e.observed_at).getTime();
    const last = perMachineLastObserved.get(e.machine_id);
    if (last != null && obs < last) {
      // stale event — record but do not apply (out of order)
      seen.add(k);
      const rec = { event: e, outcome: 'OUT_OF_ORDER', reason: `observed ${e.observed_at} < last ${new Date(last).toISOString()}` };
      rejected.push(rec); return rec;
    }
    // accept
    seen.add(k);
    perMachineLastObserved.set(e.machine_id, obs);
    const rec = { event: e, outcome: 'ACCEPTED' };
    accepted.push(rec);
    return rec;
  }

  // replay a batch (e.g. buffered during offline) — order by observed_at first
  function ingestBatch(events) {
    return events
      .slice()
      .sort((a, b) => new Date(a.observed_at) - new Date(b.observed_at))
      .map(ingest);
  }

  return {
    ingest,
    ingestBatch,
    stats: () => ({ accepted: accepted.length, rejected: rejected.length, seen: seen.size }),
    acceptedEvents: () => accepted.map((r) => r.event),
    rejections: () => rejected.slice(),
  };
}

module.exports = { createEventProcessor };
