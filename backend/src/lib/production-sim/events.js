// Canonical device data contracts + validation (report 29 §9).
// Pure helpers — no I/O. Adapters translate vendor payloads into these shapes;
// nothing downstream sees a vendor-specific field.

let _seq = 0;
function synthId(prefix) {
  _seq += 1;
  return `${prefix}_${Date.now().toString(36)}_${_seq}`;
}

const MACHINE_EVENT_TYPES = ['RUNNING', 'COMPLETION', 'STOP', 'RESTART', 'FAULT', 'COUNTER', 'GREEN_LIGHT'];

// Build a canonical MachineEvent. `observed_at` = device time; `received_at` = now.
function machineEvent(input = {}) {
  const e = {
    event_id: input.event_id || synthId('evt'),
    device_id: input.device_id || null,
    machine_id: input.machine_id || null,
    type: input.type || null,
    counter: input.counter ?? null,
    green_light: input.green_light ?? null,
    observed_at: input.observed_at || new Date().toISOString(),
    received_at: input.received_at || new Date().toISOString(),
    source: input.source || 'mock-machine',
    payload: input.payload || {},
    validation_status: 'PENDING',
  };
  e.validation_status = validateMachineEvent(e).ok ? 'VALID' : 'INVALID';
  return e;
}

function validateMachineEvent(e) {
  const errors = [];
  if (!e.event_id) errors.push('missing event_id');
  if (!e.device_id) errors.push('missing device_id');
  if (!e.machine_id) errors.push('missing machine_id');
  if (!MACHINE_EVENT_TYPES.includes(e.type)) errors.push(`invalid type '${e.type}'`);
  if (!isFiniteDate(e.observed_at)) errors.push('invalid observed_at');
  if (!isFiniteDate(e.received_at)) errors.push('invalid received_at');
  if (e.counter !== null && !(Number.isFinite(Number(e.counter)) && Number(e.counter) >= 0)) {
    errors.push('invalid counter');
  }
  return { ok: errors.length === 0, errors };
}

// Build a canonical ScaleReading. weight_basis: 'GROSS' | 'NET' (what the device reported).
function scaleReading(input = {}) {
  return {
    reading_id: input.reading_id || synthId('rd'),
    scale_id: input.scale_id || null,
    workstation_id: input.workstation_id || null,
    raw_reading: input.raw_reading ?? null,
    unit: input.unit || null,
    stable: input.stable ?? null,            // null = scale gives no stability flag
    weight_basis: input.weight_basis || 'GROSS',
    gross: input.gross ?? null,
    tare: input.tare ?? null,
    net: input.net ?? null,
    read_at: input.read_at || new Date().toISOString(),
    operator_id: input.operator_id || null,
    pending_roll_id: input.pending_roll_id || null,
    source: input.source || 'mock-scale',
    validation_status: 'PENDING',
  };
}

function isFiniteDate(v) {
  const t = new Date(v).getTime();
  return Number.isFinite(t);
}

module.exports = { MACHINE_EVENT_TYPES, machineEvent, validateMachineEvent, scaleReading, synthId, isFiniteDate };
