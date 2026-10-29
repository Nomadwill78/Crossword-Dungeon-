import test from 'node:test';
import assert from 'node:assert/strict';
import {
  STORAGE_KEY, MODES, storageKeyFor, dailyKey, dailySeed, dailyHero, previousKey, msUntilNextDaily, formatCountdown,
  loadResults, saveResults, recordResult, computeStreak, shareText,
} from '../../src/daily.js';
import { HERO_LIST } from '../../src/heroes.js';
import { DungeonRun } from '../../src/dungeon.js';
import { LEVEL_ONE } from '../../src/wordlist.js';

const result = (score = 100, retreats = 0, hintsUsed = 0, hero = 'scribe') => ({ score, retreats, hintsUsed, hero });

/** A localStorage stand-in. */
function memoryStorage(initial = {}) {
  const data = { ...initial };
  return {
    data,
    getItem: (k) => (k in data ? data[k] : null),
    setItem: (k, v) => { data[k] = String(v); },
  };
}

test('a day is the UTC date, whatever the local time zone', () => {
  assert.equal(dailyKey(new Date('2026-03-15T00:00:00Z')), '2026-03-15');
  assert.equal(dailyKey(new Date('2026-03-15T23:59:59.999Z')), '2026-03-15');
  assert.equal(dailyKey(new Date('2026-03-16T00:00:00Z')), '2026-03-16');
  // 00:30 on the 16th in Berlin (+01:00) is 23:30 on the 15th in UTC...
  assert.equal(dailyKey(new Date('2026-03-16T00:30:00+01:00')), '2026-03-15');
  // ...and 18:30 on the 15th in Los Angeles (-07:00) is already the 16th in UTC.
  assert.equal(dailyKey(new Date('2026-03-15T18:30:00-07:00')), '2026-03-16');
  assert.match(dailyKey(), /^\d{4}-\d{2}-\d{2}$/);
});

test('the day is the same wherever the machine thinks it is', () => {
  // The sandbox may well be in UTC, where local and UTC dates never differ,
  // so run under the two most extreme zones (UTC+14 and UTC-12).
  const original = process.env.TZ;
  try {
    for (const zone of ['Pacific/Kiritimati', 'Etc/GMT+12', 'America/Los_Angeles', 'Asia/Kolkata']) {
      process.env.TZ = zone;
      assert.equal(dailyKey(new Date('2026-03-15T12:00:00Z')), '2026-03-15', zone);
      assert.equal(dailyKey(new Date('2026-03-15T23:30:00Z')), '2026-03-15', zone);
      assert.equal(dailyKey(new Date('2026-03-16T00:30:00Z')), '2026-03-16', zone);
      assert.equal(msUntilNextDaily(new Date('2026-03-15T23:00:00Z')), 3600 * 1000, zone);
    }
  } finally {
    if (original === undefined) delete process.env.TZ;
    else process.env.TZ = original;
  }
});

test('the seed and hero depend only on the date', () => {
  assert.equal(dailySeed('2026-10-12'), dailySeed('2026-10-12'));
  assert.notEqual(dailySeed('2026-10-12'), dailySeed('2026-10-13'));
  assert.equal(dailyHero('2026-10-12'), dailyHero('2026-10-12'));
  assert.equal(dailyHero('2026-10-12').id, 'scribe', 'pinned: changing it changes everyone\'s day');
  assert.equal(dailyHero('2026-10-13').id, 'warden');

  const seen = new Set();
  for (let d = 0; d < 60; d += 1) seen.add(dailyHero(new Date(Date.UTC(2026, 8, 1) + d * 86400000).toISOString().slice(0, 10)).id);
  assert.equal(seen.size, HERO_LIST.length, 'every hero gets a turn');
});

test('previousKey handles month, year and leap-day boundaries', () => {
  assert.equal(previousKey('2026-03-15'), '2026-03-14');
  assert.equal(previousKey('2026-03-01'), '2026-02-28');
  assert.equal(previousKey('2024-03-01'), '2024-02-29');
  assert.equal(previousKey('2026-01-01'), '2025-12-31');
});

test('the countdown to the next dungeon', () => {
  const hour = 3600 * 1000;
  assert.equal(msUntilNextDaily(new Date('2026-03-15T23:00:00Z')), hour);
  assert.equal(msUntilNextDaily(new Date('2026-03-15T00:00:00Z')), 24 * hour, 'at midnight a full day remains');
  assert.equal(msUntilNextDaily(new Date('2026-03-15T23:59:59.500Z')), 500);
  assert.equal(formatCountdown(5 * hour + 12 * 60000), '5h 12m');
  assert.equal(formatCountdown(12 * 60000), '12m');
  assert.equal(formatCountdown(59 * 1000), 'under a minute');
  assert.equal(formatCountdown(0), 'under a minute');
  assert.equal(formatCountdown(60 * 60000), '1h 0m');
});

test('saved results survive a round trip', () => {
  const storage = memoryStorage();
  assert.deepEqual(loadResults(storage), {});
  const results = { '2026-03-14': result(300, 1, 2, 'warden'), '2026-03-15': result(410) };
  assert.equal(saveResults(storage, results), true);
  assert.deepEqual(loadResults(storage), results);
  assert.ok(STORAGE_KEY in storage.data);
});

test('damaged or hand-edited saves are ignored, never trusted', () => {
  const load = (raw) => loadResults(memoryStorage({ [STORAGE_KEY]: raw }));
  assert.deepEqual(load('not json'), {});
  assert.deepEqual(load('[]'), {});
  assert.deepEqual(load('null'), {});
  assert.deepEqual(load('42'), {});
  const good = result(10);
  const mixed = load(JSON.stringify({
    '2026-03-15': good,
    '2026-3-15': good,                                   // malformed key
    'today': good,                                       // not a date
    '2026-03-16': { ...good, score: 'lots' },            // score not a number
    '2026-03-17': { ...good, retreats: -1 },             // negative
    '2026-03-18': { ...good, hintsUsed: 1.5 },           // not an integer
    '2026-03-19': { ...good, hero: 7 },                  // hero not a string
    '2026-03-20': null,
    '__proto__': good,
  }));
  assert.deepEqual(Object.keys(mixed), ['2026-03-15']);

  const extra = load(JSON.stringify({ '2026-03-15': { ...good, admin: true } }));
  assert.deepEqual(Object.keys(extra['2026-03-15']).sort(), ['hero', 'hintsUsed', 'retreats', 'score'], 'unknown fields are dropped');

  const throwing = { getItem() { throw new Error('blocked'); }, setItem() { throw new Error('blocked'); } };
  assert.deepEqual(loadResults(throwing), {}, 'storage that throws means no results');
  assert.equal(saveResults(throwing, { '2026-03-15': good }), false, 'and a failed save is reported');
});

test('only the most recent days are kept', () => {
  const results = {};
  for (let i = 0; i < 450; i += 1) {
    results[new Date(Date.UTC(2025, 0, 1) + i * 86400000).toISOString().slice(0, 10)] = result(i);
  }
  const storage = memoryStorage();
  saveResults(storage, results);
  const kept = Object.keys(loadResults(storage)).sort();
  assert.equal(kept.length, 400);
  assert.equal(kept.at(-1), Object.keys(results).sort().at(-1), 'the newest day is kept');
  assert.ok(!kept.includes('2025-01-01'), 'the oldest are dropped');
});

test('the first finished run of a day is the one that counts', () => {
  const start = {};
  const first = recordResult(start, '2026-03-15', result(200));
  assert.equal(first.official, true);
  assert.equal(first.results['2026-03-15'].score, 200);
  assert.deepEqual(start, {}, 'the input is not modified');

  const better = recordResult(first.results, '2026-03-15', result(999));
  assert.equal(better.official, false, 'a better replay does not replace it');
  assert.equal(better.results['2026-03-15'].score, 200);
  assert.equal(better.results, first.results);

  const nextDay = recordResult(first.results, '2026-03-16', result(50));
  assert.equal(nextDay.official, true);
  assert.equal(Object.keys(nextDay.results).length, 2);

  assert.equal(recordResult({}, 'bad-key', result()).official, false);
  assert.equal(recordResult({}, '2026-03-15', { score: NaN, retreats: 0, hintsUsed: 0, hero: 'x' }).official, false);
  assert.equal(recordResult({}, '2026-03-15', null).official, false);
});

test('streaks count consecutive days and stay alive until midnight', () => {
  const days = (...keys) => Object.fromEntries(keys.map((k) => [k, result()]));
  assert.equal(computeStreak({}, '2026-03-15'), 0);
  assert.equal(computeStreak(days('2026-03-15'), '2026-03-15'), 1);
  assert.equal(computeStreak(days('2026-03-14', '2026-03-15'), '2026-03-15'), 2);
  assert.equal(computeStreak(days('2026-03-13', '2026-03-14'), '2026-03-15'), 2, 'today not played yet: still alive through yesterday');
  assert.equal(computeStreak(days('2026-03-12', '2026-03-13'), '2026-03-15'), 0, 'missed yesterday: broken');
  assert.equal(computeStreak(days('2026-03-15', '2026-03-13', '2026-03-12'), '2026-03-15'), 1, 'a gap ends the count');
  assert.equal(computeStreak(days('2026-02-27', '2026-02-28', '2026-03-01', '2026-03-02'), '2026-03-02'), 4, 'across a month boundary');
  assert.equal(computeStreak(days('2025-12-31', '2026-01-01'), '2026-01-01'), 2, 'across a year boundary');
  assert.equal(computeStreak(days('2026-03-16'), '2026-03-15'), 0, 'a future day does not count');
});

test('the share text', () => {
  const hero = HERO_LIST[1];
  assert.equal(
    shareText({ key: '2026-10-12', hero, result: result(412, 1, 3), streak: 4 }),
    ["Wordsmith's Gambit — Daily 2026-10-12", 'The Warden: 412 Score', '1 retreat · 3 hints', '4 days in a row'].join('\n')
  );
  const single = shareText({ key: '2026-10-12', hero, result: result(5, 0, 1), streak: 1, url: 'https://example.test/' });
  assert.match(single, /0 retreats · 1 hint\n1 day in a row\nhttps:\/\/example\.test\/$/);
  assert.ok(!/in a row/.test(shareText({ key: '2026-10-12', hero, result: result(), streak: 0 })), 'no streak line at zero');
});

// ---- Daily Hardcore: its own dungeon, hero, results and streak ---------------

const hard = (score = 100, outcome = 'won', hintsUsed = 0, hero = 'scribe') => ({ score, retreats: 0, hintsUsed, hero, outcome });
const layout = (run) => run.placements.map((p) => `${p.word}@${p.row},${p.col}${p.dir}`).join('|');

test('there are two dailies, and the standard one is exactly what it always was', () => {
  assert.deepEqual(MODES, ['normal', 'hardcore']);
  assert.equal(dailySeed('2026-10-12'), 'wordsmith-daily-v1:2026-10-12', 'pinned: changing it changes everyone\'s day');
  assert.equal(dailySeed('2026-10-12', 'normal'), dailySeed('2026-10-12'));
  assert.equal(dailyHero('2026-10-12', 'normal'), dailyHero('2026-10-12'));
  assert.equal(storageKeyFor('normal'), STORAGE_KEY);
  assert.equal(STORAGE_KEY, 'wordsmith-daily', 'pinned: players\' saved results live here');
  assert.throws(() => dailySeed('2026-10-12', 'easy'), /unknown daily mode/);
});

test('the hardcore daily has its own seed, its own hero and its own storage', () => {
  assert.equal(dailySeed('2026-10-12', 'hardcore'), 'wordsmith-daily-hardcore-v1:2026-10-12');
  assert.notEqual(dailySeed('2026-10-12', 'hardcore'), dailySeed('2026-10-12', 'normal'));
  assert.equal(dailyHero('2026-10-12', 'hardcore'), dailyHero('2026-10-12', 'hardcore'), 'stable for a day');
  assert.notEqual(storageKeyFor('hardcore'), storageKeyFor('normal'));

  // Over a stretch of days the two heroes are not the same sequence (the dungeon is a different puzzle).
  let differs = 0;
  const seen = new Set();
  for (let d = 0; d < 60; d += 1) {
    const key = new Date(Date.UTC(2026, 8, 1) + d * 86400000).toISOString().slice(0, 10);
    if (dailyHero(key, 'hardcore').id !== dailyHero(key, 'normal').id) differs += 1;
    seen.add(dailyHero(key, 'hardcore').id);
  }
  assert.ok(differs > 20, `the heroes differ on most days (${differs} of 60)`);
  assert.equal(seen.size, HERO_LIST.length, 'every hero gets a turn in hardcore too');
});

test('the same day gives the same hardcore dungeon, and not the standard one', () => {
  const key = '2026-10-12';
  const run = () => new DungeonRun(LEVEL_ONE, dailyHero(key, 'hardcore'), { seed: dailySeed(key, 'hardcore'), hardcore: true });
  const a = run();
  const b = run();
  assert.equal(a.hardcore, true, 'it plays by the hardcore rules');
  assert.equal(layout(a), layout(b), 'everyone gets the same dungeon');
  assert.equal(a.battleRng(1)(), b.battleRng(1)(), 'and the same dice');
  const standard = new DungeonRun(LEVEL_ONE, dailyHero(key), { seed: dailySeed(key) });
  assert.equal(standard.hardcore, false);
  assert.notEqual(layout(a), layout(standard), 'it is a different puzzle from that day\'s standard dungeon');
  const other = new DungeonRun(LEVEL_ONE, dailyHero('2026-10-13', 'hardcore'), { seed: dailySeed('2026-10-13', 'hardcore'), hardcore: true });
  assert.notEqual(layout(a), layout(other), 'and tomorrow\'s is different again');
});

test('hardcore results are kept apart and must say how the run ended', () => {
  const storage = memoryStorage();
  saveResults(storage, { '2026-10-12': result(300) }, 'normal');
  saveResults(storage, { '2026-10-12': hard(450, 'fell') }, 'hardcore');
  assert.deepEqual(Object.keys(storage.data).sort(), ['wordsmith-daily', 'wordsmith-daily-hardcore']);
  assert.equal(loadResults(storage, 'normal')['2026-10-12'].score, 300);
  assert.equal(loadResults(storage).outcome, undefined, 'default is the standard daily');
  assert.deepEqual(loadResults(storage, 'hardcore')['2026-10-12'], hard(450, 'fell'));

  // A hardcore record without an outcome, or a standard one with one, is not trusted.
  assert.deepEqual(loadResults(memoryStorage({ 'wordsmith-daily-hardcore': JSON.stringify({ '2026-10-12': result(10) }) }), 'hardcore'), {});
  assert.deepEqual(loadResults(memoryStorage({ 'wordsmith-daily': JSON.stringify({ '2026-10-12': hard(10) }) }), 'normal'), {});
  assert.deepEqual(loadResults(memoryStorage({ 'wordsmith-daily-hardcore': JSON.stringify({ '2026-10-12': { ...hard(10), outcome: 'dunno' } }) }), 'hardcore'), {});
});

test('the first finished hardcore run counts, a win or a fall', () => {
  const fell = recordResult({}, '2026-03-15', hard(120, 'fell'), 'hardcore');
  assert.equal(fell.official, true);
  assert.equal(fell.results['2026-03-15'].outcome, 'fell');
  const retry = recordResult(fell.results, '2026-03-15', hard(900, 'won'), 'hardcore');
  assert.equal(retry.official, false, 'a later win does not replace a fall');
  assert.equal(retry.results['2026-03-15'].score, 120);
  assert.equal(recordResult({}, '2026-03-15', result(5), 'hardcore').official, false, 'no outcome, no record');
});

test('the two streaks are independent', () => {
  const normal = { '2026-03-14': result(), '2026-03-15': result() };
  const hardcore = { '2026-03-15': hard(10, 'fell') };
  assert.equal(computeStreak(normal, '2026-03-15'), 2);
  assert.equal(computeStreak(hardcore, '2026-03-15'), 1, 'a fall still counts as a finished day');
  assert.equal(computeStreak({}, '2026-03-15'), 0);
});

test('the hardcore share text says how it ended', () => {
  const hero = HERO_LIST[1];
  assert.equal(
    shareText({ key: '2026-10-12', hero, result: hard(612, 'won', 2), streak: 3, mode: 'hardcore' }),
    ["Wordsmith's Gambit — Daily Hardcore 2026-10-12", 'The Warden: 612 Score', 'Cleared · 2 hints', '3 days in a row'].join('\n')
  );
  assert.match(shareText({ key: '2026-10-12', hero, result: hard(80, 'fell', 1), streak: 0, mode: 'hardcore' }), /Fell · 1 hint$/);
  assert.match(shareText({ key: '2026-10-12', hero, result: result(5, 0, 1), streak: 0 }), /^Wordsmith's Gambit — Daily 2026-10-12/, 'the standard text is unchanged');
});
