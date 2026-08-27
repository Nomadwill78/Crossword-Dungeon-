// Level content for "The Lexicon Crypt" — the crossword grid IS the dungeon
// map. Each entry becomes one corridor; solving its clue unlocks the
// corridor and, if it has a `monster`, drops you into battle at its far end.
// Entries with no `monster` are treasure rooms: solving them grants an
// immediate reward instead of a fight.

export const LEVEL_ONE = {
  id: 'lexicon-crypt',
  name: 'The Lexicon Crypt',
  entries: [
    {
      word: 'QUEST',
      clue: 'The journey you are currently on',
      isEntrance: true,
    },
    {
      word: 'GOBLIN',
      clue: 'Green dungeon pest that snickers at bad spelling',
      monster: { name: 'Snickering Goblin', hp: 18, attack: 4 },
    },
    {
      word: 'DRAGON',
      clue: 'Fire-breathing hoarder of gold and grammar alike',
      monster: { name: 'Grammar Wyrm', hp: 42, attack: 7, boss: true },
    },
    {
      word: 'RIDDLE',
      clue: 'A puzzling question guarding the vault door',
      monster: { name: 'Riddle Sphinx', hp: 24, attack: 5 },
    },
    {
      word: 'WIZARD',
      clue: 'Casts spells one syllable at a time',
      monster: { name: 'Syllable Mage', hp: 22, attack: 5 },
    },
    {
      word: 'SHIELD',
      clue: 'Blocks arrows, insults, and bad puns',
      monster: { name: 'Pun Wraith', hp: 20, attack: 4 },
    },
    {
      word: 'SCROLL',
      clue: 'Rolled parchment packed with spells',
      monster: { name: 'Ink Specter', hp: 20, attack: 4 },
    },
    {
      word: 'VAULT',
      clue: 'Where treasure and rare words are locked away',
      monster: { name: 'Vault Golem', hp: 34, attack: 6, boss: true },
    },
    {
      word: 'ARMOR',
      clue: 'Protective gear worn into battle',
      monster: { name: 'Rust Mite', hp: 14, attack: 3 },
    },
    {
      word: 'SWORD',
      clue: 'A sharp synonym for blade',
      monster: { name: 'Blade Wisp', hp: 16, attack: 4 },
    },
    {
      word: 'TRAP',
      clue: 'Hidden danger triggered by one wrong step',
      monster: { name: 'Trap Imp', hp: 12, attack: 3 },
    },
    {
      word: 'RUNE',
      clue: 'An ancient magical letter-symbol',
      reward: { type: 'letters', amount: 2 },
    },
    {
      word: 'GOLD',
      clue: 'Shiny reward for winning battles',
      reward: { type: 'score', amount: 50 },
    },
    {
      word: 'POTION',
      clue: 'Bubbling brew that restores HP',
      reward: { type: 'heal', amount: 10 },
    },
  ],
};
