// Hardcore mode: a harsher way to play free runs.
//
//   permadeath     0 HP ends the run (normally you retreat to half HP)
//   a clock        every word you cast in battle has a time limit; when it
//                  runs out the turn is wasted and the monster hits you
//   one retry      the first wrong answer on each clue is free; after that
//                  every wrong answer costs HP (but never your last HP, the
//                  same floor hints have, so a typo cannot kill you)
//   a reward       the final Score is multiplied
//
// The numbers live here, in one place, so the game logic, the picker text and
// the How-to-play card cannot disagree. Hardcore applies to free play only:
// the Daily Challenge is the same standard run for everybody.

export const HARDCORE = {
  turnSeconds: 15,
  freeWrongGuesses: 1,
  wrongGuessHp: 2,
  scoreMultiplier: 1.5,
};

/** What the player is promised, one short sentence per rule. */
export function describeHardcore(rules = HARDCORE) {
  const free = rules.freeWrongGuesses;
  return [
    'No retreat: at 0 HP the run is over.',
    `${rules.turnSeconds} seconds for each word in battle, or the monster hits you.`,
    `${free === 1 ? 'One free retry' : `${free} free retries`} per clue; after that a wrong answer costs ${rules.wrongGuessHp} HP.`,
    `Final Score ×${rules.scoreMultiplier}.`,
  ];
}

/** The Score a finished hardcore run is worth. */
export function finalScore(score, hardcore, rules = HARDCORE) {
  return hardcore ? Math.round(score * rules.scoreMultiplier) : score;
}

// ---- results kept on this device -------------------------------------------

export const STATS_KEY = 'wordsmith-hardcore-stats';
export const PREF_KEY = 'wordsmith-hardcore';

const EMPTY_STATS = { wins: 0, falls: 0, best: 0 };

function count(value) {
  return Number.isInteger(value) && value >= 0 ? value : 0;
}

/** Saved hardcore results, with anything malformed treated as zero. */
export function loadStats(storage) {
  try {
    const raw = JSON.parse(storage.getItem(STATS_KEY) ?? 'null');
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return { ...EMPTY_STATS };
    return { wins: count(raw.wins), falls: count(raw.falls), best: count(raw.best) };
  } catch {
    return { ...EMPTY_STATS };
  }
}

/** Saves [stats]; returns false if the browser would not take it. */
export function saveStats(storage, stats) {
  try {
    storage.setItem(STATS_KEY, JSON.stringify({ wins: stats.wins, falls: stats.falls, best: stats.best }));
    return true;
  } catch {
    return false;
  }
}

/**
 * Adds a finished hardcore run: a win (with its final Score) or a fall.
 * Returns new stats; the input is not modified.
 */
export function recordRun(stats, { won, score = 0 }) {
  return won
    ? { ...stats, wins: stats.wins + 1, best: Math.max(stats.best, count(score)) }
    : { ...stats, falls: stats.falls + 1 };
}
