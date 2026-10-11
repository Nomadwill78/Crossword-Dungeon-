import { generateCrossword } from './crossword.js';
import { HINT_LEVELS, MIN_HP_AFTER_HINT, isVowel } from './hints.js';
import { freeHintLevels, maxHpBonus } from './heroes.js';
import { hashSeed, randomInt, seededRng } from './rng.js';

const PLAYER_MAX_HP = 40;

/** Losing a battle ends it as a retreat: you keep the corridor but your HP is
 * reset to this fraction of max. */
export const RETREAT_HP_FRACTION = 0.5;

/** How many candidate layouts to generate before keeping the best one. */
const LAYOUT_TRIES = 8;

/** Negative if [a] sorts before [b] (compared element by element), positive if after, 0 if equal. */
function firstDifference(a, b) {
  for (let i = 0; i < a.length; i += 1) {
    if (a[i] !== b[i]) return a[i] - b[i];
  }
  return 0;
}

/**
 * Builds the dungeon grid: several candidate layouts, keeping the most
 * compact (fewest cut-off "secret passage" corridors, then the smallest
 * longest side, then the smallest area). Cells are fluid, so a 26-wide grid
 * would mean tiny cells on a phone. With a seed the candidates, and so the
 * winner, are the same for everyone.
 */
function buildGrid(entries, seed) {
  let best = null;
  for (let k = 0; k < LAYOUT_TRIES; k += 1) {
    const gridSeed = seed === null ? Math.floor(Math.random() * 2 ** 32) : hashSeed(`${seed}:grid:${k}`);
    const candidate = generateCrossword(entries, { seed: gridSeed });
    const cutOff = candidate.placements.filter((p) => p.disconnected).length;
    const rank = [cutOff, Math.max(candidate.width, candidate.height), candidate.width * candidate.height];
    const better = !best || firstDifference(rank, best.rank) < 0;
    if (better) best = { candidate, rank };
  }
  return best.candidate;
}

function cellKey(r, c) {
  return `${r},${c}`;
}

/**
 * A dungeon run: the crossword grid IS the map. Each placement is a corridor
 * that must be "solved" (its clue answered) before it can be entered. Once
 * solved, a monster corridor drops the player into battle; a reward corridor
 * pays out immediately.
 *
 * `hero` is optional: with none, the run has no perks (the baseline the rules
 * are written against). With one, its perk adjusts max HP and hint costs here
 * and word damage in combat (see heroes.js).
 *
 * `options.seed` (a string) makes the run repeatable: the same seed gives the
 * same grid, the same starting letters in each battle, the same monster hits
 * and the same hint letters. The Daily Challenge uses the date as the seed.
 * Without one, everything is random.
 */
export class DungeonRun {
  constructor(levelData, hero = null, options = {}) {
    this.level = levelData;
    this.hero = hero;
    this.seed = options.seed ?? null;
    this.rng = this.seed === null ? Math.random : seededRng(`${this.seed}:run`);
    this.battleCounts = new Map(); // placement index -> battles started there
    const { grid, placements, width, height } = buildGrid(levelData.entries, this.seed);
    this.grid = grid;
    this.placements = placements;
    this.width = width;
    this.height = height;

    this.solved = new Set();
    this.cleared = new Set();
    this.playerMaxHP = PLAYER_MAX_HP + maxHpBonus(hero);
    this.playerHP = this.playerMaxHP;
    this.score = 0;
    this.bonusLetters = 0;
    this.hintsUsed = 0;
    this.retreats = 0;
    this.hintState = new Map(); // placement index -> { vowels, letters, lore }

    this._buildAdjacency();

    // auto-solve the entrance corridor so the player always has somewhere to start
    const entrance = this.placements.find((p) => p.isEntrance);
    if (entrance) {
      this._reveal(entrance);
      this.solved.add(entrance.index);
      this.cleared.add(entrance.index);
    }
  }

  _buildAdjacency() {
    const owners = new Map(); // cellKey -> [placementIndex,...]
    for (const p of this.placements) {
      for (const [r, c] of p.cells) {
        const k = cellKey(r, c);
        if (!owners.has(k)) owners.set(k, []);
        owners.get(k).push(p.index);
      }
    }
    for (const p of this.placements) p.neighbors = new Set();
    for (const [, idxs] of owners) {
      for (const a of idxs) {
        for (const b of idxs) {
          if (a !== b) this.placements[a].neighbors.add(b);
        }
      }
    }
  }

  _reveal(placement) {
    for (const [r, c] of placement.cells) {
      this.grid[r][c].revealed = true;
    }
  }

  placement(index) {
    return this.placements[index];
  }

  isSolved(index) {
    return this.solved.has(index);
  }

  isCleared(index) {
    return this.cleared.has(index);
  }

  /** A corridor can be attempted once it's adjacent to something already
   * solved, or it's a "secret passage" with no shared cells at all (so
   * nothing is ever permanently unreachable). */
  isReachable(index) {
    const p = this.placements[index];
    if (this.solved.has(index)) return true;
    if (p.disconnected) return true;
    for (const n of p.neighbors) {
      if (this.solved.has(n)) return true;
    }
    return false;
  }

  cluesByDirection(dir) {
    return this.placements
      .filter((p) => p.dir === dir)
      .sort((a, b) => a.number - b.number);
  }

  /**
   * Attempt to solve a corridor's clue.
   * @returns {{correct:boolean, placement?:object, outcome?:'battle'|'reward'}}
   */
  attemptSolve(index, guess) {
    const p = this.placements[index];
    if (!p || this.solved.has(index)) return { correct: false };
    const normalized = guess.trim().toUpperCase();
    if (normalized !== p.word) return { correct: false };

    this.solved.add(index);
    this._reveal(p);

    if (p.monster) {
      return { correct: true, placement: p, outcome: 'battle' };
    }
    if (p.reward) {
      this._applyReward(p.reward);
      this.cleared.add(index);
      return { correct: true, placement: p, outcome: 'reward' };
    }
    this.cleared.add(index);
    return { correct: true, placement: p, outcome: 'none' };
  }

  _applyReward(reward) {
    if (reward.type === 'heal') {
      this.playerHP = Math.min(this.playerMaxHP, this.playerHP + reward.amount);
    } else if (reward.type === 'score') {
      this.score += reward.amount;
    } else if (reward.type === 'letters') {
      this.bonusLetters += reward.amount;
    }
  }

  markBattleResolved(index, { won, remainingPlayerHP, scoreGained }) {
    this.playerHP = Math.max(0, Math.min(this.playerMaxHP, remainingPlayerHP));
    this.score += scoreGained ?? 0;
    if (won) this.cleared.add(index);
    else this.retreats += 1;
  }

  /**
   * Randomness for the next battle at corridor [index]. Seeded runs get a
   * generator of their own for each (corridor, attempt), so the same fight
   * deals the same letters to everyone, however they got there.
   */
  battleRng(index) {
    const attempt = (this.battleCounts.get(index) ?? 0) + 1;
    this.battleCounts.set(index, attempt);
    return this.seed === null ? Math.random : seededRng(`${this.seed}:battle:${index}:${attempt}`);
  }

  // ---- hints ---------------------------------------------------------

  _hint(index) {
    if (!this.hintState.has(index)) {
      this.hintState.set(index, { vowels: false, letters: 0, lore: false });
    }
    return this.hintState.get(index);
  }

  /** Hints are for corridors you can attempt right now and have not solved. */
  canHint(index) {
    const p = this.placements[index];
    return !!p && !this.solved.has(index) && this.isReachable(index);
  }

  /** True if the player can already see letter `i` of the corridor: it is
   * shown on the map, or it is a vowel and the vowel hint was bought. */
  isLetterKnown(index, i) {
    const p = this.placements[index];
    const [r, c] = p.cells[i];
    if (this.grid[r][c].revealed) return true;
    return this._hint(index).vowels && isVowel(p.word[i]);
  }

  /** The word as the player currently knows it: a letter, or null if hidden. */
  hintPattern(index) {
    const p = this.placements[index];
    return [...p.word].map((ch, i) => (this.isLetterKnown(index, i) ? ch : null));
  }

  /** Letter positions a Level 2 hint could still reveal. */
  _hiddenPositions(index) {
    const p = this.placements[index];
    const hidden = [];
    for (let i = 0; i < p.word.length; i++) {
      if (!this.isLetterKnown(index, i)) hidden.push(i);
    }
    return hidden;
  }

  /**
   * What the hint panel should show for a corridor: one entry per level with
   * its status ('locked' | 'available' | 'done') and what the player can pay
   * with right now.
   */
  hintOptions(index) {
    const state = this._hint(index);
    const p = this.placements[index];
    return HINT_LEVELS.map((base) => {
      // A hero perk can make a level free; everything below uses the real price.
      const free = freeHintLevels(this.hero).includes(base.level);
      const def = free ? { ...base, cost: { score: 0, hp: 0 } } : base;
      let status;
      if (def.level === 1) status = state.vowels ? 'done' : 'available';
      else if (def.level === 2) {
        if (!state.vowels) status = 'locked';
        else status = this._hiddenPositions(index).length >= 2 ? 'available' : 'done';
      } else {
        if (state.letters === 0) status = 'locked';
        else status = state.lore ? 'done' : 'available';
      }
      return {
        ...def,
        free,
        status,
        canPayScore: this.score >= def.cost.score,
        canPayHP: this.playerHP - def.cost.hp >= MIN_HP_AFTER_HINT,
        // the lore text is only exposed once bought
        text: def.level === 3 && state.lore ? p.lore ?? null : null,
      };
    });
  }

  /**
   * Buy a hint.
   * @param {number} index corridor
   * @param {1|2|3} level
   * @param {'score'|'hp'} currency what to pay with
   * @returns {{ok:boolean, reason?:string, paid?:{currency:string, amount:number}, letterIndex?:number}}
   */
  buyHint(index, level, currency) {
    if (!this.canHint(index)) return { ok: false, reason: 'unavailable' };
    const option = this.hintOptions(index).find((o) => o.level === level);
    if (!option) return { ok: false, reason: 'unavailable' };
    if (option.status === 'locked') return { ok: false, reason: 'locked' };
    if (option.status === 'done') return { ok: false, reason: 'already_bought' };
    if (currency !== 'score' && currency !== 'hp') return { ok: false, reason: 'bad_currency' };
    if (currency === 'score' ? !option.canPayScore : !option.canPayHP) {
      return { ok: false, reason: 'cannot_afford' };
    }

    const amount = option.cost[currency];
    if (currency === 'score') this.score -= amount;
    else this.playerHP -= amount;
    this.hintsUsed += 1;

    const state = this._hint(index);
    if (level === 1) {
      state.vowels = true;
    } else if (level === 2) {
      const hidden = this._hiddenPositions(index);
      const letterIndex = hidden[randomInt(this.rng, hidden.length)];
      const [r, c] = this.placements[index].cells[letterIndex];
      this.grid[r][c].revealed = true;
      state.letters += 1;
      return { ok: true, paid: { currency, amount }, letterIndex };
    } else {
      state.lore = true;
    }
    return { ok: true, paid: { currency, amount } };
  }

  monsterPlacements() {
    return this.placements.filter((p) => p.monster);
  }

  isVictory() {
    return this.monsterPlacements().every((p) => this.cleared.has(p.index));
  }

  isDefeated() {
    return this.playerHP <= 0;
  }
}
