import test from 'node:test';
import assert from 'node:assert/strict';
import {
  HEROES, HERO_LIST, DEFAULT_HERO, heroById, describePerk, maxHpBonus, freeHintLevels, damageBonus,
} from '../../src/heroes.js';
import { DungeonRun, RETREAT_HP_FRACTION } from '../../src/dungeon.js';
import { BattleSession } from '../../src/combat.js';
import { HINT_LEVELS } from '../../src/hints.js';
import { LEVEL_ONE } from '../../src/wordlist.js';

test('the roster: distinct heroes, each with a named perk, Scribe first and default', () => {
  assert.ok(HERO_LIST.length >= 3);
  assert.equal(new Set(HERO_LIST.map((h) => h.id)).size, HERO_LIST.length, 'ids are unique');
  assert.equal(new Set(HERO_LIST.map((h) => h.name)).size, HERO_LIST.length, 'names are unique');
  assert.equal(HERO_LIST[0], DEFAULT_HERO);
  for (const hero of HERO_LIST) {
    assert.equal(HEROES[hero.id], hero, 'the map and the list agree');
    assert.ok(hero.name && hero.tagline && hero.perk.name, `${hero.id} is fully described`);
    assert.ok(describePerk(hero).length > 0, `${hero.id} has a perk the player can read`);
  }
});

test('a stale or hostile saved id falls back to the default hero', () => {
  assert.equal(heroById('warden'), HEROES.warden);
  assert.equal(heroById('nobody'), DEFAULT_HERO);
  assert.equal(heroById(undefined), DEFAULT_HERO);
  assert.equal(heroById('toString'), DEFAULT_HERO, 'inherited object keys are not heroes');
  assert.equal(heroById('__proto__'), DEFAULT_HERO);
});

test('perk text is generated from the numbers that drive the game', () => {
  assert.equal(describePerk(HEROES.warden), `+${HEROES.warden.perk.effects.maxHpBonus} max HP.`);
  assert.equal(describePerk(HEROES.duelist), `+${Math.round(HEROES.duelist.perk.effects.damageBonus * 100)}% damage on every word.`);
  assert.match(describePerk(HEROES.scribe), /Show vowels hints are free on every clue/);

  const custom = { perk: { name: 'x', effects: { maxHpBonus: 7, damageBonus: 0.35, freeHintLevels: [1, 3] } } };
  assert.equal(describePerk(custom), '+7 max HP. Show vowels and Lore hint hints are free on every clue. +35% damage on every word.');
  assert.equal(describePerk(null), '');
  assert.equal(maxHpBonus(null) + damageBonus(undefined) + freeHintLevels({}).length, 0, 'no hero, no perks');
});

test('no hero means the plain baseline run', () => {
  const run = new DungeonRun(LEVEL_ONE);
  assert.equal(run.playerMaxHP, 40);
  assert.equal(run.playerHP, 40);
  assert.ok(run.hintOptions(openClue(run)).every((o) => !o.free));
});

test('Warden: more max HP, starting full, and the retreat fraction scales with it', () => {
  const run = new DungeonRun(LEVEL_ONE, HEROES.warden);
  const bonus = HEROES.warden.perk.effects.maxHpBonus;
  assert.equal(run.playerMaxHP, 40 + bonus);
  assert.equal(run.playerHP, 40 + bonus, 'starts at full health');
  const retreat = Math.round(run.playerMaxHP * RETREAT_HP_FRACTION);
  assert.ok(retreat > 20, 'a bigger pool means a bigger retreat');
});

function openClue(run) {
  const open = run.placements.find((p) => run.canHint(p.index));
  assert.ok(open, 'a clue is open at the start');
  return open.index;
}

test('Scribe: Show vowels is free, with no Score and on the last HP, but nothing else is', () => {
  const run = new DungeonRun(LEVEL_ONE, HEROES.scribe);
  const index = openClue(run);
  run.score = 0;
  run.playerHP = 1; // paying even 1 HP would be refused

  const [vowels, letter, lore] = run.hintOptions(index);
  assert.equal(vowels.free, true);
  assert.deepEqual(vowels.cost, { score: 0, hp: 0 });
  assert.ok(vowels.canPayScore && vowels.canPayHP, 'free means affordable broke');
  assert.deepEqual(letter.cost, HINT_LEVELS[1].cost, 'level 2 still costs');
  assert.deepEqual(lore.cost, HINT_LEVELS[2].cost, 'level 3 still costs');
  assert.equal(letter.free || lore.free, false);

  const bought = run.buyHint(index, 1, 'score');
  assert.equal(bought.ok, true);
  assert.deepEqual(bought.paid, { currency: 'score', amount: 0 });
  assert.equal(run.score, 0);
  assert.equal(run.playerHP, 1, 'nothing was charged');
  assert.equal(run.hintsUsed, 1, 'it still counts as a hint used');
  const word = run.placement(index).word;
  const pattern = run.hintPattern(index);
  assert.ok([...word].every((ch, i) => !'AEIOU'.includes(ch) || pattern[i] === ch), 'every vowel is now known');
  assert.ok(pattern.some((ch) => ch === null), 'but the word is not given away');

  // The perk does not make later levels cheaper or unlock them without payment.
  assert.deepEqual(run.buyHint(index, 2, 'hp'), { ok: false, reason: 'cannot_afford' });
  assert.equal(run.buyHint(index, 3, 'score').reason, 'locked');
});

test('Scribe: free vowels apply to every clue, not just the first', () => {
  // Work outwards through the dungeon, so this never depends on how many
  // corridors happen to be open at the start of a randomly generated grid.
  const run = new DungeonRun(LEVEL_ONE, HEROES.scribe);
  let bought = 0;
  for (let round = 0; round < 6; round += 1) {
    const open = run.placements.find((p) => run.canHint(p.index));
    if (!open) break;
    // Solving corridors pays out treasure, so compare around the purchase only.
    const before = { hp: run.playerHP, score: run.score };
    assert.equal(run.buyHint(open.index, 1, 'hp').paid.amount, 0, `clue ${open.number} ${open.dir}`);
    assert.deepEqual({ hp: run.playerHP, score: run.score }, before, 'nothing was charged');
    bought += 1;
    run.attemptSolve(open.index, open.word); // opens the corridors beside it
  }
  assert.ok(bought >= 3, `checked ${bought} different clues`);
});

test('Duelist: every valid word hits harder by exactly the perk, and wasted turns are unchanged', () => {
  const words = new Set(['CAT', 'QUEST', 'LEXICON']);
  const monster = { name: 'Dummy', hp: 500, attack: 3 };
  const cast = (perks, word) => {
    const battle = new BattleSession(monster, words, new Set(), 40, 40, 8, perks);
    battle.rack = [...word].map((letter, i) => ({ id: `t${i}`, letter }));
    for (const tile of battle.rack) battle.selectTile(tile.id);
    return battle.submit();
  };

  const bonus = HEROES.duelist.perk.effects.damageBonus;
  for (const word of ['CAT', 'QUEST', 'LEXICON']) {
    const plain = cast({}, word).damage;
    const sharp = cast({ damageBonus: bonus }, word).damage;
    assert.ok(plain > 0);
    assert.ok(sharp > plain, `${word}: ${sharp} > ${plain}`);
    assert.ok(Math.abs(sharp - plain * (1 + bonus)) <= 1, `${word} is within rounding of +${bonus * 100}%`);
  }
  assert.equal(cast(undefined, 'CAT').damage, cast({}, 'CAT').damage, 'no perks argument is the baseline');

  const wasted = new BattleSession(monster, words, new Set(), 40, 40, 8, { damageBonus: bonus });
  wasted.rack = [{ id: 'z', letter: 'Z' }];
  wasted.selectTile('z');
  const miss = wasted.submit();
  assert.equal(miss.valid, false);
  assert.ok(miss.playerDamage >= 1 && miss.playerDamage <= monster.attack + 1, 'monster damage ignores the perk');
});

test('perks stack with nothing else: each hero changes only its own axis', () => {
  const baseline = new DungeonRun(LEVEL_ONE);
  for (const hero of HERO_LIST) {
    const run = new DungeonRun(LEVEL_ONE, hero);
    const fx = hero.perk.effects;
    assert.equal(run.playerMaxHP, baseline.playerMaxHP + (fx.maxHpBonus ?? 0), `${hero.id} max HP`);
    const free = run.hintOptions(openClue(run)).filter((o) => o.free).map((o) => o.level);
    assert.deepEqual(free, fx.freeHintLevels ?? [], `${hero.id} free hints`);
  }
});
