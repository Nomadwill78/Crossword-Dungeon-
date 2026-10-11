import test from 'node:test';
import assert from 'node:assert/strict';
import { DungeonRun } from '../../src/dungeon.js';
import { HINT_LEVELS } from '../../src/hints.js';
import { LEVEL_ONE } from '../../src/wordlist.js';

/** A fresh run and a corridor the player can attempt right now. */
function setup() {
  const run = new DungeonRun(LEVEL_ONE);
  const open = run.placements.find((p) => run.canHint(p.index));
  assert.ok(open, 'the entrance opens at least one corridor');
  return { run, open, index: open.index };
}

const hiddenCount = (run, index) => run.hintPattern(index).filter((ch) => ch === null).length;

test('hint levels match the design: cheap, moderate, flavor', () => {
  assert.deepEqual(HINT_LEVELS.map((h) => h.level), [1, 2, 3]);
  const level2 = HINT_LEVELS[1];
  assert.equal(level2.cost.hp, 2, 'a letter costs 2 HP...');
  assert.equal(level2.cost.score, 50, '...or 50 Score');
  assert.ok(HINT_LEVELS[0].cost.score < level2.cost.score, 'level 1 is the cheap one');
  assert.ok(HINT_LEVELS[0].cost.hp <= level2.cost.hp);
});

test('every level-one entry has lore that does not give the word away', () => {
  for (const entry of LEVEL_ONE.entries) {
    assert.ok(entry.lore, `${entry.word} has a lore hint`);
    assert.ok(!entry.lore.toUpperCase().includes(entry.word), `${entry.word}'s lore does not contain the word`);
    assert.ok(entry.lore.length < entry.clue.length + 40, `${entry.word}'s lore is short`);
  }
});

test('hints only apply to corridors you can attempt and have not solved', () => {
  const { run, index } = setup();
  const entrance = run.placements.find((p) => p.isEntrance);
  assert.equal(run.buyHint(entrance.index, 1, 'score').reason, 'unavailable', 'a solved corridor has no hints');

  const locked = run.placements.find((p) => !run.isReachable(p.index));
  if (locked) assert.equal(run.buyHint(locked.index, 1, 'score').reason, 'unavailable', 'a locked corridor has no hints');
  assert.equal(run.buyHint(index, 9, 'score').reason, 'unavailable', 'there is no level 9');
  assert.equal(run.buyHint(index, 1, 'gems').reason, 'bad_currency');
});

test('level 1 shows the vowels and costs the cheap price', () => {
  const { run, open, index } = setup();
  run.score = 100;
  const before = hiddenCount(run, index);
  const result = run.buyHint(index, 1, 'score');
  assert.ok(result.ok);
  assert.deepEqual(result.paid, { currency: 'score', amount: HINT_LEVELS[0].cost.score });
  assert.equal(run.score, 100 - HINT_LEVELS[0].cost.score);

  const pattern = run.hintPattern(index);
  [...open.word].forEach((ch, i) => {
    if ('AEIOU'.includes(ch)) assert.equal(pattern[i], ch, `vowel ${ch} is shown`);
  });
  assert.ok(hiddenCount(run, index) < before || before === hiddenCount(run, index), 'never hides anything');
  assert.equal(run.buyHint(index, 1, 'score').reason, 'already_bought', 'level 1 is bought once');
  assert.equal(run.hintsUsed, 1);
});

test('levels unlock in order', () => {
  const { run, index } = setup();
  run.score = 500;
  assert.equal(run.buyHint(index, 2, 'score').reason, 'locked', 'cannot skip to a letter');
  assert.equal(run.buyHint(index, 3, 'score').reason, 'locked', 'cannot skip to lore');
  assert.equal(run.score, 500, 'a refused hint costs nothing');
  run.buyHint(index, 1, 'score');
  assert.equal(run.buyHint(index, 3, 'score').reason, 'locked', 'lore needs a letter first');
  assert.ok(run.buyHint(index, 2, 'score').ok);
  assert.ok(run.buyHint(index, 3, 'score').ok);
});

test('level 2 reveals exactly one new letter on the map, and never the whole word', () => {
  const { run, open, index } = setup();
  run.score = 10_000;
  run.buyHint(index, 1, 'score');
  let guard = 0;
  while (run.hintOptions(index)[1].status === 'available' && guard++ < 20) {
    const before = hiddenCount(run, index);
    const result = run.buyHint(index, 2, 'score');
    assert.ok(result.ok);
    assert.equal(hiddenCount(run, index), before - 1, 'one more letter becomes known');
    const [r, c] = open.cells[result.letterIndex];
    assert.equal(run.grid[r][c].revealed, true, 'and it is filled in on the grid');
  }
  assert.ok(hiddenCount(run, index) >= 1, 'at least one letter is always left to solve');
  assert.equal(run.hintOptions(index)[1].status, 'done', 'the level reports it has nothing left');
  assert.equal(run.buyHint(index, 2, 'score').reason, 'already_bought');
  assert.equal(run.isSolved(index), false, 'hints never solve the corridor');
});

test('level 3 reveals the lore text only after it is bought', () => {
  const { run, open, index } = setup();
  run.score = 1000;
  run.buyHint(index, 1, 'score');
  run.buyHint(index, 2, 'score');
  assert.equal(run.hintOptions(index)[2].text, null, 'lore is hidden before purchase');
  run.buyHint(index, 3, 'score');
  assert.equal(run.hintOptions(index)[2].text, open.lore);
});

test('Score can be swapped for HP, but never your last HP', () => {
  const { run, index } = setup();
  const hp = run.playerHP;
  assert.ok(run.buyHint(index, 1, 'hp').ok);
  assert.equal(run.playerHP, hp - HINT_LEVELS[0].cost.hp, 'HP paid');
  assert.equal(run.score, 0, 'Score untouched');

  run.playerHP = 2;
  assert.equal(run.buyHint(index, 2, 'hp').reason, 'cannot_afford', '2 HP hint at 2 HP would leave 0');
  assert.equal(run.playerHP, 2, 'and nothing was taken');
  run.playerHP = 3;
  assert.ok(run.buyHint(index, 2, 'hp').ok);
  assert.equal(run.playerHP, 1, 'one HP survives');
  assert.equal(run.isDefeated(), false, 'a hint can never defeat you');
});

test('Score cannot go negative', () => {
  const { run, index } = setup();
  run.score = HINT_LEVELS[0].cost.score - 1;
  assert.equal(run.buyHint(index, 1, 'score').reason, 'cannot_afford');
  assert.equal(run.score, HINT_LEVELS[0].cost.score - 1);
  assert.equal(run.hintOptions(index)[0].canPayScore, false);
  assert.equal(run.hintOptions(index)[0].canPayHP, true);
});

test('hints do not change what the right answer is', () => {
  const { run, open, index } = setup();
  run.score = 1000;
  run.buyHint(index, 1, 'score');
  run.buyHint(index, 2, 'score');
  assert.equal(run.attemptSolve(index, 'zzzzz').correct, false);
  assert.equal(run.attemptSolve(index, open.word).correct, true);
});

test('hint state is per corridor', () => {
  const { run, index } = setup();
  const other = run.placements.find((p) => p.index !== index && run.canHint(p.index));
  run.score = 100;
  run.buyHint(index, 1, 'score');
  if (other) assert.equal(run.hintOptions(other.index)[0].status, 'available', 'another corridor is untouched');
});

test('the game rules the how-to-play text promises are the real ones', () => {
  const run = new DungeonRun(LEVEL_ONE);
  const open = run.placements.find((p) => run.canHint(p.index));
  const hp = run.playerHP;
  const score = run.score;
  assert.equal(run.attemptSolve(open.index, 'WRONG').correct, false);
  assert.equal(run.playerHP, hp, 'a wrong crossword answer costs no HP');
  assert.equal(run.score, score, 'and no Score');
  assert.equal(run.isVictory(), false);
  for (const p of run.monsterPlacements()) run.cleared.add(p.index);
  assert.equal(run.isVictory(), true, 'clearing every monster corridor wins');
});
