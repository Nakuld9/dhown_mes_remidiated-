// MockBusyConnector — deterministic in-memory simulation of BUSY for development
// and tests. It implements the BusyConnector contract and lets tests inject
// failures, transient (retryable) errors and async posting.
//
// ⚠️ The mock proves the BRIDGE behaves correctly (idempotency, retry,
// reconciliation, mapping). It does NOT prove real BUSY 21 compatibility — that
// needs a confirmed vendor method and a real instance.
//
// opts.behavior (all optional, for tests):
//   failRefs   : string[]            external_references that fail permanently
//   flakyRefs  : { [ref]: number }   # of transient failures before success
//   asyncRefs  : string[]            references BUSY "accepts" but posts later
//   masters    : { [entityType]: [{ busy_id, busy_code, name }] }  mock BUSY masters

const crypto = require('crypto');

// Deterministic BUSY reference from the external_reference — a pure function, so
// replays/retries of the same event always resolve to the same reference (the
// mock never creates a duplicate for the same external_reference).
function mockRef(externalReference) {
  const h = crypto.createHash('sha1').update(String(externalReference)).digest('hex').slice(0, 10).toUpperCase();
  return `BUSY-MOCK-${h}`;
}

module.exports = (pool, opts = {}) => {
  const b = opts.behavior || {};
  const failRefs = new Set(b.failRefs || []);
  const asyncRefs = new Set(b.asyncRefs || []);
  const flaky = { ...(b.flakyRefs || {}) };          // ref -> remaining transient failures
  const mastersByType = b.masters || {};
  const accepted = new Map();                          // external_reference -> busy_reference (this instance)

  function capabilities() {
    return {
      method: 'MOCK',
      can_read_masters: true,
      can_push_document: true,
      can_return_reference: true,
      is_async_posting: false,
      can_read_posting_status: true,
      writes_directly_to_busy_db: false,
      note: 'Mock adapter — does not prove real BUSY compatibility.',
    };
  }

  async function health() {
    return { online: true, adapter: 'mock', detail: 'mock always online' };
  }

  // Read side — deterministic mock BUSY masters (used by mapping tests).
  async function listMasters(entityType) {
    return { ok: true, entity_type: entityType, records: mastersByType[entityType] || [] };
  }

  // Push a document MES→BUSY. Returns a result the queue interprets; never throws
  // for an expected business/transient failure (it returns { ok:false,... }).
  async function pushDocument({ external_reference, entity_type, operation }) {
    if (!external_reference) return { ok: false, retryable: false, error_code: 'NO_REF', error_message: 'external_reference required' };

    if (failRefs.has(external_reference)) {
      return { ok: false, retryable: false, error_code: 'MOCK_PERMANENT', error_message: `mock permanent failure for ${external_reference}` };
    }
    if (flaky[external_reference] && flaky[external_reference] > 0) {
      flaky[external_reference] -= 1;
      return { ok: false, retryable: true, error_code: 'MOCK_TRANSIENT', error_message: `mock transient failure (${flaky[external_reference]} left)` };
    }
    const ref = mockRef(external_reference);
    accepted.set(external_reference, ref);
    if (asyncRefs.has(external_reference)) {
      // BUSY accepted the document but will post it later (file-import style).
      return { ok: true, status: 'AWAITING_BUSY', busy_reference: null, response: `accepted ${operation} for later posting` };
    }
    return { ok: true, status: 'SUCCESS', busy_reference: ref, response: `posted ${entity_type}/${operation}` };
  }

  async function getDocumentReference(external_reference) {
    // Deterministic: a reference that was (or would be) accepted resolves the
    // same way, which is what a reconciliation re-check relies on.
    if (asyncRefs.has(external_reference) && !accepted.get(external_reference)) return null;
    return accepted.get(external_reference) || mockRef(external_reference);
  }

  async function getPostingStatus(busy_reference) {
    if (!busy_reference) return { posted: false, status: 'UNKNOWN' };
    return { posted: true, status: 'POSTED', busy_reference };
  }

  return { capabilities, health, listMasters, pushDocument, getDocumentReference, getPostingStatus, _mockRef: mockRef };
};
