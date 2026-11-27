// Integration document identity (Phase 2).
//
// The external_reference is the stable, deterministic idempotency key for a
// logical document+operation. The same business event always produces the same
// reference, so a replayed/retried/concurrent submission collides on the queue's
// UNIQUE(external_reference) index instead of creating a second BUSY document.
//
// It also encodes document ORIGIN (which system authored the document), which the
// bidirectional Purchase/Receipt flow needs to apply source-of-truth + conflict
// rules (a BUSY-originated purchase must not be re-created by MES, and vice-versa).

const ORIGINS = ['MES', 'BUSY'];
const ENTITY_TYPES = ['CUSTOMER', 'VENDOR', 'ITEM', 'WAREHOUSE', 'TRANSACTION'];

function makeExternalReference({ document_origin = 'MES', entity_type, dhown_entity_id, operation }) {
  if (!ORIGINS.includes(document_origin)) throw new Error(`document_origin must be one of ${ORIGINS.join('/')}`);
  if (!entity_type) throw new Error('entity_type required');
  if (dhown_entity_id === undefined || dhown_entity_id === null || dhown_entity_id === '') throw new Error('dhown_entity_id required');
  if (!operation) throw new Error('operation required');
  // Readable + stable. Colons are reserved as the separator; strip any from ids.
  const clean = (s) => String(s).replace(/:/g, '_');
  return [clean(document_origin), clean(entity_type), clean(dhown_entity_id), clean(operation)].join(':');
}

function parseExternalReference(ref) {
  const [document_origin, entity_type, dhown_entity_id, operation] = String(ref).split(':');
  return { document_origin, entity_type, dhown_entity_id, operation };
}

module.exports = { ORIGINS, ENTITY_TYPES, makeExternalReference, parseExternalReference };
