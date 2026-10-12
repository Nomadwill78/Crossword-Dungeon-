import test from 'node:test';
import assert from 'node:assert/strict';
import {
  STORAGE_KEY, dailyKey, dailySeed, dailyHero, previousKey, msUntilNextDaily, formatCountdown,
  loadResults, saveResults, recordResult, computeStreak, shareText,
} from '../../src/daily.js';
import { HERO_LIST } from '../../src/heroes.js';

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
