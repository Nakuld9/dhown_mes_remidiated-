// Jest global setup (runs before each test file's modules load).
//
// src/middleware/auth.js now FAILS CLOSED when JWT_SECRET is unset (remediation
// SEC-2). Unit tests that load the auth middleware therefore need a secret to be
// present. This provides a TEST-ONLY value — it is a test fixture, never a
// production fallback, and does not reintroduce the removed built-in default.
// Tests that specifically assert the missing/leaked-secret behaviour override
// process.env.JWT_SECRET themselves.
if (!process.env.JWT_SECRET) {
  process.env.JWT_SECRET = 'test-only-jwt-secret-not-for-production-0123456789abcdef';
}
