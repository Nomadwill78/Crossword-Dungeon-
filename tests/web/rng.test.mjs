import test from 'node:test';
import assert from 'node:assert/strict';
import { mulberry32, hashSeed, seededRng, randomInt } from '../../src/rng.js';

// These pinned values are a compatibility contract. If they change, every
// player's Daily Challenge changes with them (and a result shared yesterday
// no longer describes the dungeon anyone can play), so change them on purpose.
test('the generator and hash are pinned', () => {
  const r = mulberry32(1);
  assert.deepEqual([r(), r(), r()], [0.6270739405881613, 0.002735721180215478, 0.5274470399599522]);
  assert.equal(hashSeed('2026-10-12'), 4278251);
  assert.equal(hashSeed('wordsmith-daily-v1:2026-10-12'), 2939221502);
});

test('the same seed repeats exactly; different seeds do not', () => {
  const a = mulberry32(42);
  const b = mulberry32(42);
  const c = mulberry32(43);
  const first = Array.from({ length: 50 }, () => a());
  assert.deepEqual(Array.from({ length: 50 }, () => b()), first);
  assert.notDeepEqual(Array.from({ length: 50 }, () => c()), first);
  assert.ok(first.every((x) => x >= 0 && x < 1));
});

test('hashing: stable, spread out, and sensitive to every character', () => {
  assert.equal(hashSeed('abc'), hashSeed('abc'));
  const seeds = new Set();
  for (let d = 1; d <= 31; d += 1) seeds.add(hashSeed(`2026-10-${String(d).padStart(2, '0')}`));
  assert.equal(seeds.size, 31, 'no two October dates collide');
  assert.notEqual(hashSeed('2026-10-12'), hashSeed('2026-10-13'));
  assert.notEqual(hashSeed('a'), hashSeed('b'));
  assert.ok(Number.isInteger(hashSeed('')) && hashSeed('') >= 0);
  const unicode = hashSeed('wörd ✓');
  assert.ok(unicode >= 0 && unicode < 2 ** 32);
});

test('seededRng is hash + generator, and randomInt stays in range and covers it', () => {
  assert.deepEqual(
    [seededRng('x')(), seededRng('x')()],
    [mulberry32(hashSeed('x'))(), mulberry32(hashSeed('x'))()]
  );
  const rng = seededRng('range');
  const seen = new Set();
  for (let i = 0; i < 500; i += 1) {
    const n = randomInt(rng, 5);
    assert.ok(Number.isInteger(n) && n >= 0 && n < 5);
    seen.add(n);
  }
  assert.equal(seen.size, 5, 'every value comes up');
  assert.equal(randomInt(() => 0.999999, 7), 6);
  assert.equal(randomInt(() => 0, 7), 0);
});
