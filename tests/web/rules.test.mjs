import test from 'node:test';
import assert from 'node:assert/strict';
import { renderRulesHtml, rulesSections } from '../../src/rules.js';
import { HINT_LEVELS } from '../../src/hints.js';
import { DungeonRun, RETREAT_HP_FRACTION } from '../../src/dungeon.js';
import { LEVEL_ONE } from '../../src/wordlist.js';

const facts = (overrides = {}) => ({
  maxHp: 40, retreatHp: 20, monsterCount: 10, healAmount: 10, goldAmount: 50, hintLevels: HINT_LEVELS, ...overrides,
});
const text = (html) => html.replace(/<[^>]+>/g, ' ');

test('the rules explain how HP is lost, how score works, and how to win', () => {
  const sections = rulesSections(facts()).map((s) => s.title);
  for (const needed of ['Goal', 'Your HP', 'Score', 'Winning', 'Hints']) {
    assert.ok(sections.includes(needed), `has a "${needed}" section`);
  }
});

test('every number comes from the facts it is given', () => {
  const body = text(renderRulesHtml(facts({ maxHp: 77, retreatHp: 33, monsterCount: 12, healAmount: 9, goldAmount: 31 })));
  assert.match(body, /all 12 monsters/);
  assert.match(body, /You have 77 HP/);
  assert.match(body, /return with 33 HP/);
  assert.match(body, /\+31 Score/);
  assert.match(body, /heals 9 HP/);
  for (const hint of HINT_LEVELS) {
    assert.ok(body.includes(`Costs ${hint.cost.score} Score or ${hint.cost.hp} HP`), `${hint.name}'s costs are listed`);
  }
});

test('treasure is only mentioned when the level has it', () => {
  const body = text(renderRulesHtml(facts({ healAmount: null, goldAmount: null })));
  assert.doesNotMatch(body, /treasure rooms \(/);
  assert.doesNotMatch(body, /heals/);
});

test('it matches the real game', () => {
  const run = new DungeonRun(LEVEL_ONE);
  const retreat = Math.round(run.playerMaxHP * RETREAT_HP_FRACTION);
  const monsters = run.monsterPlacements().length;
  const body = text(renderRulesHtml(facts({ maxHp: run.playerMaxHP, retreatHp: retreat, monsterCount: monsters })));
  assert.match(body, new RegExp(`all ${monsters} monsters`));
  assert.match(body, new RegExp(`You have ${run.playerMaxHP} HP`));
  assert.ok(monsters > 0 && retreat > 0 && retreat < run.playerMaxHP);
});

test('text is escaped', () => {
  const html = renderRulesHtml(facts({ hintLevels: [{ name: '<b>x</b>', blurb: 'a & b', cost: { score: 1, hp: 1 } }] }));
  assert.ok(!html.includes('<b>x</b>'));
  assert.ok(html.includes('&lt;b&gt;x&lt;/b&gt;'));
  assert.ok(html.includes('a &amp; b'));
});
