// Regression (Phase 1.5-A): manual finished-entry must handle empty / null /
// invalid / valid input and DB errors defensively — returning a clean result
// object, never throwing or returning a misleading shape. No DB (mocked pool).
const makeLib = require('../src/lib/finished-entry');

function fakePool(countRows = [{ n: 0 }]) {
  const client = { query: jest.fn(async () => ({ rows: countRows })), release: jest.fn() };
  return { pool: { connect: async () => client }, client };
}

describe('finished-entry.create — defensive input handling', () => {
  test('missing fabric_type → 400 (no DB write)', async () => {
    const { pool, client } = fakePool();
    const r = await makeLib(pool).create({ rolls: [{ weight_kg: 5 }] }, 'u');
    expect(r.code).toBe(400);
    expect(client.query).not.toHaveBeenCalled();
  });

  test('empty rolls array → 400', async () => {
    const r = await makeLib(fakePool().pool).create({ fabric_type: 'X', rolls: [] }, 'u');
    expect(r.code).toBe(400);
  });

  test('null rolls → 400 (handled, not a crash)', async () => {
    const r = await makeLib(fakePool().pool).create({ fabric_type: 'X', rolls: null }, 'u');
    expect(r.code).toBe(400);
  });

  test('rolls with non-positive weights → 400', async () => {
    const r = await makeLib(fakePool().pool).create({ fabric_type: 'X', rolls: [{ weight_kg: 0 }, { weight_kg: -2 }] }, 'u');
    expect(r.code).toBe(400);
  });

  test('valid data → ok shape with created[] (no throw)', async () => {
    const r = await makeLib(fakePool([{ n: 0 }]).pool).create(
      { fabric_type: 'ZZ', color_name: 'Navy', rolls: [{ weight_kg: 40 }, { weight_kg: 42 }] }, 'u');
    expect(r.ok).toBe(true);
    expect(r.rolls).toBe(2);
    expect(r.total_kg).toBe(82);
    expect(Array.isArray(r.created)).toBe(true);
    expect(r.created).toHaveLength(2);
  });

  test('DB error → clean { code: 500 } (not a thrown exception)', async () => {
    const client = {
      query: jest.fn(async (q) => { if (/INSERT/i.test(q)) throw new Error('boom'); return { rows: [{ n: 0 }] }; }),
      release: jest.fn(),
    };
    const r = await makeLib({ connect: async () => client }).create(
      { fabric_type: 'ZZ', rolls: [{ weight_kg: 40 }] }, 'u');
    expect(r.code).toBe(500);
    expect(r.error).toBeTruthy();
  });
});
