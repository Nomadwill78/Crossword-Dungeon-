// The Daily Challenge: one dungeon a day, the same for everyone.
//
// A "day" is a UTC calendar date, so a player in Tokyo and a player in Lima
// are on the same puzzle at the same moment. The date is the seed: it fixes the
// grid layout, the hero, and every dice roll in the run (see rng.js). Nothing
// here touches the page; main.js wires it up.
//
// There are two dailies a day, each with its own dungeon, hero, saved results
// and streak: the standard one, and **Daily Hardcore** (the same hardcore rules
// as free play: no retreat, a clock, one free retry, x1.5 Score). They are
// different puzzles, not one puzzle played two ways, so a hardcore daily has its
// own seed.
//
// Results are kept on this device (there is no server): the first run finished
// each day is the one that counts, so replaying with the answers already known
// cannot improve it. Replays are practice. In Hardcore a run is finished when it
// is won or when the hero falls.

import { HERO_LIST } from './heroes.js';
import { hashSeed } from './rng.js';

/** The two dailies. */
export const MODES = ['normal', 'hardcore'];
const STORAGE_KEYS = { normal: 'wordsmith-daily', hardcore: 'wordsmith-daily-hardcore' };
/** The standard daily's storage key (kept for callers that predate the second daily). */
export const STORAGE_KEY = STORAGE_KEYS.normal;
// Changing a salt changes every dungeon for that daily, so these never change
// once players have results saved under them.
const SALTS = { normal: 'wordsmith-daily-v1', hardcore: 'wordsmith-daily-hardcore-v1' };
const DAY_MS = 24 * 60 * 60 * 1000;
const KEY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const MAX_STORED_DAYS = 400;

/** The daily key for a moment in time: its UTC date, "YYYY-MM-DD". */
export function dailyKey(date = new Date()) {
  return date.toISOString().slice(0, 10);
}

function checkedMode(mode) {
  if (!MODES.includes(mode)) throw new Error(`unknown daily mode: ${mode}`);
  return mode;
}

/** Where a daily's results are kept. */
export function storageKeyFor(mode = 'normal') {
  return STORAGE_KEYS[checkedMode(mode)];
}

/** The string every part of that day's run is seeded from. */
export function dailySeed(key, mode = 'normal') {
  return `${SALTS[checkedMode(mode)]}:${key}`;
}

/** Today's hero. Fixed per day (and per daily) so everybody plays the same character. */
export function dailyHero(key, mode = 'normal') {
  return HERO_LIST[hashSeed(`${dailySeed(key, mode)}:hero`) % HERO_LIST.length];
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

const OUTCOMES = ['won', 'fell'];

/** A hardcore result says how the run ended; a standard one has no `outcome`. */
function validResult(r, mode = 'normal') {
  return Boolean(
    r && typeof r === 'object'
    && Number.isFinite(r.score)
    && Number.isInteger(r.retreats) && r.retreats >= 0
    && Number.isInteger(r.hintsUsed) && r.hintsUsed >= 0
    && typeof r.hero === 'string'
    && (mode === 'hardcore' ? OUTCOMES.includes(r.outcome) : r.outcome === undefined)
  );
}

function cleanResult(r) {
  const clean = { score: r.score, retreats: r.retreats, hintsUsed: r.hintsUsed, hero: r.hero };
  if (r.outcome !== undefined) clean.outcome = r.outcome;
  return clean;
}

/**
 * Saved results, keyed by day. Anything malformed (a hand-edited or old save)
 * is ignored rather than trusted. [storage] is a localStorage-like object.
 */
export function loadResults(storage, mode = 'normal') {
  try {
    const raw = JSON.parse(storage.getItem(storageKeyFor(mode)) ?? '{}');
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {};
    const results = {};
    for (const [key, value] of Object.entries(raw)) {
      if (KEY_PATTERN.test(key) && validResult(value, mode)) results[key] = cleanResult(value);
    }
    return results;
  } catch {
    return {};
  }
}

/** Saves [results], keeping the most recent days. Returns false if it could not. */
export function saveResults(storage, results, mode = 'normal') {
  const kept = Object.keys(results).sort().slice(-MAX_STORED_DAYS);
  const trimmed = Object.fromEntries(kept.map((key) => [key, results[key]]));
  try {
    storage.setItem(storageKeyFor(mode), JSON.stringify(trimmed));
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
export function recordResult(results, key, result, mode = 'normal') {
  if (!KEY_PATTERN.test(key) || !validResult(result, mode)) return { results, official: false };
  if (results[key]) return { results, official: false };
  return { results: { ...results, [key]: cleanResult(result) }, official: true };
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
export function shareText({ key, hero, result, streak, url = '', mode = 'normal' }) {
  const hardcore = mode === 'hardcore';
  const lines = [
    `Wordsmith's Gambit — Daily ${hardcore ? 'Hardcore ' : ''}${key}`,
    `${hero.name}: ${result.score} Score`,
    hardcore
      ? `${result.outcome === 'won' ? 'Cleared' : 'Fell'} · ${plural(result.hintsUsed, 'hint')}`
      : `${plural(result.retreats, 'retreat')} · ${plural(result.hintsUsed, 'hint')}`,
  ];
  if (streak > 0) lines.push(`${plural(streak, 'day')} in a row`);
  if (url) lines.push(url);
  return lines.join('\n');
}
