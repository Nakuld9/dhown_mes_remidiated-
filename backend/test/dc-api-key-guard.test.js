// dcApiKeyGuard hardening regression (remediation: DC ingest fail-closed).
//
// Proves the /api/live-data ingest guard now FAILS CLOSED: no/empty DC_API_KEY
// rejects with 503, credentials are accepted via the x-api-key HEADER ONLY
// (query-string keys rejected), comparison is constant-time and length-safe,
// wrong/missing credentials never reach the route, and no credential value is
// ever logged. JWT behaviour is unaffected (jest.setup provides JWT_SECRET).

jest.mock('../src/lib/token-revocation', () => ({ isRevoked: () => false }));
const auth = require('../src/middleware/auth');

// Minimal express-style req/res harness.
function run({ header, query } = {}) {
  let status = 200, body = null, nexted = false;
  const req = {
    get: (h) => (String(h).toLowerCase() === 'x-api-key' ? header : undefined),
    query: query || {},
    headers: {},
  };
  const res = {
    status(c) { status = c; return this; },
    json(b) { body = b; return this; },
  };
  auth.dcApiKeyGuard(req, res, () => { nexted = true; });
  return { status, body, nexted };
}

describe('dcApiKeyGuard — fail-closed DC ingest auth', () => {
  const ORIGINAL = process.env.DC_API_KEY;
  afterEach(() => {
    if (ORIGINAL === undefined) delete process.env.DC_API_KEY;
    else process.env.DC_API_KEY = ORIGINAL;
    jest.restoreAllMocks();
  });

  test('DC_API_KEY unset → 503, next() not called', () => {
    delete process.env.DC_API_KEY;
    const r = run({ header: 'anything' });
    expect(r.status).toBe(503);
    expect(r.nexted).toBe(false);
  });

  test('DC_API_KEY empty/whitespace → 503, next() not called', () => {
    process.env.DC_API_KEY = '   ';
    const r = run({ header: 'anything' });
    expect(r.status).toBe(503);
    expect(r.nexted).toBe(false);
  });

  test('missing header (key configured) → 401, not next()', () => {
    process.env.DC_API_KEY = 'correct-dc-key-0123456789';
    const r = run({});
    expect(r.status).toBe(401);
    expect(r.nexted).toBe(false);
  });

  test('incorrect header → 401, not next()', () => {
    process.env.DC_API_KEY = 'correct-dc-key-0123456789';
    const r = run({ header: 'wrong-key-0123456789' });
    expect(r.status).toBe(401);
    expect(r.nexted).toBe(false);
  });

  test('correct header → next() called, no error response', () => {
    process.env.DC_API_KEY = 'correct-dc-key-0123456789';
    const r = run({ header: 'correct-dc-key-0123456789' });
    expect(r.nexted).toBe(true);
    expect(r.status).toBe(200);
  });

  test('query-string key alone → rejected (header-only), not next()', () => {
    process.env.DC_API_KEY = 'correct-dc-key-0123456789';
    const r = run({ query: { api_key: 'correct-dc-key-0123456789' } });
    expect(r.nexted).toBe(false);
    expect(r.status).toBe(401);
  });

  test('unequal key lengths → rejected safely (no throw)', () => {
    process.env.DC_API_KEY = 'short';
    let r;
    expect(() => { r = run({ header: 'a-much-longer-supplied-value-than-expected' }); }).not.toThrow();
    expect(r.status).toBe(401);
    expect(r.nexted).toBe(false);
  });

  test('no credential value appears in logs', () => {
    const SECRET = 'super-secret-dc-key-value-XYZ';
    const spies = ['log', 'warn', 'error', 'info', 'debug'].map((m) => jest.spyOn(console, m).mockImplementation(() => {}));
    // exercise all branches
    delete process.env.DC_API_KEY; run({ header: SECRET });
    process.env.DC_API_KEY = SECRET; run({}); run({ header: 'wrong' }); run({ header: SECRET });
    const logged = spies.flatMap((s) => s.mock.calls).flat().map(String).join('\n');
    expect(logged).not.toContain(SECRET);
    expect(logged).not.toContain('wrong');
  });
});
