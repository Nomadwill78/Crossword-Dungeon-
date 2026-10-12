// The Daily Challenge: one dungeon a day, the same for everyone.
//
// A "day" is a UTC calendar date, so a player in Tokyo and a player in Lima
// are on the same puzzle at the same moment. The date is the seed: it fixes the
// grid layout, the hero, and every dice roll in the run (see rng.js). Nothing
// here touches the page; main.js wires it up.
//
// Results are kept on this device (there is no server): the first run finished
// each day is the one that counts, so replaying with the answers already known
// cannot improve it. Replays are practice.

import { HERO_LIST } from './heroes.js';
import { hashSeed } from './rng.js';

export const STORAGE_KEY = 'wordsmith-daily';
const SALT = 'wordsmith-daily-v1';
const DAY_MS = 24 * 60 * 60 * 1000;
const KEY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const MAX_STORED_DAYS = 400;

/** The daily key for a moment in time: its UTC date, "YYYY-MM-DD". */
export function dailyKey(date = new Date()) {
  return date.toISOString().slice(0, 10);
}

/** The string every part of that day's run is seeded from. */
export function dailySeed(key) {
  return `${SALT}:${key}`;
}

/** Today's hero. Fixed per day so everybody plays the same character. */
export function dailyHero(key) {
  return HERO_LIST[hashSeed(`${dailySeed(key)}:hero`) % HERO_LIST.length];
}

function keyToTime(key) {
  return Date.parse(`${key}T00:00:00Z`);
}

/** The key of the day before [key]. */
export function previousKey(key) {
  return new Date(keyToTime(key) - DAY_MS).toISOString().slice(0, 10);
}

/** Milliseconds until the next daily dungeon (00:00 UTC). */
export function msUntilNextDaily(now = new Date()) {
  const next = keyToTime(dailyKey(now)) + DAY_MS;
  return Math.max(0, next - now.getTime());
}

/** "5h 12m", "12m", or "under a minute". */
export function formatCountdown(ms) {
  const minutes = Math.floor(ms / 60000);
  if (minutes < 1) return 'under a minute';
  const hours = Math.floor(minutes / 60);
  return hours > 0 ? `${hours}h ${minutes % 60}m` : `${minutes}m`;
}

// ---- saved results ---------------------------------------------------------

function validResult(r) {
  return (
    r && typeof r === 'object'
    && Number.isFinite(r.score)
    && Number.isInteger(r.retreats) && r.retreats >= 0
    && Number.isInteger(r.hintsUsed) && r.hintsUsed >= 0
    && typeof r.hero === 'string'
  );
}

/**
 * Saved results, keyed by day. Anything malformed (a hand-edited or old save)
 * is ignored rather than trusted. [storage] is a localStorage-like object.
 */
export function loadResults(storage) {
  try {
    const raw = JSON.parse(storage.getItem(STORAGE_KEY) ?? '{}');
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {};
    const results = {};
    for (const [key, value] of Object.entries(raw)) {
      if (KEY_PATTERN.test(key) && validResult(value)) {
        results[key] = {
          score: value.score, retreats: value.retreats, hintsUsed: value.hintsUsed, hero: value.hero,
        };
      }
    }
    return results;
  } catch {
    return {};
  }
}

/** Saves [results], keeping the most recent days. Returns false if it could not. */
export function saveResults(storage, results) {
  const kept = Object.keys(results).sort().slice(-MAX_STORED_DAYS);
  const trimmed = Object.fromEntries(kept.map((key) => [key, results[key]]));
  try {
    storage.setItem(STORAGE_KEY, JSON.stringify(trimmed));
    return true;
  } catch {
    return false;
  }
}

/**
 * Adds a finished run to [results] if that day has none yet.
 * @returns {{results: object, official: boolean}} `official` is true when this
 *   run is the one that counts; the input is never modified.
 */
export function recordResult(results, key, result) {
  if (!KEY_PATTERN.test(key) || !validResult(result)) return { results, official: false };
  if (results[key]) return { results, official: false };
  return {
    results: {
      ...results,
      [key]: {
        score: result.score, retreats: result.retreats, hintsUsed: result.hintsUsed, hero: result.hero,
      },
    },
    official: true,
  };
}

/**
 * Consecutive days with a finished daily, up to today. If today is not done
 * yet the streak is still alive through yesterday (you have until midnight).
 */
export function computeStreak(results, todayKey) {
  let key = results[todayKey] ? todayKey : previousKey(todayKey);
  let streak = 0;
  while (results[key]) {
    streak += 1;
    key = previousKey(key);
  }
  return streak;
}

// ---- sharing -----------------------------------------------------------------

function plural(n, one, many = `${one}s`) {
  return `${n} ${n === 1 ? one : many}`;
}

/** The text a player copies to show off a result. */
export function shareText({ key, hero, result, streak, url = '' }) {
  const lines = [
    `Wordsmith's Gambit — Daily ${key}`,
    `${hero.name}: ${result.score} Score`,
    `${plural(result.retreats, 'retreat')} · ${plural(result.hintsUsed, 'hint')}`,
  ];
  if (streak > 0) lines.push(`${plural(streak, 'day')} in a row`);
  if (url) lines.push(url);
  return lines.join('\n');
}
