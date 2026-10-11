// Seedable randomness. The Daily Challenge needs every player to get the same
// dungeon, so everything that rolls dice (grid layout, battle racks, monster
// hits, which letter a hint reveals) takes one of these instead of calling
// Math.random directly. Free play simply passes Math.random.

/** A fast, well-distributed 32-bit generator: call it for a float in [0, 1). */
export function mulberry32(seed) {
  let a = seed;
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Turns any string into a 32-bit seed (so "2026-10-12" and "2026-10-13"
 * give unrelated sequences). */
export function hashSeed(text) {
  let h = 1779033703 ^ text.length;
  for (let i = 0; i < text.length; i += 1) {
    h = Math.imul(h ^ text.charCodeAt(i), 3432918353);
    h = (h << 13) | (h >>> 19);
  }
  h = Math.imul(h ^ (h >>> 16), 2246822507);
  h = Math.imul(h ^ (h >>> 13), 3266489909);
  return (h ^ (h >>> 16)) >>> 0;
}

/** A generator for a named seed. */
export function seededRng(text) {
  return mulberry32(hashSeed(text));
}

/** An integer in [0, n) from [rng]. */
export function randomInt(rng, n) {
  return Math.floor(rng() * n);
}
