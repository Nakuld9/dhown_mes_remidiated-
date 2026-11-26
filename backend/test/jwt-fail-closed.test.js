// SEC-2 regression: the JWT secret must FAIL CLOSED.
//
// Proves that a missing JWT_SECRET can never result in use of a built-in
// fallback secret, that the former public value is refused, and that with a
// correctly configured secret a token forged under the old fallback is rejected
// while a legitimately signed token is accepted.

jest.mock('../src/lib/token-revocation', () => ({ isRevoked: () => false }));
const jwt = require('jsonwebtoken');

const FORMER_BUILTIN = 'dhown_mes_jwt_secret_2026';
const loadAuth = () => require('../src/middleware/auth');

function runVerify(auth, token) {
  let status = 200, nexted = false, body = null;
  const req = { headers: token ? { authorization: 'Bearer ' + token } : {}, baseUrl: '', path: '/', originalUrl: '/' };
  const res = { status(c) { status = c; return this; }, json(b) { body = b; return this; } };
  auth.verifyToken(req, res, () => { nexted = true; });
  return { status, nexted, body };
}

describe('SEC-2 — JWT fail-closed (no built-in fallback secret)', () => {
  const ORIGINAL = process.env.JWT_SECRET;
  afterEach(() => { process.env.JWT_SECRET = ORIGINAL; jest.resetModules(); });

  test('missing JWT_SECRET → auth module refuses to load (no fallback)', () => {
    jest.resetModules();
    delete process.env.JWT_SECRET;
    expect(loadAuth).toThrow(/JWT_SECRET is not set/i);
  });

  test('empty/whitespace JWT_SECRET → refused', () => {
    jest.resetModules();
    process.env.JWT_SECRET = '   ';
    expect(loadAuth).toThrow(/JWT_SECRET is not set/i);
  });

  test('the former built-in secret is explicitly refused', () => {
    jest.resetModules();
    process.env.JWT_SECRET = FORMER_BUILTIN;
    expect(loadAuth).toThrow(/public|rotate/i);
  });

  test('configured secret: valid token passes; a token forged with the old fallback is rejected', () => {
    jest.resetModules();
    process.env.JWT_SECRET = 'a-strong-random-test-secret-9f3c1a7b2e';
    const auth = loadAuth();

    const good = jwt.sign({ id: 1, username: 'u', role: 'ADMIN' }, process.env.JWT_SECRET, { expiresIn: '5m' });
    const forged = jwt.sign({ id: 1, username: 'u', role: 'ADMIN' }, FORMER_BUILTIN, { expiresIn: '5m' });

    expect(runVerify(auth, good).nexted).toBe(true);        // legitimate token accepted

    const f = runVerify(auth, forged);                       // forged-with-old-fallback token
    expect(f.nexted).toBe(false);
    expect(f.status).toBe(401);
  });
});
