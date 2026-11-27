// MOCK digital-weighing-scale adapter — a TEST implementation only.
//
// It does NOT talk to any real scale, serial/USB/Ethernet port, or vendor API.
// It emits canonical ScaleReadings (events.js) in memory. It supports multiple
// scale IDs / weighing stations. Every reading is sourced 'mock-scale'.
//
// Implements the replaceable WeighingConnector contract:
//   { readStable(), stream(cb), health(), ...simulate* }
//
// No real vendor communication protocol is implied. Whether a real scale offers
// a stability flag / net-vs-gross output is vendor-dependent (report 29 §18).

const { scaleReading } = require('../events');

function createMockScale(opts = {}) {
  const scale_id = opts.scale_id || 'MOCK-SCALE-1';
  const workstation_id = opts.workstation_id || 'WS-1';
  const capacity = Number(opts.capacity || 50);      // kg
  const resolution = Number(opts.resolution || 0.01);
  const unit = opts.unit || 'kg';
  let connected = true;
  const emitted = [];
  let subscriber = null;

  function emit(rd) { emitted.push(rd); if (connected && subscriber) subscriber(rd); return rd; }
  function make(extra = {}) { return scaleReading({ scale_id, workstation_id, unit, ...extra }); }

  return {
    capabilities: () => ({ kind: 'mock', writes_to_real_scale: false, capacity, resolution, unit }),
    stream(cb) { subscriber = cb; return () => { subscriber = null; }; },
    async health() { return { connected, scale_id, workstation_id }; },

    // ---- valid readings ----
    // stable gross reading with a tare (net computed by caller/validation, not here)
    stableGross(gross, tare = 0, extra = {}) {
      return emit(make({ raw_reading: gross, gross, tare, stable: true, weight_basis: 'GROSS', ...extra }));
    },
    // a scale that itself reports NET (no second tare subtraction allowed downstream)
    stableNet(net, extra = {}) {
      return emit(make({ raw_reading: net, net, stable: true, weight_basis: 'NET', ...extra }));
    },
    // ---- abnormal readings ----
    unstable(gross, extra = {}) { return emit(make({ raw_reading: gross, gross, stable: false, weight_basis: 'GROSS', ...extra })); },
    zero(extra = {}) { return emit(make({ raw_reading: 0, gross: 0, stable: true, weight_basis: 'GROSS', ...extra })); },
    negative(extra = {}) { return emit(make({ raw_reading: -1, gross: -1, stable: true, weight_basis: 'GROSS', ...extra })); },
    overCapacity(extra = {}) { return emit(make({ raw_reading: capacity + 10, gross: capacity + 10, stable: true, weight_basis: 'GROSS', ...extra })); },
    wrongUnit(gross, badUnit = 'lb', extra = {}) { return emit(make({ raw_reading: gross, gross, stable: true, unit: badUnit, weight_basis: 'GROSS', ...extra })); },
    invalid(extra = {}) { return emit(make({ raw_reading: 'NaN', gross: null, stable: null, weight_basis: 'GROSS', ...extra })); },
    duplicate(rd) { return emit({ ...rd, read_at: new Date().toISOString() }); },
    delayed(gross, readAtIso, extra = {}) { return emit(make({ raw_reading: gross, gross, stable: true, read_at: readAtIso, weight_basis: 'GROSS', ...extra })); },

    // ---- connectivity ----
    disconnect() { connected = false; },
    reconnect() { connected = true; },

    _state: () => ({ connected, emitted: emitted.length, scale_id, workstation_id }),
    meta: () => ({ scale_id, workstation_id, capacity, resolution, unit }),
  };
}

module.exports = { createMockScale };
