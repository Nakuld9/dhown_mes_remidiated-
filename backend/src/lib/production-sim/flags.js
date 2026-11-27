// Production-simulation feature flags — ALL OFF BY DEFAULT.
//
// Mirrors the established BUSY operational-events flag pattern: environment
// flags, with an optional `override` (Set | array | {flag:true}) so tests can
// control flags without mutating process-global env. When a flag is OFF the
// corresponding capability is a guaranteed no-op with zero side effects.
//
// This module NEVER connects to a real machine, a real scale, a vendor cloud,
// a production DB or BUSY. Every flag here gates MOCK behaviour only. Turning a
// flag ON still only enables the in-memory simulator / processor — there is no
// real-equipment code path in this module at all.

const FLAGS = [
  'mock_machine',      // PRODSIM_MOCK_MACHINE   — mock knitting-machine simulator
  'mock_scale',        // PRODSIM_MOCK_SCALE     — mock digital-weighing-scale simulator
  'event_processor',   // PRODSIM_EVENT_PROCESSOR— device event validation/idempotency/ordering
  'roll_completion',   // PRODSIM_ROLL_COMPLETION— roll-completion automation (pending→weight→finalise)
];

function envFlags() {
  const set = new Set();
  const all = (process.env.PRODSIM || '').toLowerCase().trim();
  if (all === 'all') return new Set(FLAGS);
  all.split(',').map((s) => s.trim()).filter(Boolean).forEach((f) => set.add(f));
  for (const f of FLAGS) {
    const v = process.env[`PRODSIM_${f.toUpperCase()}`];
    if (v && /^(1|on|true|yes)$/i.test(v)) set.add(f);
  }
  return set;
}

// override: Set | string[] | { flag: boolean } | 'all' | undefined
function isEnabled(flag, override) {
  if (override !== undefined && override !== null) {
    if (override === 'all') return true;
    if (override instanceof Set) return override.has(flag);
    if (Array.isArray(override)) return override.includes(flag);
    if (typeof override === 'object') return !!override[flag];
  }
  return envFlags().has(flag);
}

module.exports = { FLAGS, envFlags, isEnabled };
