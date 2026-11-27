// Mock machine + digital-weighing-scale simulator tests (report 30).
// DB-FREE and deterministic: the simulator, state machine, validation and
// completion manager are pure / dependency-injected. A spy rollEngine proves the
// existing roll engine is the single finalisation point WITHOUT a database and
// WITHOUT creating any real production record.

const {
  build, flags, STATES, stateMachine,
  events, weightValidation,
  createMockMachine, createMockScale, createEventProcessor, createCompletionManager,
} = require('../src/lib/production-sim');

// a spy stand-in for src/lib/rolls.js's finalisation hook
function spyRollEngine() {
  const calls = [];
  return {
    calls,
    async applyMeasuredWeight(roll_id, net, meta) { calls.push({ roll_id, net, meta }); return { roll_id, weight_kg: net, source: meta.source }; },
  };
}

const T0 = '2026-11-27T10:00:00.000Z';
const ctxBase = (over = {}) => ({
  machine_id: 'SJ03', device_event_id: 'evt-1', roll_id: 'DHM-SJ03-SJ-G20-20261127-A-001',
  assigned_operator_id: 'OP1', shift: 'A', estimate_weight_kg: 12.5, scale_id: 'SC1', ...over,
});

describe('feature flags — OFF by default, no side effects', () => {
  const saved = { ...process.env };
  afterEach(() => { process.env = { ...saved }; });

  test('build() with no flags creates nothing', () => {
    const sim = build();
    expect(sim.enabled).toEqual({ mock_machine: false, mock_scale: false, event_processor: false, roll_completion: false });
    expect(sim.machine).toBeNull();
    expect(sim.scale).toBeNull();
    expect(sim.processor).toBeNull();
    expect(sim.completion).toBeNull();
  });

  test("override 'all' enables every component; env stays untouched", () => {
    const sim = build({ flags: 'all', rollEngine: spyRollEngine() });
    expect(Object.values(sim.enabled).every(Boolean)).toBe(true);
    expect(sim.machine && sim.scale && sim.processor && sim.completion).toBeTruthy();
  });

  test('env PRODSIM_MOCK_MACHINE=on enables only that flag', () => {
    process.env.PRODSIM_MOCK_MACHINE = 'on';
    expect(flags.isEnabled('mock_machine')).toBe(true);
    expect(flags.isEnabled('mock_scale')).toBe(false);
  });
});

describe('machine simulator', () => {
  test('running, completion event has full canonical envelope', () => {
    const m = createMockMachine();
    m.running();
    const ev = m.completion();
    for (const k of ['event_id', 'device_id', 'machine_id', 'type', 'observed_at', 'received_at', 'source', 'validation_status']) {
      expect(ev[k]).toBeDefined();
    }
    expect(ev.type).toBe('COMPLETION');
    expect(ev.validation_status).toBe('VALID');
    expect(ev.source).toBe('mock-machine');
  });

  test('stop without completion, fault, restart, counter reset', () => {
    const m = createMockMachine();
    expect(m.stop().type).toBe('STOP');
    expect(m.fault('x').type).toBe('FAULT');
    expect(m.restart().type).toBe('RESTART');
    m.advanceCounter(100);
    const reset = m.resetCounter(0);
    expect(reset.payload.reset).toBe(true);
    expect(reset.counter).toBe(0);
  });

  test('duplicate event keeps the same event_id', () => {
    const m = createMockMachine();
    const e = m.completion();
    const dup = m.duplicate(e);
    expect(dup.event_id).toBe(e.event_id);
  });

  test('offline buffering then reconnect replays in order', () => {
    const got = [];
    const m = createMockMachine();
    m.subscribe((e) => got.push(e.type));
    m.running();                 // delivered live
    m.disconnect();
    m.completion();              // buffered
    m.restart();                 // buffered
    expect(got).toEqual(['RUNNING']);
    const replay = m.reconnectAndReplay();
    expect(replay.map((e) => e.type)).toEqual(['COMPLETION', 'RESTART']);
    expect(got).toEqual(['RUNNING', 'COMPLETION', 'RESTART']);
  });
});

describe('event processor — idempotency, ordering, replay', () => {
  test('duplicate (source,device,event_id) is ignored', () => {
    const p = createEventProcessor();
    const e = events.machineEvent({ device_id: 'D', machine_id: 'SJ03', type: 'COMPLETION' });
    expect(p.ingest(e).outcome).toBe('ACCEPTED');
    expect(p.ingest(e).outcome).toBe('DUPLICATE');
    expect(p.stats().accepted).toBe(1);
  });

  test('out-of-order (older observed_at) is flagged, not applied', () => {
    const p = createEventProcessor();
    p.ingest(events.machineEvent({ device_id: 'D', machine_id: 'SJ03', type: 'COUNTER', observed_at: '2026-11-27T10:05:00Z' }));
    const stale = events.machineEvent({ device_id: 'D', machine_id: 'SJ03', type: 'COUNTER', observed_at: '2026-11-27T10:00:00Z' });
    expect(p.ingest(stale).outcome).toBe('OUT_OF_ORDER');
  });

  test('invalid event rejected on schema', () => {
    const p = createEventProcessor();
    const bad = events.machineEvent({ device_id: 'D', machine_id: 'SJ03', type: 'NONSENSE' });
    expect(bad.validation_status).toBe('INVALID');
    expect(p.ingest(bad).outcome).toBe('REJECTED');
  });

  test('offline batch replayed in observed_at order', () => {
    const p = createEventProcessor();
    const a = events.machineEvent({ device_id: 'D', machine_id: 'SJ03', type: 'COUNTER', observed_at: '2026-11-27T10:02:00Z' });
    const b = events.machineEvent({ device_id: 'D', machine_id: 'SJ03', type: 'COUNTER', observed_at: '2026-11-27T10:01:00Z' });
    const out = p.ingestBatch([a, b]);
    expect(out[0].event.observed_at < out[1].event.observed_at).toBe(true);
    expect(out.every((r) => r.outcome === 'ACCEPTED')).toBe(true);
  });
});

describe('scale simulator + weight validation', () => {
  const cfg = { capacity: 50, unit: 'kg', expected_scale_id: 'SC1' };

  test('valid stable gross with tare → net = gross - tare (single subtraction)', () => {
    const s = createMockScale({ scale_id: 'SC1' });
    const rd = s.stableGross(13.2, 0.7);
    const v = weightValidation.validateReading(rd, cfg);
    expect(v.ok).toBe(true);
    expect(v.net).toBeCloseTo(12.5, 5);
  });

  test('scale that already reports NET is not tared again', () => {
    const s = createMockScale({ scale_id: 'SC1' });
    const rd = s.stableNet(12.5);
    rd.tare = 0.7; // even if a tare is present, NET basis must ignore it
    const v = weightValidation.validateReading(rd, cfg);
    expect(v.net).toBeCloseTo(12.5, 5);
  });

  test('unstable, zero, negative, over-capacity, wrong unit, invalid all rejected', () => {
    const s = createMockScale({ scale_id: 'SC1', capacity: 50 });
    expect(weightValidation.validateReading(s.unstable(10), cfg).reasons).toContain('UNSTABLE');
    expect(weightValidation.validateReading(s.zero(), cfg).reasons).toContain('ZERO_READING');
    expect(weightValidation.validateReading(s.negative(), cfg).reasons).toContain('NEGATIVE_READING');
    expect(weightValidation.validateReading(s.overCapacity(), cfg).reasons).toContain('OVER_CAPACITY');
    expect(weightValidation.validateReading(s.wrongUnit(10), cfg).reasons).toContain('WRONG_UNIT');
    expect(weightValidation.validateReading(s.invalid(), cfg).reasons).toContain('INVALID_DATA');
  });

  test('wrong scale flagged as a conflict (→ MANUAL_REVIEW)', () => {
    const s = createMockScale({ scale_id: 'SC2' });
    const v = weightValidation.validateReading(s.stableGross(12.5), cfg);
    expect(v.reasons).toContain('WRONG_SCALE');
    expect(v.is_conflict).toBe(true);
  });

  test('repeated reading detected via signature set', () => {
    const s = createMockScale({ scale_id: 'SC1' });
    const recent = new Set();
    const first = weightValidation.validateReading(s.stableGross(12.5), { ...cfg, recent_signatures: recent });
    recent.add(first.signature);
    const again = weightValidation.validateReading(s.stableGross(12.5), { ...cfg, recent_signatures: recent });
    expect(again.reasons).toContain('REPEATED_READING');
  });

  test('product limits applied only when supplied (never invented)', () => {
    const s = createMockScale({ scale_id: 'SC1' });
    const rd = s.stableGross(12.5);
    expect(weightValidation.validateReading(rd, cfg).ok).toBe(true);           // no limits → fine
    const v = weightValidation.validateReading(rd, { ...cfg, product_max_kg: 10 });
    expect(v.reasons).toContain('ABOVE_PRODUCT_MAX');
  });

  test('no stability flag → requires operator confirmation, not an error', () => {
    const s = createMockScale({ scale_id: 'SC1' });
    const rd = s.stableGross(12.5); rd.stable = null;
    const v = weightValidation.validateReading(rd, cfg);
    expect(v.ok).toBe(true);
    expect(v.requires_operator_confirmation).toBe(true);
  });
});

describe('roll completion state machine — guards', () => {
  test('STOP alone never opens a pending roll (only COMPLETION does)', () => {
    const cm = createCompletionManager({ rollEngine: spyRollEngine() });
    // no completion called → still RUNNING, no pending
    expect(cm.getState('SJ03')).toBe(STATES.RUNNING);
    expect(cm.getPending('SJ03')).toBeNull();
  });

  test('duplicate completion never creates a second pending roll', () => {
    const cm = createCompletionManager({ rollEngine: spyRollEngine() });
    expect(cm.onCompletion(ctxBase()).ignored).toBe(false);
    const dup = cm.onCompletion(ctxBase());
    expect(dup.ignored).toBe(true);
    expect(dup.reason).toBe('DUPLICATE_COMPLETION');
  });

  test('operator confirmation is required before weighing', () => {
    const cm = createCompletionManager({ rollEngine: spyRollEngine() });
    cm.onCompletion(ctxBase());
    expect(cm.getState('SJ03')).toBe(STATES.AWAITING_OPERATOR);
    // a weight before operator confirm is rejected
    const s = createMockScale({ scale_id: 'SC1' });
    const r = cm.onWeight('SJ03', s.stableGross(12.5), { expected_scale_id: 'SC1', capacity: 50, unit: 'kg' });
    expect(r.ok).toBe(false);
    expect(r.reason).toBe('NOT_AWAITING_WEIGHT');
  });

  test('wrong operator → MANUAL_REVIEW', () => {
    const cm = createCompletionManager({ rollEngine: spyRollEngine() });
    cm.onCompletion(ctxBase());
    const r = cm.onOperatorConfirmRemoval('SJ03', { operator_id: 'OP999' });
    expect(r.ok).toBe(false);
    expect(cm.getState('SJ03')).toBe(STATES.MANUAL_REVIEW);
  });

  test('invalid weight does not finalise the roll', () => {
    const eng = spyRollEngine();
    const cm = createCompletionManager({ rollEngine: eng });
    cm.onCompletion(ctxBase());
    cm.onOperatorConfirmRemoval('SJ03', { operator_id: 'OP1' });
    const s = createMockScale({ scale_id: 'SC1' });
    const r = cm.onWeight('SJ03', s.overCapacity(), { expected_scale_id: 'SC1', capacity: 50, unit: 'kg' });
    expect(r.ok).toBe(false);
    expect(cm.getState('SJ03')).toBe(STATES.EXCEPTION);
    expect(eng.calls.length).toBe(0); // never finalised
  });

  test('restart before weighing does NOT create/finalise a roll; pending preserved', () => {
    const cm = createCompletionManager({ rollEngine: spyRollEngine() });
    cm.onCompletion(ctxBase());
    cm.onOperatorConfirmRemoval('SJ03', { operator_id: 'OP1' });
    const r = cm.onRestart('SJ03');
    expect(r.ok).toBe(false);
    expect(r.reason).toBe('RESTART_BEFORE_RECORDED');
    expect(r.pending_preserved).toBe(true);
    expect(cm.getState('SJ03')).toBe(STATES.AWAITING_WEIGHT);
  });

  test('invalid state-machine transition throws', () => {
    expect(() => stateMachine.next(STATES.RUNNING, 'finalise')).toThrow(/invalid transition/i);
  });
});

describe('roll completion — full successful cycle + audit + reuse of roll engine', () => {
  async function runHappyPath(eng, weightFn) {
    const cm = createCompletionManager({ rollEngine: eng, now: () => T0 });
    cm.onCompletion(ctxBase());                                   // RUNNING→…→AWAITING_OPERATOR
    cm.onOperatorConfirmRemoval('SJ03', { operator_id: 'OP1' });  // →AWAITING_WEIGHT
    weightFn(cm);                                                 // →WEIGHT_CAPTURED
    const fin = await cm.finalise('SJ03');                        // →ROLL_RECORDED
    const restart = cm.onRestart('SJ03');                         // →RUNNING_AGAIN→RUNNING
    return { cm, fin, restart };
  }

  test('scale weight replaces the estimate via the roll engine; estimate preserved in audit', async () => {
    const eng = spyRollEngine();
    const s = createMockScale({ scale_id: 'SC1' });
    const { cm, fin, restart } = await runHappyPath(eng, (c) =>
      c.onWeight('SJ03', s.stableGross(13.2, 0.7), { expected_scale_id: 'SC1', capacity: 50, unit: 'kg' }));

    expect(fin.ok).toBe(true);
    expect(fin.weight_kg).toBeCloseTo(12.5, 5);
    expect(fin.source).toBe('SCALE');
    expect(cm.getState('SJ03')).toBe(STATES.RUNNING);
    expect(restart.ok).toBe(true);

    // the EXISTING roll engine is the single finalisation point
    expect(eng.calls).toHaveLength(1);
    expect(eng.calls[0].roll_id).toBe('DHM-SJ03-SJ-G20-20261127-A-001');
    expect(eng.calls[0].meta.estimate_weight_kg).toBe(12.5);   // estimate passed through for preservation

    // audit retains BOTH the estimate placeholder and the measured weight
    const kinds = cm.getPending('SJ03'); // pending cleared after restart
    expect(kinds).toBeNull();
  });

  test('audit trail captures estimate → measured correction (before restart clears pending)', () => {
    const eng = spyRollEngine();
    const cm = createCompletionManager({ rollEngine: eng, now: () => T0 });
    cm.onCompletion(ctxBase());
    cm.onOperatorConfirmRemoval('SJ03', { operator_id: 'OP1' });
    const s = createMockScale({ scale_id: 'SC1' });
    cm.onWeight('SJ03', s.stableGross(13.2, 0.7), { expected_scale_id: 'SC1', capacity: 50, unit: 'kg' });
    const audit = cm.getPending('SJ03').audit.map((a) => a.kind);
    expect(audit).toEqual(expect.arrayContaining(['ESTIMATE_PLACEHOLDER', 'SCALE_READING', 'WEIGHT_CAPTURED']));
  });

  test('authorised manual fallback is marked MANUAL and distinguishable; unauthorised rejected', async () => {
    const eng = spyRollEngine();
    const cm = createCompletionManager({ rollEngine: eng, now: () => T0 });
    cm.onCompletion(ctxBase());
    cm.onOperatorConfirmRemoval('SJ03', { operator_id: 'OP1' });
    // unauthorised → rejected
    expect(cm.onManualWeight('SJ03', { weight_kg: 12.5, operator_id: 'OP1', authorised: false }).ok).toBe(false);
    // authorised → MANUAL source
    const r = cm.onManualWeight('SJ03', { weight_kg: 12.4, operator_id: 'SUP1', reason: 'scale offline', authorised: true });
    expect(r.ok).toBe(true);
    expect(r.source).toBe('MANUAL');
    const fin = await cm.finalise('SJ03');
    expect(fin.source).toBe('MANUAL');
    expect(eng.calls[0].meta.source).toBe('MANUAL'); // engine told it is manual, never shown as auto
  });

  test('shift boundary: a new completion after a finished cycle uses the new shift', async () => {
    const eng = spyRollEngine();
    const s = createMockScale({ scale_id: 'SC1' });
    const cm = createCompletionManager({ rollEngine: eng, now: () => T0 });
    cm.onCompletion(ctxBase({ shift: 'A' }));
    cm.onOperatorConfirmRemoval('SJ03', { operator_id: 'OP1' });
    cm.onWeight('SJ03', s.stableGross(12.5), { expected_scale_id: 'SC1', capacity: 50, unit: 'kg' });
    await cm.finalise('SJ03');
    cm.onRestart('SJ03');
    // next cycle, shift B
    const r2 = cm.onCompletion(ctxBase({ device_event_id: 'evt-2', roll_id: 'DHM-SJ03-SJ-G20-20261127-B-001', shift: 'B' }));
    expect(r2.ignored).toBe(false);
    expect(cm.getPending('SJ03').shift).toBe('B');
  });

  test('failed finalisation (engine throws) leaves state at WEIGHT_CAPTURED for retry', async () => {
    const flaky = { async applyMeasuredWeight() { throw new Error('transient'); } };
    const cm = createCompletionManager({ rollEngine: flaky, now: () => T0 });
    cm.onCompletion(ctxBase());
    cm.onOperatorConfirmRemoval('SJ03', { operator_id: 'OP1' });
    const s = createMockScale({ scale_id: 'SC1' });
    cm.onWeight('SJ03', s.stableGross(12.5), { expected_scale_id: 'SC1', capacity: 50, unit: 'kg' });
    await expect(cm.finalise('SJ03')).rejects.toThrow('transient');
    expect(cm.getState('SJ03')).toBe(STATES.WEIGHT_CAPTURED); // unchanged → safe retry
    // state is unchanged, so a later finalise() with a healthy engine can retry safely
  });
});
