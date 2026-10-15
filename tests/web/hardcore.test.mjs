import test from 'node:test';
import assert from 'node:assert/strict';
import {
  HARDCORE, describeHardcore, finalScore, loadStats, saveStats, recordRun, STATS_KEY,
} from '../../src/hardcore.js';
import { DungeonRun } from '../../src/dungeon.js';
import { BattleSession } from '../../src/combat.js';
import { renderRulesHtml } from '../../src/rules.js';
import { HINT_LEVELS } from '../../src/hints.js';
import { HEROES } from '../../src/heroes.js';
import { LEVEL_ONE } from '../../src/wordlist.js';

const text = (html) => html.replace(/<[^>]+>/g, ' ');
const monster = { name: 'Dummy', hp: 100, attack: 6 };

function openClue(run) {
  const p = run.placements.find((x) => run.canHint(x.index));
  assert.ok(p, 'a clue is open at the start');
  return p;
}

function memoryStorage(initial = {}) {
  const data = { ...initial };
  return { data, getItem: (k) => (k in data ? data[k] : null), setItem: (k, v) => { data[k] = String(v); } };
}

// ---- the rule text and constants ------------------------------------------------

test('the promises are generated from the constants', () => {
  const lines = describeHardcore(HARDCORE).join(' ');
  assert.match(lines, new RegExp(`${HARDCORE.turnSeconds} seconds`));
  assert.match(lines, new RegExp(`costs ${HARDCORE.wrongGuessHp} HP`));
  assert.match(lines, new RegExp(`\\u00d7${HARDCORE.scoreMultiplier}`));
  assert.match(lines, /No retreat/);
  const custom = describeHardcore({ turnSeconds: 9, freeWrongGuesses: 3, wrongGuessHp: 4, scoreMultiplier: 2 }).join(' ');
  assert.match(custom, /9 seconds/);
  assert.match(custom, /3 free retries/);
  assert.match(custom, /costs 4 HP/);
  assert.match(custom, /×2/);
});

test('the final score is multiplied in hardcore only, and rounds', () => {
  assert.equal(finalScore(100, false), 100);
  assert.equal(finalScore(100, true), 150);
  assert.equal(finalScore(101, true), 152, '151.5 rounds up');
  assert.equal(finalScore(0, true), 0);
  assert.equal(finalScore(10, true, { scoreMultiplier: 3 }), 30);
});

// ---- the battle clock ---------------------------------------------------------------

test('running out of time wastes the turn exactly like a rejected word', () => {
  const make = () => new BattleSession(monster, new Set(['CAT']), new Set(), 40, 40, 8, {}, () => 0.5);
  const timed = make();
  const rejected = make();
  for (const b of [timed, rejected]) { b.rack = [{ id: 'a', letter: 'Z' }, { id: 'b', letter: 'Q' }]; b.selectTile('a'); b.comboStreak = 3; }

  const out = timed.timeOut();
  const miss = rejected.submit();
  assert.equal(out.timedOut, true);
  assert.equal(out.valid, false);
  assert.equal(out.playerDamage, miss.playerDamage, 'the monster hits just as hard');
  assert.equal(timed.playerHP, rejected.playerHP);
  assert.equal(timed.comboStreak, 0, 'the combo breaks');
  assert.deepEqual(timed.selected, [], 'the half-built word is lost');
  assert.match(timed.log[0], /^Out of time! Dummy hits you for \d+\./);
});

test('a timeout can end the battle, and does nothing once it is over', () => {
  const b = new BattleSession({ ...monster, attack: 50 }, new Set(), new Set(), 10, 40, 8, {}, () => 0.5);
  const result = b.timeOut();
  assert.equal(result.playerDefeated, true);
  assert.equal(b.over, true);
  assert.equal(b.won, false);
  assert.equal(b.playerHP, 0);
  const again = b.timeOut();
  assert.equal(again.timedOut, true);
  assert.equal(b.playerHP, 0, 'no further damage');
  assert.equal(b.log.length, 1, 'and no further log lines');
});

test('timeouts are repeatable with a seeded run', () => {
  const run = () => new DungeonRun(LEVEL_ONE, null, { seed: 's', hardcore: true });
  const play = (r) => {
    const b = new BattleSession(monster, new Set(), new Set(), 40, 40, 8, {}, r.battleRng(3));
    return [b.timeOut().playerDamage, b.timeOut().playerDamage, b.timeOut().playerDamage].join(',');
  };
  assert.equal(play(run()), play(run()));
});

// ---- permadeath ---------------------------------------------------------------------

test('hardcore: losing a battle ends the run; there is no retreat', () => {
  const run = new DungeonRun(LEVEL_ONE, null, { hardcore: true });
  const m = run.monsterPlacements()[0];
  run.markBattleResolved(m.index, { won: false, remainingPlayerHP: 20, scoreGained: 12 });
  assert.equal(run.fallen, true);
  assert.equal(run.playerHP, 0, 'not the retreat HP');
  assert.equal(run.isDefeated(), true);
  assert.equal(run.retreats, 0, 'a fall is not a retreat');
  assert.equal(run.score, 12, 'the damage dealt still counts');
  assert.ok(!run.isCleared(m.index));
});

test('normal runs still retreat to half HP, exactly as before', () => {
  const run = new DungeonRun(LEVEL_ONE);
  const m = run.monsterPlacements()[0];
  run.markBattleResolved(m.index, { won: false, remainingPlayerHP: 20, scoreGained: 5 });
  assert.equal(run.fallen, false);
  assert.equal(run.hardcore, false);
  assert.equal(run.playerHP, 20);
  assert.equal(run.retreats, 1);
  assert.equal(run.finalScore(), run.score, 'no multiplier');
});

test('hardcore: winning a battle works as usual', () => {
  const run = new DungeonRun(LEVEL_ONE, null, { hardcore: true });
  const m = run.monsterPlacements()[0];
  run.markBattleResolved(m.index, { won: true, remainingPlayerHP: 33, scoreGained: 40 });
  assert.equal(run.fallen, false);
  assert.equal(run.playerHP, 33);
  assert.ok(run.isCleared(m.index));
  assert.equal(run.finalScore(), 60, 'x1.5 on the 40 earned');
});

test('once fallen, the dungeon is closed: no answers, no hints', () => {
  const run = new DungeonRun(LEVEL_ONE, null, { hardcore: true });
  const p = openClue(run);
  run.markBattleResolved(run.monsterPlacements()[0].index, { won: false, remainingPlayerHP: 0, scoreGained: 0 });
  assert.deepEqual(run.attemptSolve(p.index, p.word), { correct: false }, 'even the right answer');
  assert.ok(!run.isSolved(p.index));
  assert.equal(run.canHint(p.index), false);
  assert.equal(run.buyHint(p.index, 1, 'hp').ok, false);
});

// ---- wrong answers ---------------------------------------------------------------------

test('hardcore: one free retry per clue, then wrong answers cost HP', () => {
  const run = new DungeonRun(LEVEL_ONE, null, { hardcore: true });
  const p = openClue(run);
  const hp = run.playerHP;
  assert.equal(run.retriesLeft(p.index), HARDCORE.freeWrongGuesses);

  const first = run.attemptSolve(p.index, 'WRONG');
  assert.deepEqual(first, { correct: false, penalty: 0, freeRetry: true });
  assert.equal(run.playerHP, hp);
  assert.equal(run.retriesLeft(p.index), 0);

  const second = run.attemptSolve(p.index, 'WRONGER');
  assert.equal(second.correct, false);
  assert.equal(second.penalty, HARDCORE.wrongGuessHp);
  assert.equal(run.playerHP, hp - HARDCORE.wrongGuessHp);

  const third = run.attemptSolve(p.index, 'NOPE');
  assert.equal(third.penalty, HARDCORE.wrongGuessHp);
  assert.equal(run.playerHP, hp - 2 * HARDCORE.wrongGuessHp);
});

test('hardcore: retries are counted per clue, and the right answer still works afterwards', () => {
  const run = new DungeonRun(LEVEL_ONE, null, { hardcore: true });
  const open = run.placements.filter((p) => run.canHint(p.index));
  assert.ok(open.length >= 1);
  const [a] = open;
  run.attemptSolve(a.index, 'X');
  run.attemptSolve(a.index, 'Y'); // costs HP
  const hp = run.playerHP;
  assert.equal(run.attemptSolve(a.index, a.word).correct, true);
  assert.ok(run.playerHP >= hp, 'a right answer is never penalised (a treasure room may even heal)');
  // Another clue starts with its own retry (use a fresh run to be independent of the layout).
  const fresh = new DungeonRun(LEVEL_ONE, null, { hardcore: true });
  const b = openClue(fresh);
  assert.equal(fresh.retriesLeft(b.index), HARDCORE.freeWrongGuesses);
});

test('hardcore: a wrong answer can never take your last HP, and a blank answer is never wrong', () => {
  const run = new DungeonRun(LEVEL_ONE, null, { hardcore: true });
  const p = openClue(run);
  run.playerHP = 2;
  run.attemptSolve(p.index, 'A');                 // the free retry
  assert.equal(run.attemptSolve(p.index, 'B').penalty, 1, 'only 1 HP could be taken');
  assert.equal(run.playerHP, 1);
  assert.equal(run.attemptSolve(p.index, 'C').penalty, 0);
  assert.equal(run.playerHP, 1, 'the floor holds');
  assert.equal(run.fallen, false, 'a typo cannot end the run');

  const fresh = new DungeonRun(LEVEL_ONE, null, { hardcore: true });
  const q = openClue(fresh);
  for (const blank of ['', '   ']) {
    assert.deepEqual(fresh.attemptSolve(q.index, blank), { correct: false, penalty: 0 });
  }
  assert.equal(fresh.retriesLeft(q.index), HARDCORE.freeWrongGuesses, 'blank submissions do not use the retry');
});

test('normal runs: wrong answers are always free', () => {
  const run = new DungeonRun(LEVEL_ONE);
  const p = openClue(run);
  const hp = run.playerHP;
  for (let i = 0; i < 6; i += 1) assert.deepEqual(run.attemptSolve(p.index, `NO${i}`), { correct: false, penalty: 0 });
  assert.equal(run.playerHP, hp);
  assert.equal(run.retriesLeft(p.index), 0, 'no retries to count outside hardcore');
});

test('hardcore stacks with a hero and does not touch the hero\'s perks', () => {
  const run = new DungeonRun(LEVEL_ONE, HEROES.warden, { hardcore: true });
  assert.equal(run.playerMaxHP, 50);
  const scribe = new DungeonRun(LEVEL_ONE, HEROES.scribe, { hardcore: true });
  const p = openClue(scribe);
  assert.equal(scribe.buyHint(p.index, 1, 'hp').paid.amount, 0, 'free vowels are still free');
});

// ---- the rules card --------------------------------------------------------------------

const facts = (hardcore) => ({
  maxHp: 40, retreatHp: 20, monsterCount: 10, healAmount: 10, goldAmount: 50, hintLevels: HINT_LEVELS,
  ...(hardcore ? { hardcore } : {}),
});

test('the rules card matches the mode being played', () => {
  const normal = text(renderRulesHtml(facts({ active: false, rules: HARDCORE })));
  assert.match(normal, /A wrong answer costs nothing/);
  assert.match(normal, /you retreat/);
  assert.match(normal, /Hardcore mode\s/, 'the mode is still explained');
  assert.ok(!/Hardcore mode \(on\)/.test(normal));

  const hard = text(renderRulesHtml(facts({ active: true, rules: HARDCORE })));
  assert.match(hard, /Hardcore mode \(on\)/);
  assert.match(hard, /the run is over/);
  assert.ok(!/you retreat:/.test(hard), 'no promise of a retreat');
  assert.ok(!/A wrong answer costs nothing/.test(hard), 'wrong answers are not free');
  assert.match(hard, new RegExp(`you have ${HARDCORE.turnSeconds} seconds`));
  assert.match(hard, new RegExp(`costs ${HARDCORE.wrongGuessHp} HP`));
  assert.match(hard, new RegExp(`\\u00d7${HARDCORE.scoreMultiplier}`));
});

test('rules numbers come from the rules it is given', () => {
  const rules = { turnSeconds: 7, freeWrongGuesses: 2, wrongGuessHp: 5, scoreMultiplier: 3 };
  const body = text(renderRulesHtml(facts({ active: true, rules })));
  assert.match(body, /7 seconds/);
  assert.match(body, /first 2 wrong answers/);
  assert.match(body, /costs 5 HP/);
  assert.match(body, /×3/);
});

test('without hardcore facts the card is unchanged', () => {
  const body = text(renderRulesHtml(facts(null)));
  assert.ok(!/Hardcore/i.test(body));
  assert.match(body, /A wrong answer costs nothing/);
});

// ---- saved results ----------------------------------------------------------------------

test('hardcore results are recorded, saved and validated', () => {
  let stats = loadStats(memoryStorage());
  assert.deepEqual(stats, { wins: 0, falls: 0, best: 0 });
  stats = recordRun(stats, { won: false });
  stats = recordRun(stats, { won: true, score: 300 });
  stats = recordRun(stats, { won: true, score: 250 });
  stats = recordRun(stats, { won: false });
  assert.deepEqual(stats, { wins: 2, falls: 2, best: 300 });

  const storage = memoryStorage();
  assert.equal(saveStats(storage, stats), true);
  assert.deepEqual(loadStats(storage), stats);

  const frozen = { wins: 1, falls: 0, best: 10 };
  recordRun(frozen, { won: true, score: 99 });
  assert.deepEqual(frozen, { wins: 1, falls: 0, best: 10 }, 'the input is not modified');
});

test('damaged hardcore saves are treated as zero', () => {
  const load = (raw) => loadStats(memoryStorage({ [STATS_KEY]: raw }));
  assert.deepEqual(load('not json'), { wins: 0, falls: 0, best: 0 });
  assert.deepEqual(load('[]'), { wins: 0, falls: 0, best: 0 });
  assert.deepEqual(load('7'), { wins: 0, falls: 0, best: 0 });
  assert.deepEqual(load(JSON.stringify({ wins: -3, falls: 'x', best: 1.5 })), { wins: 0, falls: 0, best: 0 });
  assert.deepEqual(load(JSON.stringify({ wins: 4, falls: 2, best: 90, admin: true })), { wins: 4, falls: 2, best: 90 });
  const throwing = { getItem() { throw new Error('blocked'); }, setItem() { throw new Error('blocked'); } };
  assert.deepEqual(loadStats(throwing), { wins: 0, falls: 0, best: 0 });
  assert.equal(saveStats(throwing, { wins: 1, falls: 0, best: 1 }), false);
});
