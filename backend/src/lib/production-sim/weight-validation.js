// Weight validation + gross/tare/net resolution (report 29 §7). Pure, no I/O.
//
// Key rules enforced here:
//   * Net = Gross - Tare, but if the scale ALREADY reports net (weight_basis
//     'NET'), the net is used as-is — tare is NOT subtracted a second time.
//   * Invalid readings are never silently accepted; each returns a reason.
//   * Product min/max limits are applied ONLY when the caller supplies them —
//     this module never invents a product weight limit.

const r5 = (n) => Math.round(Number(n) * 100000) / 100000;

// cfg: { capacity, resolution, unit, expected_scale_id, expected_workstation_id,
//        product_min_kg?, product_max_kg?, recent_signatures?: Set }
function validateReading(reading, cfg = {}) {
  const reasons = [];
  const unit = cfg.unit || 'kg';

  // --- unit ---
  if (!reading.unit) reasons.push('MISSING_UNIT');
  else if (reading.unit !== unit) reasons.push('WRONG_UNIT');

  // --- wrong scale / wrong workstation ---
  if (cfg.expected_scale_id && reading.scale_id !== cfg.expected_scale_id) reasons.push('WRONG_SCALE');
  if (cfg.expected_workstation_id && reading.workstation_id && reading.workstation_id !== cfg.expected_workstation_id) {
    reasons.push('WRONG_WORKSTATION');
  }

  // --- resolve net safely (no double tare) ---
  let net = null;
  if (reading.weight_basis === 'NET') {
    net = toNum(reading.net != null ? reading.net : reading.raw_reading);   // already net — do NOT subtract tare
  } else {
    const gross = toNum(reading.gross != null ? reading.gross : reading.raw_reading);
    const tare = toNum(reading.tare || 0);
    net = gross == null ? null : r5(gross - tare);
  }

  // --- numeric sanity ---
  if (net == null || Number.isNaN(net)) reasons.push('INVALID_DATA');
  else {
    if (net === 0) reasons.push('ZERO_READING');
    if (net < 0) reasons.push('NEGATIVE_READING');
    if (cfg.capacity != null && net > Number(cfg.capacity)) reasons.push('OVER_CAPACITY');
    if (cfg.product_min_kg != null && net < Number(cfg.product_min_kg)) reasons.push('BELOW_PRODUCT_MIN');
    if (cfg.product_max_kg != null && net > Number(cfg.product_max_kg)) reasons.push('ABOVE_PRODUCT_MAX');
  }

  // --- stability (only when the scale provides a flag) ---
  if (reading.stable === false) reasons.push('UNSTABLE');
  // reading.stable === null → scale gives no flag → operator confirmation required (not an error)

  // --- repeated/duplicate reading signature ---
  const signature = `${reading.scale_id}|${net}|${reading.unit}`;
  if (cfg.recent_signatures && cfg.recent_signatures.has(signature)) reasons.push('REPEATED_READING');

  const requires_operator_confirmation = reading.stable == null && reasons.length === 0;
  return {
    ok: reasons.length === 0,
    net,
    signature,
    requires_operator_confirmation,
    reasons,
    // partition reasons so the caller can route EXCEPTION vs MANUAL_REVIEW
    is_conflict: reasons.some((r) => ['WRONG_SCALE', 'WRONG_WORKSTATION'].includes(r)),
  };
}

function toNum(v) {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

module.exports = { validateReading, r5 };
