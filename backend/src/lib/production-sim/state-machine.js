// Roll-completion state machine (approved in report 29).
//
// Pure, deterministic, NO database and NO side effects. It only answers
// "is this transition allowed?" and "what is the next state?". The caller
// (completion-manager) owns persistence and the roll-engine integration.
//
// States:
//   RUNNING           machine producing; open roll accumulating counter
//   COMPLETION_PENDING machine stop + green-light observed (a doff)
//   AWAITING_OPERATOR  pending roll created; waiting for operator to confirm removal
//   AWAITING_WEIGHT    operator confirmed removal; waiting for a valid scale weight
//   WEIGHT_CAPTURED    a valid (stable, validated) weight is attached
//   ROLL_RECORDED      roll finalised with the measured weight
//   RUNNING_AGAIN      machine restarted after a recorded roll
//   EXCEPTION          a timeout / invalid signal needs attention (recoverable)
//   MANUAL_REVIEW      a data conflict needs an authorised human decision

const STATES = Object.freeze({
  RUNNING: 'RUNNING',
  COMPLETION_PENDING: 'COMPLETION_PENDING',
  AWAITING_OPERATOR: 'AWAITING_OPERATOR',
  AWAITING_WEIGHT: 'AWAITING_WEIGHT',
  WEIGHT_CAPTURED: 'WEIGHT_CAPTURED',
  ROLL_RECORDED: 'ROLL_RECORDED',
  RUNNING_AGAIN: 'RUNNING_AGAIN',
  EXCEPTION: 'EXCEPTION',
  MANUAL_REVIEW: 'MANUAL_REVIEW',
});

// event -> { from: nextState }. Any (from,event) not listed is an INVALID transition.
const TRANSITIONS = {
  // a completion (stop + green) only starts a pending cycle from RUNNING
  completion: { [STATES.RUNNING]: STATES.COMPLETION_PENDING },
  // pending roll materialises and we wait for the operator
  pending_created: { [STATES.COMPLETION_PENDING]: STATES.AWAITING_OPERATOR },
  // operator confirms the physical roll was removed (REQUIRED step)
  operator_confirm_removal: { [STATES.AWAITING_OPERATOR]: STATES.AWAITING_WEIGHT },
  // a valid, stable, validated weight is attached to the correct pending roll
  weight_valid: { [STATES.AWAITING_WEIGHT]: STATES.WEIGHT_CAPTURED },
  // roll finalised (measured weight written, estimate preserved in audit)
  finalise: { [STATES.WEIGHT_CAPTURED]: STATES.ROLL_RECORDED },
  // machine restarts AFTER the roll is recorded -> next cycle
  restart: { [STATES.ROLL_RECORDED]: STATES.RUNNING_AGAIN },
  resume_running: { [STATES.RUNNING_AGAIN]: STATES.RUNNING },
  // recovery out of EXCEPTION/MANUAL_REVIEW back into the weighing flow
  recover_to_weight: {
    [STATES.EXCEPTION]: STATES.AWAITING_WEIGHT,
    [STATES.MANUAL_REVIEW]: STATES.AWAITING_WEIGHT,
  },
};

// Events that may fire from ANY non-terminal state (never create/finalise a roll).
const ANYSTATE = {
  // invalid weight, scale timeout, operator timeout -> EXCEPTION (roll NOT finalised)
  exception: STATES.EXCEPTION,
  // data conflict (wrong scale/operator, mismatch) -> MANUAL_REVIEW
  manual_review: STATES.MANUAL_REVIEW,
};

function canTransition(from, event) {
  if (ANYSTATE[event]) {
    // cannot leave a finished roll via exception/manual_review
    return from !== STATES.ROLL_RECORDED && from !== STATES.RUNNING;
  }
  const map = TRANSITIONS[event];
  return !!(map && map[from]);
}

function next(from, event) {
  if (ANYSTATE[event]) {
    if (!canTransition(from, event)) {
      throw new InvalidTransition(from, event);
    }
    return ANYSTATE[event];
  }
  const map = TRANSITIONS[event];
  if (!map || !map[from]) throw new InvalidTransition(from, event);
  return map[from];
}

class InvalidTransition extends Error {
  constructor(from, event) {
    super(`invalid transition: cannot apply '${event}' from state '${from}'`);
    this.name = 'InvalidTransition';
    this.from = from;
    this.event = event;
    this.code = 'INVALID_TRANSITION';
  }
}

module.exports = { STATES, TRANSITIONS, ANYSTATE, canTransition, next, InvalidTransition };
