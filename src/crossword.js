// Crossword generator: turns a list of {word, clue, ...meta} entries into an
// interlocking grid, à la the classic greedy crossword-construction algorithm
// (place longest words first, cross new words through existing letters,
// validate no illegal adjacencies, retry/fallback for anything that won't fit).

import { mulberry32 } from './rng.js';

const GRID = 31; // virtual working grid, trimmed to bounding box at the end
const CENTER = Math.floor(GRID / 2);

function key(r, c) {
  return `${r},${c}`;
}

function inBounds(r, c) {
  return r >= 0 && r < GRID && c >= 0 && c < GRID;
}

/**
 * Attempt a single generation pass. Returns { placements, disconnectedCount }.
 * placements: [{ word, clue, meta, row, col, dir: 'across'|'down' }]
 */
function attemptGeneration(entries, rng) {
  const cells = new Map(); // key -> { letter, across: entryIndex|null, down: entryIndex|null }
  const placements = [];
  let disconnectedCount = 0;

  // Ties are broken by a random key drawn up front. (A comparator that calls
  // rng() would make the result depend on the order a browser's sort happens
  // to compare things in, and the Daily Challenge must build the same grid in
  // every browser.)
  const order = entries
    .map((e, i) => ({ e, i, tie: rng() }))
    .sort((a, b) => b.e.word.length - a.e.word.length || a.tie - b.tie);

  function getCell(r, c) {
    return cells.get(key(r, c));
  }

  function canPlace(word, row, col, dir) {
    let intersections = 0;
    for (let i = 0; i < word.length; i++) {
      const r = dir === 'down' ? row + i : row;
      const c = dir === 'across' ? col + i : col;
      if (!inBounds(r, c)) return null;
      const existing = getCell(r, c);
      if (existing) {
        if (existing.letter !== word[i]) return null;
        if (dir === 'across' && existing.across != null) return null; // two across words on same cell
        if (dir === 'down' && existing.down != null) return null;
        intersections++;
      } else {
        // empty cell: perpendicular neighbours must also be empty so we don't
        // accidentally create an unintended adjacent word
        if (dir === 'across') {
          if (getCell(r - 1, c) || getCell(r + 1, c)) return null;
        } else {
          if (getCell(r, c - 1) || getCell(r, c + 1)) return null;
        }
      }
    }
    // cells immediately before/after the word must be empty (no run-ons)
    const beforeR = dir === 'down' ? row - 1 : row;
    const beforeC = dir === 'across' ? col - 1 : col;
    const afterR = dir === 'down' ? row + word.length : row;
    const afterC = dir === 'across' ? col + word.length : col;
    if (getCell(beforeR, beforeC)) return null;
    if (getCell(afterR, afterC)) return null;
    return intersections;
  }

  function place(entryIndex, entry, row, col, dir) {
    for (let i = 0; i < entry.word.length; i++) {
      const r = dir === 'down' ? row + i : row;
      const c = dir === 'across' ? col + i : col;
      const existing = getCell(r, c) || { letter: entry.word[i], across: null, down: null };
      existing.letter = entry.word[i];
      existing[dir] = entryIndex;
      cells.set(key(r, c), existing);
    }
    placements[entryIndex] = { ...entry, row, col, dir };
  }

  function findCandidates(word) {
    const candidates = [];
    for (const [k, cell] of cells) {
      const [cr, cc] = k.split(',').map(Number);
      for (let i = 0; i < word.length; i++) {
        if (word[i] !== cell.letter) continue;
        // must cross perpendicular to any orientation already occupying this cell
        if (cell.across == null) {
          const row = cr;
          const col = cc - i;
          const score = canPlace(word, row, col, 'across');
          if (score != null && score > 0) candidates.push({ row, col, dir: 'across', score, tie: rng() });
        }
        if (cell.down == null) {
          const row = cr - i;
          const col = cc;
          const score = canPlace(word, row, col, 'down');
          if (score != null && score > 0) candidates.push({ row, col, dir: 'down', score, tie: rng() });
        }
      }
    }
    candidates.sort((a, b) => b.score - a.score || a.tie - b.tie);
    return candidates;
  }

  // seed with the longest word, horizontally, at the grid center
  const first = order[0];
  place(first.i, first.e, CENTER, CENTER - Math.floor(first.e.word.length / 2), 'across');

  const remaining = order.slice(1);
  const retryQueue = [];

  for (const { e, i } of remaining) {
    const candidates = findCandidates(e.word);
    if (candidates.length > 0) {
      const best = candidates[0];
      place(i, e, best.row, best.col, best.dir);
    } else {
      retryQueue.push({ e, i });
    }
  }

  // second pass: more letters are on the board now, some may fit
  const stillStuck = [];
  for (const { e, i } of retryQueue) {
    const candidates = findCandidates(e.word);
    if (candidates.length > 0) {
      const best = candidates[0];
      place(i, e, best.row, best.col, best.dir);
    } else {
      stillStuck.push({ e, i });
    }
  }

  // fallback: drop anything left over into open space below the grid so it's
  // never silently lost, flagged as a "secret passage" accessible from the start
  let fallbackRow = GRID; // grows past the virtual bound; trimmed later since
  // trimming happens over the bounding box of *used* cells including these.
  for (const { e, i } of stillStuck) {
    fallbackRow += 2;
    const row = fallbackRow;
    const col = CENTER - Math.floor(e.word.length / 2);
    place(i, e, row, col, 'across');
    disconnectedCount++;
  }

  return { placements, disconnectedCount, cells };
}

/**
 * Generate an interlocking crossword grid from theme entries.
 * @param {Array<{word:string, clue:string}>} rawEntries
 * @param {object} [options]
 * @param {number} [options.attempts=8] how many randomized passes to try
 * @param {number} [options.seed] deterministic seed: the same seed and entries
 *   give the same grid in every browser
 * @returns {{width:number, height:number, grid: Array<Array<Cell|null>>, placements: Array<Placement>}}
 */
export function generateCrossword(rawEntries, options = {}) {
  const attempts = options.attempts ?? 8;
  const entries = rawEntries.map((e) => ({ ...e, word: e.word.toUpperCase() }));

  let best = null;
  for (let a = 0; a < attempts; a++) {
    const seed = (options.seed ?? Date.now()) + a * 7919;
    const rng = mulberry32(seed);
    const result = attemptGeneration(entries, rng);
    if (!best || result.disconnectedCount < best.disconnectedCount) {
      best = result;
      if (best.disconnectedCount === 0) break;
    }
  }

  // compute bounding box over all placed cells
  let minR = Infinity;
  let minC = Infinity;
  let maxR = -Infinity;
  let maxC = -Infinity;
  for (const [k] of best.cells) {
    const [r, c] = k.split(',').map(Number);
    minR = Math.min(minR, r);
    minC = Math.min(minC, c);
    maxR = Math.max(maxR, r);
    maxC = Math.max(maxC, c);
  }

  const width = maxC - minC + 1;
  const height = maxR - minR + 1;
  const grid = Array.from({ length: height }, () => Array(width).fill(null));

  for (const [k, cell] of best.cells) {
    const [r, c] = k.split(',').map(Number);
    grid[r - minR][c - minC] = { letter: cell.letter, number: null, revealed: false };
  }

  const placements = best.placements.map((p, idx) => ({
    ...p,
    row: p.row - minR,
    col: p.col - minC,
    index: idx,
    disconnected: p.row - minR >= height, // placeholder, corrected below
  }));

  // crossword numbering: a cell starts a number if it begins an across
  // and/or down word
  let num = 1;
  const startsAcross = new Set();
  const startsDown = new Set();
  for (const p of placements) {
    if (p.dir === 'across') startsAcross.add(key(p.row, p.col));
    else startsDown.add(key(p.row, p.col));
  }
  for (let r = 0; r < height; r++) {
    for (let c = 0; c < width; c++) {
      const k = key(r, c);
      if (startsAcross.has(k) || startsDown.has(k)) {
        grid[r][c].number = num;
        for (const p of placements) {
          if (p.row === r && p.col === c) p.number = num;
        }
        num++;
      }
    }
  }

  // recompute disconnected flag: a placement is "disconnected" (a secret
  // passage) if none of its cells are shared with any other placement
  const cellOwners = new Map();
  for (const p of placements) {
    for (let i = 0; i < p.word.length; i++) {
      const r = p.dir === 'down' ? p.row + i : p.row;
      const c = p.dir === 'across' ? p.col + i : p.col;
      const k = key(r, c);
      if (!cellOwners.has(k)) cellOwners.set(k, []);
      cellOwners.get(k).push(p.index);
    }
  }
  for (const p of placements) {
    let shared = false;
    for (let i = 0; i < p.word.length; i++) {
      const r = p.dir === 'down' ? p.row + i : p.row;
      const c = p.dir === 'across' ? p.col + i : p.col;
      if (cellOwners.get(key(r, c)).length > 1) shared = true;
    }
    p.disconnected = !shared;
  }

  for (const p of placements) {
    p.cells = [];
    for (let i = 0; i < p.word.length; i++) {
      const r = p.dir === 'down' ? p.row + i : p.row;
      const c = p.dir === 'across' ? p.col + i : p.col;
      p.cells.push([r, c]);
    }
  }

  return { width, height, grid, placements };
}
