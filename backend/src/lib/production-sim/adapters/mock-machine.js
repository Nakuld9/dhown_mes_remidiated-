// MOCK knitting-machine adapter — a TEST implementation only.
//
// It does NOT talk to any real machine, the Chinese manufacturer's cloud, or any
// network. It generates canonical MachineEvents (events.js) in memory so the
// event processor, state machine and roll-completion flow can be exercised and
// tested without equipment. Every event is clearly sourced 'mock-machine'.
//
// Implements the replaceable MachineConnector contract:
//   { subscribe(cb), fetchEvents(sinceIso), health(), ...simulate* }
//
// NOTHING here should ever be read as evidence that the real machine cloud
// supports these event types — that is entirely vendor-dependent (report 29 §18).

const { machineEvent } = require('../events');

function createMockMachine(opts = {}) {
  const device_id = opts.device_id || 'MOCK-DC-SJ03';
  const machine_id = opts.machine_id || 'SJ03';
  const source = 'mock-machine';
  let connected = true;
  let counter = Number(opts.start_counter || 0);
  const buffer = [];           // events held while "offline" (for replay)
  const emitted = [];          // everything ever produced (for assertions)
  let subscriber = null;

  function emit(ev) {
    emitted.push(ev);
    if (connected) {
      if (subscriber) subscriber(ev);
    } else {
      buffer.push(ev);          // offline → buffer for later replay
    }
    return ev;
  }

  function make(type, extra = {}) {
    return machineEvent({ device_id, machine_id, type, source, ...extra });
  }

  return {
    // ---- MachineConnector contract ----
    capabilities: () => ({ kind: 'mock', writes_to_real_machine: false }),
    subscribe(cb) { subscriber = cb; return () => { subscriber = null; }; },
    async fetchEvents() { return emitted.slice(); },
    async health() { return { connected, counter, buffered: buffer.length }; },

    // ---- simulation controls (test only) ----
    running() { return emit(make('RUNNING', { counter })); },
    advanceCounter(by = 1) { counter += Number(by); return emit(make('COUNTER', { counter })); },
    resetCounter(to = 0) { counter = Number(to); return emit(make('COUNTER', { counter, payload: { reset: true } })); },
    greenLight() { return emit(make('GREEN_LIGHT', { green_light: true, counter })); },
    stop() { return emit(make('STOP', { counter })); },
    // a "completion" = stop + green light at the current counter (a doff)
    completion(extra = {}) { return emit(make('COMPLETION', { green_light: true, counter, ...extra })); },
    fault(reason = 'MOCK_FAULT') { return emit(make('FAULT', { payload: { reason } })); },
    restart() { return emit(make('RESTART', { counter })); },

    // duplicate: same event_id as a prior event
    duplicate(ev) { return emit({ ...ev, received_at: new Date().toISOString() }); },
    // delayed/out-of-order: an event stamped in the past, delivered now
    delayed(type, observedAtIso, extra = {}) { return emit(make(type, { observed_at: observedAtIso, counter, ...extra })); },

    // communication failure + reconnection with replay of buffered events
    disconnect() { connected = false; },
    reconnectAndReplay() {
      connected = true;
      const replay = buffer.splice(0);
      if (subscriber) replay.forEach((e) => subscriber(e));
      return replay;
    },

    _state: () => ({ connected, counter, buffered: buffer.length, emitted: emitted.length }),
  };
}

module.exports = { createMockMachine };
