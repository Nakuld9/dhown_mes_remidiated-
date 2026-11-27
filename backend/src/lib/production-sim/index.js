// Production-simulation module entrypoint (report 29 / mock-first).
//
// IMPORTANT SAFETY PROPERTIES:
//   * This module is NOT required by server.js and is NOT wired into boot.
//     Importing it has ZERO side effects: no DB, no network, no scheduler.
//   * Every capability is gated by a flag that is OFF BY DEFAULT (flags.js).
//     With flags OFF, build() returns an inert facade that creates nothing.
//   * There is NO real-machine / real-scale / vendor-cloud / BUSY code path here.
//     The only connectors are the in-memory mocks. Turning flags ON enables the
//     SIMULATOR only.
//   * The completion manager writes a real roll ONLY if a real rollEngine is
//     explicitly injected; otherwise it refuses (defaultGuardEngine). A mock
//     event can never create a real production record on its own.
//
// Build a wired set of components for tests or a future flagged pilot:
//   const sim = require('./lib/production-sim').build({ flags: 'all', rollEngine });

const flags = require('./flags');
const sm = require('./state-machine');
const events = require('./events');
const weightValidation = require('./weight-validation');
const { createMockMachine } = require('./adapters/mock-machine');
const { createMockScale } = require('./adapters/mock-scale');
const { createEventProcessor } = require('./event-processor');
const { createCompletionManager } = require('./completion-manager');

function build(opts = {}) {
  const override = opts.flags; // Set|array|{flag:bool}|'all'|undefined → env/OFF
  const on = (f) => flags.isEnabled(f, override);

  const facade = {
    enabled: {
      mock_machine: on('mock_machine'),
      mock_scale: on('mock_scale'),
      event_processor: on('event_processor'),
      roll_completion: on('roll_completion'),
    },
    machine: null,
    scale: null,
    processor: null,
    completion: null,
  };

  if (facade.enabled.mock_machine) facade.machine = createMockMachine(opts.machine || {});
  if (facade.enabled.mock_scale) facade.scale = createMockScale(opts.scale || {});
  if (facade.enabled.event_processor) facade.processor = createEventProcessor(opts.processor || {});
  if (facade.enabled.roll_completion) {
    facade.completion = createCompletionManager({ rollEngine: opts.rollEngine, now: opts.now });
  }
  return facade;
}

module.exports = {
  build,
  flags,
  STATES: sm.STATES,
  stateMachine: sm,
  events,
  weightValidation,
  createMockMachine,
  createMockScale,
  createEventProcessor,
  createCompletionManager,
};
