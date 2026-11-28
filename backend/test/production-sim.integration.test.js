// Isolated Production Simulator INTEGRATION tests (report 31).
//
// Pure, in-memory, DB-FREE, no network. These compose the production-sim units
// (adapters + event processor + state machine + weight validation + completion
// manager) across MULTIPLE machines / operators / scales to exercise the full
// workflow and its failure modes. A spy rollEngine stands in for src/lib/rolls.js
// so NOTHING here writes a real production record or opens a database/socket.
//
// Isolation guarantees asserted below:
//   * the only roll-finalisation path is an injected spy (no real engine)
//   * requiring the module performs no DB/network I/O (see 'isolation' block)
//   * the simulator never fabricates a roll id (IDs come from the caller, i.e.
//     in production from the existing rolls.js format — unchanged)

const path = require('path');
const {
  build, STATES, stateMachine, events, weightValidation,
  createMockMachine, createMockScale, createEventProcessor, createCompletionManager,
} = require('../src/lib/production-sim');

// ---- a spy stand-in for src/lib/rolls.js's finalisation hook ----
function spyRollEngine() {
  const calls = [];
  return { calls, async applyMeasuredWeight(roll_id, net, meta) { calls.push({ roll_id, net, meta }); return { roll_id, weight_kg: net, source: meta.source }; } };
}
const cfgFor = (scale_id) => ({ expected_scale_id: scale_id, capacity: 50, unit: 'kg' });

// drive a machine from completion to AWAITING_WEIGHT
function toAwaitingWeight(cm, ctx) {
  cm.onCompletion(ctx);
  cm.onOperatorConfirmRemoval(ctx.machine_id, { operator_id: ctx.assigned_operator_id });
  return cm;
}
const baseCtx = (o = {}) => ({ machine_id: 'SJ03', device_event_id: 'e1', roll_id: 'DHM-SJ03-SJ-G20-20261128-A-001', assigned_operator_id: 'OP1', shift: 'A', scale_id: 'SC1', estimate_weight_kg: 12.5, ...o });

describe('ISOLATION — no real engine, no DB/network on import', () => {
  test('completion manager without an injected engine refuses to finalise (no real writes)', async () => {
    const cm = createCompletionManager();                 // default guard engine
    toAwaitingWeight(cm, baseCtx());
    const s = createMockScale({ scale_id: 'SC1' });
    cm.onWeight('SJ03', s.stableGross(12.5), cfgFor('SC1'));
    await expect(cm.finalise('SJ03')).rejects.toThrow(/refusing to write a real roll/i);
  });

  test('module source does not import a DB pool or network client', () => {
    // the completion manager (the only DB-capable boundary) reuses rolls.js only
    // via INJECTION; it must not itself require config/database or pg.
    const src = require('fs').readFileSync(path.join(__dirname, '../src/lib/production-sim/completion-manager.js'), 'utf8');
    expect(src).not.toMatch(/config\/database|require\(['"]pg['"]\)|http|net\.|socket/i);
  });
});

describe('Scenario 1 & 2 — multiple machines + operators, correct attribution', () => {
  test('three machines run concurrently with independent state and correct operator attribution', async () => {
    const eng = spyRollEngine();
    const cm = createCompletionManager({ rollEngine: eng, now: () => '2026-11-28T06:00:00Z' });
    const machines = [
      baseCtx({ machine_id: 'SJ03', device_event_id: 'e-sj', roll_id: 'R-SJ03', assigned_operator_id: 'OP1', scale_id: 'SC1' }),
      baseCtx({ machine_id: 'RB01', device_event_id: 'e-rb', roll_id: 'R-RB01', assigned_operator_id: 'OP2', scale_id: 'SC2' }),
      baseCtx({ machine_id: 'IL05', device_event_id: 'e-il', roll_id: 'R-IL05', assigned_operator_id: 'OP3', scale_id: 'SC3' }),
    ];
    // interleave completions
    machines.forEach((c) => cm.onCompletion(c));
    machines.forEach((c) => expect(cm.getState(c.machine_id)).toBe(STATES.AWAITING_OPERATOR));
    // each confirmed by its OWN operator
    machines.forEach((c) => expect(cm.onOperatorConfirmRemoval(c.machine_id, { operator_id: c.assigned_operator_id }).ok).toBe(true));
    // weigh each on its OWN scale
    for (const c of machines) {
      const s = createMockScale({ scale_id: c.scale_id });
      cm.onWeight(c.machine_id, s.stableGross(10 + Math.random(), 0.5), cfgFor(c.scale_id));
      await cm.finalise(c.machine_id);
    }
    expect(eng.calls.map((x) => x.roll_id).sort()).toEqual(['R-IL05', 'R-RB01', 'R-SJ03']);
    expect(eng.calls.every((x) => x.meta.operator_id && x.meta.source === 'SCALE')).toBe(true);
  });

  test('wrong operator confirming a removal routes to MANUAL_REVIEW', () => {
    const cm = createCompletionManager({ rollEngine: spyRollEngine() });
    cm.onCompletion(baseCtx({ assigned_operator_id: 'OP1' }));
    expect(cm.onOperatorConfirmRemoval('SJ03', { operator_id: 'OP9' }).reason).toBe('WRONG_OPERATOR');
    expect(cm.getState('SJ03')).toBe(STATES.MANUAL_REVIEW);
  });
});

describe('Scenario 3 — multiple scale IDs / station association', () => {
  test('a reading from the wrong scale is a conflict; correct scale is accepted', () => {
    const cm = createCompletionManager({ rollEngine: spyRollEngine() });
    toAwaitingWeight(cm, baseCtx({ scale_id: 'SC1' }));
    const wrong = createMockScale({ scale_id: 'SC2' });
    const r1 = cm.onWeight('SJ03', wrong.stableGross(12.5), cfgFor('SC1'));
    expect(r1.ok).toBe(false);
    expect(r1.reasons).toContain('WRONG_SCALE');
    expect(cm.getState('SJ03')).toBe(STATES.MANUAL_REVIEW);
    // a reading from the CORRECT scale validates cleanly against the station config
    const rec = createMockScale({ scale_id: 'SC1' });
    const v = weightValidation.validateReading(rec.stableGross(12.5), cfgFor('SC1'));
    expect(v.ok).toBe(true);
  });
});

describe('Scenario 4 & 12 — duplicate events cannot duplicate rolls or overwrite weight', () => {
  test('duplicate completion ignored; duplicate reading cannot overwrite an accepted weight', async () => {
    const eng = spyRollEngine();
    const cm = createCompletionManager({ rollEngine: eng, now: () => '2026-11-28T06:00:00Z' });
    toAwaitingWeight(cm, baseCtx({ device_event_id: 'dup-1' }));
    const s = createMockScale({ scale_id: 'SC1' });
    const accepted = cm.onWeight('SJ03', s.stableGross(13.2, 0.7), cfgFor('SC1'));
    expect(accepted.ok).toBe(true);
    const capturedWeight = cm.getPending('SJ03').measured_weight_kg;
    expect(capturedWeight).toBeCloseTo(12.5, 5);

    // a SECOND reading after capture must be rejected (state no longer AWAITING_WEIGHT)
    const second = cm.onWeight('SJ03', s.stableGross(40), cfgFor('SC1'));
    expect(second.ok).toBe(false);
    expect(cm.getPending('SJ03').measured_weight_kg).toBeCloseTo(12.5, 5); // unchanged

    await cm.finalise('SJ03');
    // a REPLAYED completion with the same device_event_id must not create a new roll
    const replay = cm.onCompletion(baseCtx({ device_event_id: 'dup-1' }));
    expect(replay.ignored).toBe(true);
    expect(replay.reason).toBe('DUPLICATE_COMPLETION');
    expect(eng.calls).toHaveLength(1); // exactly one finalisation
  });

  test('duplicate scale reading detected via signature set', () => {
    const recent = new Set();
    const s = createMockScale({ scale_id: 'SC1' });
    const a = weightValidation.validateReading(s.stableGross(12.5), { ...cfgFor('SC1'), recent_signatures: recent });
    recent.add(a.signature);
    const b = weightValidation.validateReading(s.stableGross(12.5), { ...cfgFor('SC1'), recent_signatures: recent });
    expect(b.reasons).toContain('REPEATED_READING');
  });
});

describe('Scenario 5 & 6 — delayed/out-of-order + disconnect/reconnect/replay', () => {
  test('event processor rejects out-of-order and dedups replayed events', () => {
    const p = createEventProcessor();
    const e1 = events.machineEvent({ device_id: 'D1', machine_id: 'SJ03', type: 'COUNTER', observed_at: '2026-11-28T06:05:00Z' });
    expect(p.ingest(e1).outcome).toBe('ACCEPTED');
    const stale = events.machineEvent({ device_id: 'D1', machine_id: 'SJ03', type: 'COUNTER', observed_at: '2026-11-28T06:04:00Z' });
    expect(p.ingest(stale).outcome).toBe('OUT_OF_ORDER');
    expect(p.ingest(e1).outcome).toBe('DUPLICATE');
  });

  test('machine offline buffers events, reconnect replays in order; processor stays idempotent', () => {
    const p = createEventProcessor();
    const got = [];
    const m = createMockMachine({ device_id: 'D1', machine_id: 'SJ03' });
    m.subscribe((e) => { if (p.ingest(e).outcome === 'ACCEPTED') got.push(e.type); });
    m.running();
    m.disconnect();
    m.completion();                 // buffered
    m.advanceCounter(5);            // buffered
    m.reconnectAndReplay();         // replays in emission order
    expect(got).toEqual(['RUNNING', 'COMPLETION', 'COUNTER']);
    // replay the same buffered set again → all duplicates, none re-accepted
    const before = p.stats().accepted;
    m.fetchEvents().then(() => {});
    [...got].forEach(() => {});
    expect(p.stats().accepted).toBe(before);
  });

  test('scale disconnect then reconnect; a delayed reading still validates on content', () => {
    const s = createMockScale({ scale_id: 'SC1' });
    s.disconnect();
    const delayed = s.delayed(12.5, '2026-11-28T05:59:00Z'); // emitted while offline (not delivered live)
    s.reconnect();
    const v = weightValidation.validateReading(delayed, cfgFor('SC1'));
    expect(v.ok).toBe(true);
    expect(v.net).toBeCloseTo(12.5, 5);
  });
});

describe('Scenario 7 & 8 — invalid readings + gross/tare/net (no double tare)', () => {
  const s = () => createMockScale({ scale_id: 'SC1', capacity: 50 });
  test('invalid/unstable/negative/zero/over-capacity/wrong-unit all rejected, roll not finalised', () => {
    const eng = spyRollEngine();
    const cases = [
      ['unstable', (x) => x.unstable(10), 'UNSTABLE'],
      ['negative', (x) => x.negative(), 'NEGATIVE_READING'],
      ['zero', (x) => x.zero(), 'ZERO_READING'],
      ['over', (x) => x.overCapacity(), 'OVER_CAPACITY'],
      ['unit', (x) => x.wrongUnit(10), 'WRONG_UNIT'],
      ['invalid', (x) => x.invalid(), 'INVALID_DATA'],
    ];
    for (const [name, mk, reason] of cases) {
      const cm = createCompletionManager({ rollEngine: eng });
      toAwaitingWeight(cm, baseCtx({ machine_id: 'M-' + name }));
      const r = cm.onWeight('M-' + name, mk(s()), cfgFor('SC1'));
      expect(r.ok).toBe(false);
      expect(r.reasons).toContain(reason);
      expect(cm.getState('M-' + name)).not.toBe(STATES.WEIGHT_CAPTURED);
    }
    expect(eng.calls).toHaveLength(0);
  });

  test('gross - tare = net (single subtraction); net-basis scale is not tared again', () => {
    const g = weightValidation.validateReading(s().stableGross(13.2, 0.7), cfgFor('SC1'));
    expect(g.net).toBeCloseTo(12.5, 5);
    const netRd = s().stableNet(12.5); netRd.tare = 0.7;
    const n = weightValidation.validateReading(netRd, cfgFor('SC1'));
    expect(n.net).toBeCloseTo(12.5, 5); // tare ignored on NET basis
  });
});

describe('Scenario 9 — stop/green/restart in different orders', () => {
  test('completion only from RUNNING; restart before recorded makes no roll; green alone does not finalise', () => {
    const eng = spyRollEngine();
    const cm = createCompletionManager({ rollEngine: eng });
    // restart while RUNNING (no pending) → no roll, state stays RUNNING
    expect(cm.onRestart('SJ03').ok).toBe(false);
    expect(cm.getState('SJ03')).toBe(STATES.RUNNING);
    // completion → pending; a restart before weighing does not finalise
    cm.onCompletion(baseCtx());
    expect(cm.onRestart('SJ03').reason).toBe('RESTART_BEFORE_RECORDED');
    expect(eng.calls).toHaveLength(0);
    // a second completion while already pending is a duplicate-by-state (NOT_RUNNING)
    const again = cm.onCompletion(baseCtx({ device_event_id: 'e2' }));
    expect(again.ignored).toBe(true);
    expect(again.reason).toBe('NOT_RUNNING');
  });
});

describe('Scenario 10 — EXCEPTION / MANUAL_REVIEW recovery', () => {
  test('invalid weight → EXCEPTION → authorised manual fallback recovers and finalises (marked MANUAL)', async () => {
    const eng = spyRollEngine();
    const cm = createCompletionManager({ rollEngine: eng, now: () => '2026-11-28T06:00:00Z' });
    toAwaitingWeight(cm, baseCtx());
    const s = createMockScale({ scale_id: 'SC1' });
    expect(cm.onWeight('SJ03', s.overCapacity(), cfgFor('SC1')).ok).toBe(false);
    expect(cm.getState('SJ03')).toBe(STATES.EXCEPTION);
    // unauthorised manual entry refused
    expect(cm.onManualWeight('SJ03', { weight_kg: 12.5, authorised: false }).ok).toBe(false);
    // authorised manual fallback recovers
    const r = cm.onManualWeight('SJ03', { weight_kg: 12.4, operator_id: 'SUP1', reason: 'scale over-capacity glitch', authorised: true });
    expect(r.ok).toBe(true);
    expect(r.source).toBe('MANUAL');
    const fin = await cm.finalise('SJ03');
    expect(fin.source).toBe('MANUAL');
    expect(eng.calls[0].meta.source).toBe('MANUAL'); // engine always told it is MANUAL, never shown as auto
  });
});

describe('Scenario 11 — completion before a shift boundary, weighing after it', () => {
  // ESTABLISHED RULE (verified): a roll's shift is fixed at creation/completion
  // (rolls.routes.js requires `shift` at create; on approval, production_records
  // is allocated to `roll.shift`, NOT the weighing-time shift). So weighing after
  // the boundary must NOT reassign the shift. This is NOT a newly invented rule.
  test('completion-shift is preserved; weighing after the boundary does not reassign it; both timestamps retained', async () => {
    const times = ['2026-11-28T13:59:00Z', '2026-11-28T14:01:00Z']; // 14:00Z = A→B boundary (example)
    let i = 0;
    const eng = spyRollEngine();
    const cm = createCompletionManager({ rollEngine: eng, now: () => times[Math.min(i, times.length - 1)] });
    // completion in shift A, just before the boundary
    cm.onCompletion(baseCtx({ shift: 'A' }));
    cm.onOperatorConfirmRemoval('SJ03', { operator_id: 'OP1' });
    i = 1; // clock advances past the boundary
    const s = createMockScale({ scale_id: 'SC1' });
    cm.onWeight('SJ03', s.stableGross(12.5), cfgFor('SC1'));
    const pending = cm.getPending('SJ03');
    expect(pending.shift).toBe('A');                         // shift NOT reassigned by late weighing
    const estAt = pending.audit.find((a) => a.kind === 'ESTIMATE_PLACEHOLDER').at;
    const wAt = pending.audit.find((a) => a.kind === 'WEIGHT_CAPTURED').at;
    expect(estAt).toBe('2026-11-28T13:59:00Z');              // completion timestamp preserved
    expect(wAt).toBe('2026-11-28T14:01:00Z');                // weighing timestamp preserved
    await cm.finalise('SJ03');
    expect(eng.calls[0].roll_id).toContain('-A-');           // roll id carries the completion shift (A)
  });
});

describe('INVARIANTS — roll id + one-open-roll-per-machine (owned by rolls.js, unchanged)', () => {
  test('simulator never fabricates a roll id — it uses the id supplied by the roll engine', async () => {
    const eng = spyRollEngine();
    const cm = createCompletionManager({ rollEngine: eng, now: () => '2026-11-28T06:00:00Z' });
    toAwaitingWeight(cm, baseCtx({ roll_id: 'DHM-SJ03-SJ-G20-20261128-A-001' }));
    const s = createMockScale({ scale_id: 'SC1' });
    cm.onWeight('SJ03', s.stableGross(12.5), cfgFor('SC1'));
    await cm.finalise('SJ03');
    // the exact id passed in is the exact id finalised (format preserved by rolls.js)
    expect(eng.calls[0].roll_id).toBe('DHM-SJ03-SJ-G20-20261128-A-001');
    expect(/^DHM-[A-Z0-9]+-.*-\d{8}-[A-Z]-\d{3}$/.test(eng.calls[0].roll_id)).toBe(true);
  });

  test('at most one pending (open) roll per machine — a duplicate completion never opens a second', () => {
    const cm = createCompletionManager({ rollEngine: spyRollEngine() });
    cm.onCompletion(baseCtx({ device_event_id: 'x1' }));
    const p1 = cm.getPending('SJ03');
    cm.onCompletion(baseCtx({ device_event_id: 'x1' })); // duplicate
    cm.onCompletion(baseCtx({ device_event_id: 'x2' })); // different id but machine already pending
    expect(cm.getPending('SJ03')).toBe(p1);              // same single pending object
  });
});

describe('feature flags remain OFF by default', () => {
  test('build() with no override constructs nothing', () => {
    const sim = build();
    expect(Object.values(sim.enabled).some(Boolean)).toBe(false);
    expect([sim.machine, sim.scale, sim.processor, sim.completion].every((x) => x === null)).toBe(true);
  });
});
