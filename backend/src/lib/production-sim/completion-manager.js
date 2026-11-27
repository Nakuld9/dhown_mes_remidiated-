// Roll Completion Manager (report 29 §C/§E). Drives the state machine, owns the
// pending-roll lifecycle, and attaches the measured scale weight to the roll as
// an AUDITABLE CORRECTION that preserves the original estimated placeholder.
//
// Reuse, not duplication: this manager does NOT generate roll IDs or re-implement
// the roll engine. The existing auto-doff (src/lib/rolls.js closeOpenRoll) already
// closes the open roll with an ESTIMATED weight; this manager only (a) tracks the
// pending weighing step and (b) applies the real measured weight through an
// injected rollEngine.applyMeasuredWeight(roll_id, net, meta). The engine is
// injected so the manager is DB-free and unit-testable; in a flagged DB wiring
// the engine would wrap rolls.js. With flags OFF nothing here runs.
//
// Safety: a STOP alone never opens a pending roll (only COMPLETION does); a
// RESTART never finalises or creates a roll; duplicate COMPLETION (same device
// event) never creates a second pending roll; an invalid/incomplete weighing
// never finalises; manual weight is always marked MANUAL and needs authorisation.

const sm = require('./state-machine');
const { validateReading } = require('./weight-validation');

function createCompletionManager(deps = {}) {
  const rollEngine = deps.rollEngine || defaultGuardEngine();
  const now = deps.now || (() => new Date().toISOString());
  const sessions = new Map();     // machine_id -> session
  const seenCompletions = new Set(); // device_event_id -> dedup

  function session(machine_id) {
    if (!sessions.has(machine_id)) {
      sessions.set(machine_id, { machine_id, state: sm.STATES.RUNNING, pending: null, history: [] });
    }
    return sessions.get(machine_id);
  }

  function transition(s, event, note) {
    const to = sm.next(s.state, event);
    s.history.push({ at: now(), event, from: s.state, to, note: note || null });
    s.state = to;
    return to;
  }

  // ---- machine completion (stop + green light = a doff) ----
  // ctx: { device_event_id, roll_id, operator_id, shift, scale_id, assigned_operator_id,
  //        estimate_weight_kg }
  function onCompletion(ctx = {}) {
    const s = session(ctx.machine_id);
    // duplicate completion -> no second pending roll
    if (ctx.device_event_id && seenCompletions.has(ctx.device_event_id)) {
      return { ignored: true, reason: 'DUPLICATE_COMPLETION', state: s.state, pending: s.pending };
    }
    if (!sm.canTransition(s.state, 'completion')) {
      return { ignored: true, reason: 'NOT_RUNNING', state: s.state, pending: s.pending };
    }
    if (ctx.device_event_id) seenCompletions.add(ctx.device_event_id);
    transition(s, 'completion', `completion evt=${ctx.device_event_id || '-'}`);
    s.pending = {
      pending_id: `pend_${ctx.machine_id}_${seenCompletions.size}`,
      roll_id: ctx.roll_id || null,         // the roll the auto-doff already created/closed
      machine_id: ctx.machine_id,
      device_event_id: ctx.device_event_id || null,
      assigned_operator_id: ctx.assigned_operator_id ?? ctx.operator_id ?? null,
      operator_id: null,
      shift: ctx.shift || null,
      scale_id: ctx.scale_id || null,
      estimate_weight_kg: num(ctx.estimate_weight_kg),
      measured_weight_kg: null,
      weight_source: null,
      weight_confirmed: false,
      exceptions: [],
      audit: [{ at: now(), kind: 'ESTIMATE_PLACEHOLDER', weight_kg: num(ctx.estimate_weight_kg) }],
    };
    transition(s, 'pending_created');
    return { ignored: false, state: s.state, pending: s.pending };
  }

  // ---- operator confirms physical roll removal (REQUIRED) ----
  function onOperatorConfirmRemoval(machine_id, { operator_id } = {}) {
    const s = session(machine_id);
    if (s.state !== sm.STATES.AWAITING_OPERATOR) {
      return reject(s, 'NOT_AWAITING_OPERATOR');
    }
    if (s.pending.assigned_operator_id && operator_id && operator_id !== s.pending.assigned_operator_id) {
      s.pending.exceptions.push('WRONG_OPERATOR');
      transition(s, 'manual_review', `wrong operator ${operator_id}`);
      return { ok: false, reason: 'WRONG_OPERATOR', state: s.state };
    }
    s.pending.operator_id = operator_id || s.pending.assigned_operator_id || null;
    transition(s, 'operator_confirm_removal');
    return { ok: true, state: s.state };
  }

  // ---- a scale reading arrives for the pending roll ----
  // cfg is passed to validateReading (capacity/unit/limits/expected_scale_id...)
  function onWeight(machine_id, reading, cfg = {}) {
    const s = session(machine_id);
    if (s.state !== sm.STATES.AWAITING_WEIGHT) return reject(s, 'NOT_AWAITING_WEIGHT');

    const v = validateReading(reading, cfg);
    s.pending.audit.push({ at: now(), kind: 'SCALE_READING', reading_id: reading.reading_id, net: v.net, reasons: v.reasons });

    if (!v.ok) {
      s.pending.exceptions.push(...v.reasons);
      transition(s, v.is_conflict ? 'manual_review' : 'exception', v.reasons.join(','));
      return { ok: false, reasons: v.reasons, state: s.state };
    }
    if (v.requires_operator_confirmation && !reading.operator_confirmed) {
      // valid but no stability flag → hold for operator confirmation (not an error)
      return { ok: false, reason: 'AWAITING_OPERATOR_CONFIRMATION', net: v.net, state: s.state };
    }
    // attach measured weight (auditable correction; estimate preserved above)
    s.pending.measured_weight_kg = v.net;
    s.pending.weight_source = 'SCALE';
    s.pending.scale_id = reading.scale_id;
    s.pending.audit.push({ at: now(), kind: 'WEIGHT_CAPTURED', weight_kg: v.net, source: 'SCALE', scale_id: reading.scale_id });
    transition(s, 'weight_valid');
    return { ok: true, net: v.net, state: s.state };
  }

  // ---- authorised manual fallback (scale unavailable) ----
  function onManualWeight(machine_id, { weight_kg, operator_id, reason, authorised } = {}) {
    const s = session(machine_id);
    if (s.state !== sm.STATES.AWAITING_WEIGHT && s.state !== sm.STATES.EXCEPTION) return reject(s, 'NOT_AWAITING_WEIGHT');
    if (!authorised) return { ok: false, reason: 'NOT_AUTHORISED', state: s.state };
    const w = num(weight_kg);
    if (w == null || w <= 0) return { ok: false, reason: 'INVALID_MANUAL_WEIGHT', state: s.state };
    if (s.state === sm.STATES.EXCEPTION) transition(s, 'recover_to_weight', 'manual fallback');
    s.pending.measured_weight_kg = w;
    s.pending.weight_source = 'MANUAL';           // ALWAYS distinguishable from SCALE
    s.pending.audit.push({ at: now(), kind: 'MANUAL_WEIGHT', weight_kg: w, source: 'MANUAL', by: operator_id || null, reason: reason || null });
    transition(s, 'weight_valid');
    return { ok: true, net: w, source: 'MANUAL', state: s.state };
  }

  // ---- finalise: write measured weight to the roll (auditable correction) ----
  async function finalise(machine_id) {
    const s = session(machine_id);
    if (s.state !== sm.STATES.WEIGHT_CAPTURED) return reject(s, 'NOT_WEIGHT_CAPTURED');
    const p = s.pending;
    // reuse the roll engine; it is responsible for preserving the estimate in
    // audit history and writing the measured weight + source.
    const result = await rollEngine.applyMeasuredWeight(p.roll_id, p.measured_weight_kg, {
      source: p.weight_source,
      scale_id: p.scale_id,
      operator_id: p.operator_id,
      estimate_weight_kg: p.estimate_weight_kg,
      device_event_id: p.device_event_id,
    });
    p.audit.push({ at: now(), kind: 'ROLL_FINALISED', roll_id: p.roll_id, weight_kg: p.measured_weight_kg, source: p.weight_source });
    transition(s, 'finalise');
    return { ok: true, state: s.state, roll_id: p.roll_id, weight_kg: p.measured_weight_kg, source: p.weight_source, engine: result };
  }

  // ---- machine restart ----
  function onRestart(machine_id) {
    const s = session(machine_id);
    if (s.state === sm.STATES.ROLL_RECORDED) {
      transition(s, 'restart');
      transition(s, 'resume_running');
      const finished = s.pending;
      s.pending = null;                 // ready for the next cycle
      return { ok: true, state: s.state, recorded_roll: finished && finished.roll_id };
    }
    // restart before the roll is recorded must NOT create or finalise a roll
    s.history.push({ at: now(), event: 'restart_ignored', from: s.state, to: s.state, note: 'restart before ROLL_RECORDED — pending preserved' });
    return { ok: false, reason: 'RESTART_BEFORE_RECORDED', state: s.state, pending_preserved: !!s.pending };
  }

  function reject(s, reason) { return { ok: false, reason, state: s.state }; }
  function getState(machine_id) { return session(machine_id).state; }
  function getPending(machine_id) { return session(machine_id).pending; }
  function getHistory(machine_id) { return session(machine_id).history.slice(); }

  return { onCompletion, onOperatorConfirmRemoval, onWeight, onManualWeight, finalise, onRestart, getState, getPending, getHistory, sessions };
}

// Default engine REFUSES to touch real data — guarantees a mock event can never
// create a real production record unless a real engine is explicitly injected.
function defaultGuardEngine() {
  return {
    async applyMeasuredWeight() {
      throw new Error('production-sim: no rollEngine injected — refusing to write a real roll from a mock/unwired context');
    },
  };
}

function num(v) {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

module.exports = { createCompletionManager, defaultGuardEngine };
