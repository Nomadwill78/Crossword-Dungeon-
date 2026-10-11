import test from 'node:test';
import assert from 'node:assert/strict';
import { DungeonRun } from '../../src/dungeon.js';
import { BattleSession } from '../../src/combat.js';
import { dailySeed } from '../../src/daily.js';
import { HEROES } from '../../src/heroes.js';
import { LEVEL_ONE } from '../../src/wordlist.js';

const signature = (g) => JSON.stringify({
  w: g.width,
  h: g.height,
  p: g.placements.map((p) => [p.word, p.row, p.col, p.dir, p.number]),
  g: g.grid.map((row) => row.map((c) => (c ? c.letter : '.')).join('')),
});

const dailyRun = (key, hero = null) => new DungeonRun(LEVEL_ONE, hero, { seed: dailySeed(key) });

/** The d-th day after 2026-08-31 (d = 1 is 2026-09-01), as a daily key. */
const keyFor = (d) => new Date(Date.UTC(2026, 7, 31) + d * 86400000).toISOString().slice(0, 10);

test('one day\'s layout is pinned', () => {
  // If the word list or the generator changes, this changes for everyone: update it on purpose.
  const run = dailyRun('2026-10-12');
  assert.equal(run.width, 13);
  assert.equal(run.height, 17);
  assert.equal(
    run.placements.map((p) => `${p.word}@${p.row},${p.col}${p.dir[0]}`).join(' '),
    'QUEST@16,2a GOBLIN@5,3d DRAGON@5,0a RIDDLE@11,4d WIZARD@9,2a SHIELD@12,2a SCROLL@7,6d VAULT@2,1a ARMOR@3,9d SWORD@7,6a TRAP@4,1d RUNE@4,9a GOLD@14,1a POTION@0,5d'
  );
});

test('the same seed always builds the same dungeon; different days differ', () => {
  const sigs = new Set();
  for (let d = 1; d <= 40; d += 1) {
    const a = signature(dailyRun(keyFor(d)));
    assert.equal(signature(dailyRun(keyFor(d))), a, `day ${d} repeats`);
    sigs.add(a);
  }
  assert.ok(sigs.size >= 35, `${sigs.size} distinct layouts in 40 days`);
});

test('the layout does not depend on how a browser orders its sort comparisons', () => {
  // Engines sort with different algorithms, calling the comparator in different
  // orders. A comparator that draws random numbers would give each browser its
  // own dungeon. Swap in a very different (but valid, stable) sort and check
  // nothing changes.
  const nativeSort = Array.prototype.sort;
  const reversedInsertionSort = function (compare = (a, b) => (String(a) < String(b) ? -1 : String(a) > String(b) ? 1 : 0)) {
    const items = [...this];
    const out = [];
    for (let i = items.length - 1; i >= 0; i -= 1) {       // walk backwards, insert before the first strictly-greater
      let at = out.length;
      while (at > 0 && compare(out[at - 1], items[i]) > 0) at -= 1;
      out.splice(at, 0, items[i]);
    }
    // restore stability: equal elements must keep their original order
    const rank = new Map(items.map((v, i) => [v, i]));
    out.sort = nativeSort;
    nativeSort.call(out, (a, b) => compare(a, b) || rank.get(a) - rank.get(b));
    for (let i = 0; i < out.length; i += 1) this[i] = out[i];
    return this;
  };

  const days = Array.from({ length: 25 }, (_, d) => keyFor(d + 1));
  const expected = days.map((key) => signature(dailyRun(key)));
  Array.prototype.sort = reversedInsertionSort;
  try {
    const other = days.map((key) => signature(dailyRun(key)));
    assert.deepEqual(other, expected);
  } finally {
    Array.prototype.sort = nativeSort;
  }
});

test('every seeded dungeon can be won: all corridors are reachable from the entrance', () => {
  for (let d = 1; d <= 120; d += 1) {
    const run = dailyRun(keyFor(d), HEROES.scribe);
    const open = new Set(run.placements.filter((p) => p.isEntrance).map((p) => p.index));
    let grew = true;
    while (grew) {
      grew = false;
      for (const p of run.placements) {
        if (open.has(p.index)) continue;
        if (p.disconnected || [...p.neighbors].some((n) => open.has(n))) { open.add(p.index); grew = true; }
      }
    }
    assert.equal(open.size, run.placements.length, `day ${d}: every corridor can be opened`);
    assert.equal(run.monsterPlacements().length, 10, `day ${d}: always ten monsters`);
    assert.ok(Math.max(run.width, run.height) <= 19, `day ${d}: a compact map (${run.width}x${run.height})`);
    assert.equal(run.placements.filter((p) => p.disconnected).length, 0, `day ${d}: no cut-off corridors`);
  }
});

test('unseeded runs are still random', () => {
  const sigs = new Set();
  for (let i = 0; i < 12; i += 1) sigs.add(signature(new DungeonRun(LEVEL_ONE)));
  assert.ok(sigs.size > 1, 'free play does not repeat the same dungeon');
  assert.equal(new DungeonRun(LEVEL_ONE).seed, null);
});

test('a seeded run repeats itself: grid, hints and battle letters', () => {
  const seed = dailySeed('2026-10-12');
  const a = new DungeonRun(LEVEL_ONE, HEROES.warden, { seed });
  const b = new DungeonRun(LEVEL_ONE, HEROES.warden, { seed });
  assert.equal(signature(a), signature(b));

  // the same hint purchases reveal the same letters
  const index = a.placements.find((p) => a.canHint(p.index)).index;
  for (const run of [a, b]) {
    run.score = 500;
    run.buyHint(index, 1, 'score');
    run.buyHint(index, 2, 'score');
    run.buyHint(index, 2, 'score');
  }
  assert.deepEqual(a.hintPattern(index), b.hintPattern(index));

  // the same fight deals the same racks, in any run, however the player got there
  const monster = { name: 'Dummy', hp: 999, attack: 5 };
  const dict = new Set(['CAT']);
  const rackOf = (run, idx) => new BattleSession(monster, dict, new Set(), 40, 40, 8, {}, run.battleRng(idx)).rack.map((t) => t.letter).join('');
  const fresh = new DungeonRun(LEVEL_ONE, HEROES.warden, { seed });
  assert.equal(rackOf(a, 3), rackOf(fresh, 3), 'first fight at corridor 3 is identical');
  const again = rackOf(a, 3);
  assert.equal(again, rackOf(fresh, 3), 'and so is the second (a retry)');
  assert.notEqual(rackOf(a, 4), rackOf(a, 5), 'different corridors deal different letters');
  const racks = new Set(Array.from({ length: 10 }, (_, i) => rackOf(new DungeonRun(LEVEL_ONE, null, { seed: dailySeed(keyFor(i + 1)) }), 3)));
  assert.ok(racks.size >= 8, 'different days deal different letters');
});

test('a whole battle replays identically from the same seed', () => {
  const dict = new Set(['CAT', 'ACT', 'TEA', 'EAT', 'ATE', 'TAN', 'ANT', 'NET', 'TEN', 'EAR', 'ARE', 'ERA', 'RAT', 'ART', 'TAR', 'SEA', 'ASH', 'OAT', 'TOE', 'ONE']);
  const monster = { name: 'Dummy', hp: 60, attack: 6 };
  const play = (rng) => {
    const battle = new BattleSession(monster, dict, new Set(['CAT']), 40, 40, 8, {}, rng);
    const trace = [battle.rack.map((t) => t.letter).join('')];
    for (let turn = 0; turn < 12 && !battle.over; turn += 1) {
      // cast the first valid word we can spell, else a single (wasted) tile
      const word = [...dict].find((w) => {
        const pool = battle.rack.map((t) => t.letter);
        return [...w].every((ch) => { const at = pool.indexOf(ch); if (at < 0) return false; pool.splice(at, 1); return true; });
      });
      const pool = [...battle.rack];
      for (const ch of word ?? 'Z') {
        const tile = pool.find((t) => t.letter === ch && !battle.selected.includes(t.id)) ?? pool[0];
        battle.selectTile(tile.id);
      }
      trace.push(JSON.stringify(battle.submit()), battle.rack.map((t) => t.letter).join(''));
    }
    return trace.join('|');
  };
  const run = new DungeonRun(LEVEL_ONE, null, { seed: dailySeed('2026-10-12') });
  const first = play(run.battleRng(7));
  const replay = play(new DungeonRun(LEVEL_ONE, null, { seed: dailySeed('2026-10-12') }).battleRng(7));
  assert.equal(replay, first);
  assert.notEqual(play(run.battleRng(7)), first, 'a retry (attempt 2) is a different fight');
});

test('retreats are counted', () => {
  const run = new DungeonRun(LEVEL_ONE);
  const monster = run.monsterPlacements()[0];
  assert.equal(run.retreats, 0);
  run.markBattleResolved(monster.index, { won: false, remainingPlayerHP: 20, scoreGained: 5 });
  run.markBattleResolved(monster.index, { won: false, remainingPlayerHP: 20, scoreGained: 0 });
  assert.equal(run.retreats, 2);
  run.markBattleResolved(monster.index, { won: true, remainingPlayerHP: 30, scoreGained: 10 });
  assert.equal(run.retreats, 2, 'a win is not a retreat');
  assert.equal(run.score, 15);
});
