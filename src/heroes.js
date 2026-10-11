// Selectable heroes. Each has one small passive perk, described as plain
// numbers in `effects` so the same data drives three things that must agree:
// what the game does (dungeon.js, combat.js), what the picker promises, and
// what the How-to-play card says. Perk text is generated from `effects`
// (describePerk), never written by hand.
//
//   effects.maxHpBonus       extra max HP (and starting HP)
//   effects.freeHintLevels   hint levels that cost nothing on every clue
//   effects.damageBonus      fraction added to the damage of every valid word

import { HINT_LEVELS } from './hints.js';

export const HEROES = {
  scribe: {
    id: 'scribe',
    name: 'The Scribe',
    tagline: 'Quick with a clue.',
    perk: { name: 'Study Notes', effects: { freeHintLevels: [1] } },
  },
  warden: {
    id: 'warden',
    name: 'The Warden',
    tagline: 'Built to take a hit.',
    perk: { name: 'Thick Skin', effects: { maxHpBonus: 10 } },
  },
  duelist: {
    id: 'duelist',
    name: 'The Duelist',
    tagline: 'Every word cuts.',
    perk: { name: 'Sharp Quill', effects: { damageBonus: 0.2 } },
  },
};

/** The roster in the order the picker shows it. */
export const HERO_LIST = [HEROES.scribe, HEROES.warden, HEROES.duelist];

export const DEFAULT_HERO = HEROES.scribe;

/** The hero with this id, or the default (e.g. a stale saved choice). */
export function heroById(id) {
  return Object.hasOwn(HEROES, id) ? HEROES[id] : DEFAULT_HERO;
}

function effectsOf(hero) {
  return hero?.perk?.effects ?? {};
}

export function maxHpBonus(hero) {
  return effectsOf(hero).maxHpBonus ?? 0;
}

export function freeHintLevels(hero) {
  return effectsOf(hero).freeHintLevels ?? [];
}

export function damageBonus(hero) {
  return effectsOf(hero).damageBonus ?? 0;
}

/** One sentence per effect, built from the numbers in `effects`. */
export function describePerk(hero) {
  const parts = [];
  const hp = maxHpBonus(hero);
  if (hp) parts.push(`+${hp} max HP.`);

  const free = freeHintLevels(hero);
  if (free.length) {
    const names = free.map((level) => HINT_LEVELS.find((h) => h.level === level)?.name ?? `level ${level}`);
    parts.push(`${names.join(' and ')} hints are free on every clue.`);
  }

  const dmg = damageBonus(hero);
  if (dmg) parts.push(`+${Math.round(dmg * 100)}% damage on every word.`);

  return parts.join(' ');
}
