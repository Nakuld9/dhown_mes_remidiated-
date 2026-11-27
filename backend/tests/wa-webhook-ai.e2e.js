// Verify the two ends of the WhatsApp inbound → AI-draft path that can be
// checked without a live Meta number:
//
//   1. The webhook HMAC gate — the door every inbound message comes through.
//      Meta signs the raw body with the App Secret; a forged or unsigned body
//      must be refused, and if the secret is unset the door must FAIL CLOSED.
//   2. AI reachability — the Groq call that produces a draft actually responds.
//
// The middle (durable queue → processor → persist → wa-ai.run orchestration) is
// covered by the existing wa-* jest specs + ai-guardrails.e2e and by the app
// booting; it also writes to live tables, so it is deliberately not exercised here.
//
//   node tests/wa-webhook-ai.e2e.js

const crypto = require('crypto');
const path = require('path');

let fails = 0;
const ok = (c, m, extra = '') => { console.log((c ? '  PASS  ' : '  FAIL  ') + m + (extra ? '   ' + extra : '')); if (!c) fails++; };

// Load a FRESH copy of the verifier with a chosen App Secret (it reads the env
// at require-time and fails closed when unset — so each case needs a clean load).
const VERIFY_PATH = path.resolve(__dirname, '../src/middleware/webhook-verify.js');
function loadVerifier(secret) {
  delete require.cache[VERIFY_PATH];
  if (secret === null) delete process.env.WHATSAPP_APP_SECRET;
  else process.env.WHATSAPP_APP_SECRET = secret;
  return require('../src/middleware/webhook-verify').verifyWhatsappSignature;
}

// Run the middleware against a crafted request; report 'next' or the HTTP status.
function run(verify, { rawBody, signatureHeader }) {
  let outcome = 'pending';
  const req = {
    rawBody: rawBody === undefined ? undefined : Buffer.from(rawBody),
    get: (h) => (h.toLowerCase() === 'x-hub-signature-256' ? signatureHeader : undefined),
  };
  const res = {
    status: (s) => ({ json: () => { outcome = s; } }),
    sendStatus: (s) => { outcome = s; },
  };
  verify(req, res, () => { outcome = 'next'; });
  return outcome;
}

const SECRET = 'test_app_secret_' + crypto.randomBytes(4).toString('hex');
const body = JSON.stringify({ object: 'whatsapp_business_account', entry: [{ changes: [{ value: { messages: [{ from: '919999000001', text: { body: 'Rate for 30s single jersey?' } }] } }] }] });
const sign = (b, secret = SECRET) => 'sha256=' + crypto.createHmac('sha256', secret).update(Buffer.from(b)).digest('hex');

(async () => {
  // ── 1. Webhook HMAC gate ───────────────────────────────────────────────────
  console.log('\nWebhook signature gate');

  const unset = loadVerifier(null);
  ok(run(unset, { rawBody: body, signatureHeader: sign(body) }) === 503,
    'FAILS CLOSED when App Secret is unset — every webhook refused (503)');

  const verify = loadVerifier(SECRET);
  ok(run(verify, { rawBody: body, signatureHeader: sign(body) }) === 'next',
    'a correctly-signed Meta webhook passes');
  ok(run(verify, { rawBody: body, signatureHeader: undefined }) === 401,
    'an unsigned body is refused (401)');
  ok(run(verify, { rawBody: body, signatureHeader: 'sha256=' + '0'.repeat(64) }) === 401,
    'a wrong signature is refused (401)');
  ok(run(verify, { rawBody: body + ' ', signatureHeader: sign(body) }) === 401,
    'a tampered body (signature no longer matches the bytes) is refused (401)');
  ok(run(verify, { rawBody: body, signatureHeader: sign(body, 'not_the_real_secret') }) === 401,
    'a body signed with the wrong secret is refused (401)');
  ok(run(verify, { rawBody: undefined, signatureHeader: sign(body) }) === 401,
    'a signature with no raw body to verify against is refused (401)');
  ok(run(verify, { rawBody: body, signatureHeader: 'garbage' }) === 401,
    'a malformed signature header is refused (401)');

  // ── 2. AI reachability ─────────────────────────────────────────────────────
  // AI draft path — Groq TRANSPORT IS MOCKED here (Phase 1.5-B controlled
  // fixture): no live api.groq.com call and NO production credentials. This
  // exercises callGroq's real request-build + response-parse against a canned
  // completion, verifying the webhook→AI-draft path without an external service.
  // Live Groq reachability is an ops/runtime concern, not a clean-DB test concern.
  require('dotenv').config({ quiet: true });
  console.log('\nAI draft engine (Groq transport MOCKED — no live call, no credentials)');
  const { EventEmitter } = require('events');
  const https = require('https');
  const realGroqRequest = https.request;
  const prevKey = process.env.GROQ_API_KEY;
  process.env.GROQ_API_KEY = prevKey || 'test-mock-key-not-a-real-credential';
  https.request = (options, cb) => {
    if (options && options.hostname === 'api.groq.com') {
      const res = new EventEmitter();
      process.nextTick(() => {
        res.emit('data', JSON.stringify({ choices: [{ message: { content: 'Yes — we knit single jersey fabric.' } }] }));
        res.emit('end');
      });
      cb(res);
      const req = new EventEmitter();
      req.setTimeout = () => {}; req.write = () => {}; req.end = () => {}; req.destroy = () => {};
      return req;
    }
    return realGroqRequest(options, cb);
  };
  const { callGroq } = require('../src/lib/ai');
  ok(!!process.env.GROQ_API_KEY, 'GROQ_API_KEY present (mock value in tests)');
  let reply = '';
  try {
    reply = await callGroq(
      'You are a knitting-mill sales assistant. Answer in one short sentence.',
      'A customer asks: do you make single jersey fabric?');
  } catch (e) { reply = 'THREW: ' + e.message; }
  https.request = realGroqRequest;
  if (prevKey === undefined) delete process.env.GROQ_API_KEY; else process.env.GROQ_API_KEY = prevKey;
  const usable = typeof reply === 'string' && reply.length > 0 &&
    !/GROQ_API_KEY not set/i.test(reply) && !/^THREW:/.test(reply);
  ok(usable, 'webhook→AI-draft path produces a usable draft (Groq transport MOCKED)',
    usable ? `→ "${reply.slice(0, 70).replace(/\n/g, ' ')}…"` : `→ "${reply.slice(0, 90)}"`);

  console.log(fails ? `\n${fails} FAILED\n` : '\nAll checks passed — the webhook gate and AI draft engine are sound.\n');
  process.exit(fails ? 1 : 0);
})().catch((e) => { console.error('CRASH', e.message); process.exit(1); });
