// Progressive hints for a stuck crossword corridor. Three levels, bought in
// order, each payable with Score or HP so a player who is stuck is never
// blocked outright - but every hint costs something that matters.
//
//   1  Show vowels      every vowel in the word appears in the clue card
//   2  Reveal a letter  one more letter is filled in on the map (repeatable,
//                       but never the whole word)
//   3  Lore hint        an extra, simpler clue written for the word
//
// Costs live here, in one place, so the rules modal and the game cannot drift.

export const HINT_LEVELS = [
  {
    level: 1,
    id: 'vowels',
    name: 'Show vowels',
    blurb: 'Reveals every vowel in the word.',
    cost: { score: 10, hp: 1 },
  },
  {
    level: 2,
    id: 'letter',
    name: 'Reveal a letter',
    blurb: 'Fills in one letter on the map. Use it again for another.',
    cost: { score: 50, hp: 2 },
  },
  {
    level: 3,
    id: 'lore',
    name: 'Lore hint',
    blurb: 'An extra, simpler clue about the word.',
    cost: { score: 25, hp: 2 },
  },
];

const VOWELS = new Set(['A', 'E', 'I', 'O', 'U']);

export function isVowel(ch) {
  return VOWELS.has(String(ch).toUpperCase());
}

/** The player can never spend their last HP on a hint. */
export const MIN_HP_AFTER_HINT = 1;
