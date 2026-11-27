// BUSY integration bridge (Phase 2) — factory that wires the integration-state
// schema, the selected connector (mock by default), the master mapping and the
// sync queue into one object. This is the ONLY surface the rest of the MES uses
// to talk to BUSY, and it never writes to BUSY's internal database.
//
//   const bridge = require('./lib/busy')(pool);
//   await bridge.ensure();                       // create integration-state tables
//   await bridge.enqueue({ ... });               // idempotent handoff
//   await bridge.queue.processDue();              // push via the active connector
//
// Default connector = mock. A real connector is selected only once a vendor
// method is confirmed (BUSY_CONNECTOR env), never silently.

const makeSchema = require('./schema');
const makeMapping = require('./mapping');
const makeQueue = require('./queue');
const { selectConnector } = require('./connector');

module.exports = (pool, opts = {}) => {
  const schema = makeSchema(pool);
  const connector = opts.connector && typeof opts.connector === 'object'
    ? opts.connector                       // test can inject a pre-built adapter
    : selectConnector(pool, opts);
  const mapping = makeMapping(pool);
  const queue = makeQueue(pool, connector, mapping);

  async function ensure() { return schema.ensure(); }

  return {
    ensure,
    connector,
    capabilities: () => connector.capabilities(),
    mapping,
    queue,
    // Convenience passthroughs
    enqueue: (...a) => queue.enqueue(...a),
    processDue: (...a) => queue.processDue(...a),
    reconcile: (...a) => queue.reconcile(...a),
    health: () => queue.updateConnectionHealth(),
  };
};
