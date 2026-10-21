import test from 'node:test';
import assert from 'node:assert/strict';
import { DEFAULT_ICON, battleFraming, strikeEffect, wordPrompt } from '../../src/battlefx.js';
import { LEVEL_ONE } from '../../src/wordlist.js';

test('every fight is framed as a fight, with the monster named', () => {
  const f = battleFraming({ name: 'Snickering Goblin', hp: 18, attack: 4, icon: 'G' });
  assert.equal(f.title, 'BATTLE!');
  assert.match(f.hint, /fighting Snickering Goblin/);
  assert.match(f.hint, /Cast/, 'the hint says how you attack');
  assert.match(f.hint, /strikes back/, 'and what a bad word costs');
  assert.equal(f.icon, 'G');
  assert.equal(f.boss, false);
});

test('a boss fight says so', () => {
  const f = battleFraming({ name: 'Grammar Wyrm', hp: 42, attack: 7, boss: true });
  assert.equal(f.title, 'BOSS BATTLE!');
  assert.equal(f.boss, true);
  assert.match(f.hint, /Grammar Wyrm/);
  assert.match(f.hint, /Cast/);
  assert.match(f.hint, /hits back/, 'a boss fight also says what a bad word costs');
  assert.equal(f.icon, DEFAULT_ICON, 'a monster without a portrait still gets one');
});

test('every monster in the dungeon has a portrait', () => {
  const monsters = LEVEL_ONE.entries.filter((e) => e.monster).map((e) => e.monster);
  assert.ok(monsters.length >= 8);
  for (const m of monsters) assert.ok(m.icon, `${m.name} has an icon`);
});

test('the word prompt names the target and counts letters', () => {
  assert.equal(wordPrompt('', 'Rust Mite'), 'Tap tiles to spell an attack on Rust Mite');
  assert.match(wordPrompt('FEAR', 'Rust Mite'), /^FEAR \(4 letters\)\. Cast it to attack!$/);
  assert.match(wordPrompt('A', 'Rust Mite'), /\(1 letter\)/);
});

test('a landed word floats its damage over the monster', () => {
  assert.deepEqual(strikeEffect({ valid: true, word: 'FEAR', damage: 7 }), { side: 'foe', amount: '-7', label: 'Hit!', kind: 'hit' });
  assert.equal(strikeEffect({ valid: true, word: 'FEAR', damage: 12, combo: true }).kind, 'combo');
  const kill = strikeEffect({ valid: true, word: 'FEAR', damage: 12, combo: true, monsterDefeated: true });
  assert.equal(kill.kind, 'kill', 'the killing blow outranks a combo');
  assert.equal(kill.label, 'Defeated!');
});

test('a wasted turn floats the monster\'s hit over the hero', () => {
  assert.deepEqual(strikeEffect({ valid: false, word: 'QZ', playerDamage: 4 }), { side: 'hero', amount: '-4', label: 'Not a word!', kind: 'miss' });
  const slow = strikeEffect({ valid: false, word: '', playerDamage: 3, timedOut: true });
  assert.equal(slow.label, 'Out of time!');
  assert.equal(slow.kind, 'timeout');
  assert.equal(strikeEffect({ valid: false, word: 'QZ', playerDamage: 5, playerDefeated: true }).kind, 'down');
});

test('nothing floats when nothing happened', () => {
  assert.equal(strikeEffect(null), null);
  assert.equal(strikeEffect({ valid: false, word: '' }), null, 'a cast after the fight is over');
});
