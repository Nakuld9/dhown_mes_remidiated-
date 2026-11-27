// BusyConnector — the replaceable abstraction over BUSY 21 (Phase 2).
//
// NOTHING in the MES talks to BUSY except through a connector that implements
// this contract. The method the real BUSY uses is NOT assumed to be a REST API;
// BUSY 21 has no official public REST API (see 14_BUSY_CONNECTOR_DESIGN.md).
// Adapters will be: AceOledbReadConnector (read, proven), XmlExcelDocConnector
// (write via BUSY's Data Export/Import — primary write candidate), PartnerApi
// connector (if ever licensed), and MockBusyConnector (default — dev/tests only).
//
// The MockBusyConnector proves the BRIDGE is correct. It does NOT prove real
// BUSY compatibility — that requires a confirmed vendor method + real instance.

// Capability descriptor an adapter advertises. The bridge consults this instead
// of assuming any method exists.
const CAPABILITY_KEYS = [
  'method',            // 'MOCK' | 'ACE_OLEDB_READ' | 'XML_DOC' | 'EXCEL_DOC' | 'PARTNER_API'
  'can_read_masters',  // list BUSY masters (customers/vendors/items/warehouses)
  'can_push_document', // submit a document MES→BUSY
  'can_return_reference', // return the BUSY voucher/doc reference synchronously
  'is_async_posting',  // BUSY posting completes later (file import) → AWAITING_BUSY
  'can_read_posting_status', // query confirmed posting status
  'writes_directly_to_busy_db', // MUST be false — never write BUSY's internal DB
];

// Every connector MUST implement these async methods. Throwing or returning
// { ok:false, retryable } drives the queue's retry/failure handling.
const REQUIRED_METHODS = ['capabilities', 'health', 'listMasters', 'pushDocument', 'getDocumentReference', 'getPostingStatus'];

function assertConnector(c) {
  for (const m of REQUIRED_METHODS) {
    if (typeof c[m] !== 'function') throw new Error(`BusyConnector missing method: ${m}`);
  }
  const caps = c.capabilities();
  if (caps.writes_directly_to_busy_db === true) {
    throw new Error('A connector that writes directly to BUSY\'s internal database is forbidden.');
  }
  return c;
}

// Select the active adapter. Default is the mock — a real adapter is chosen only
// when its method is confirmed and configured (never by default).
function selectConnector(pool, opts = {}) {
  const which = (opts.connector || process.env.BUSY_CONNECTOR || 'mock').toLowerCase();
  switch (which) {
    case 'mock':
      return assertConnector(require('./adapters/mock')(pool, opts));
    // Real adapters are added here once the vendor method is confirmed. Until
    // then, requesting one fails loudly rather than silently falling back.
    case 'xml':
    case 'excel':
    case 'ace':
    case 'partner':
      throw new Error(`BUSY connector '${which}' is not implemented yet — vendor method unconfirmed. Use 'mock'.`);
    default:
      throw new Error(`Unknown BUSY_CONNECTOR '${which}'.`);
  }
}

module.exports = { CAPABILITY_KEYS, REQUIRED_METHODS, assertConnector, selectConnector };
