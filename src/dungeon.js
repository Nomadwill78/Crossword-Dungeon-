import { generateCrossword } from './crossword.js';

const PLAYER_MAX_HP = 40;

function cellKey(r, c) {
  return `${r},${c}`;
}

/**
 * A dungeon run: the crossword grid IS the map. Each placement is a corridor
 * that must be "solved" (its clue answered) before it can be entered. Once
 * solved, a monster corridor drops the player into battle; a reward corridor
 * pays out immediately.
 */
export class DungeonRun {
  constructor(levelData) {
    this.level = levelData;
    const { grid, placements, width, height } = generateCrossword(levelData.entries);
    this.grid = grid;
    this.placements = placements;
    this.width = width;
    this.height = height;

    this.solved = new Set();
    this.cleared = new Set();
    this.playerHP = PLAYER_MAX_HP;
    this.playerMaxHP = PLAYER_MAX_HP;
    this.score = 0;
    this.bonusLetters = 0;

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
