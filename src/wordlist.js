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
      lore: "Heroes in stories always seem to be on one.",
      isEntrance: true,
    },
    {
      word: 'GOBLIN',
      clue: 'Green dungeon pest that snickers at bad spelling',
      lore: "Small, green, and fond of sneering at your homework.",
      monster: { name: 'Snickering Goblin', hp: 18, attack: 4, icon: '👺' },
    },
    {
      word: 'DRAGON',
      clue: 'Fire-breathing hoarder of gold and grammar alike',
      lore: "Sleeps on a mountain of coins and breathes flame.",
      monster: { name: 'Grammar Wyrm', hp: 42, attack: 7, boss: true, icon: '🐉' },
    },
    {
      word: 'RIDDLE',
      clue: 'A puzzling question guarding the vault door',
      lore: "The Sphinx loves to ask one of these.",
      monster: { name: 'Riddle Sphinx', hp: 24, attack: 5, icon: '🦁' },
    },
    {
      word: 'WIZARD',
      clue: 'Casts spells one syllable at a time',
      lore: "Pointy hat, long beard, and a staff full of spells.",
      monster: { name: 'Syllable Mage', hp: 22, attack: 5, icon: '🧙' },
    },
    {
      word: 'SHIELD',
      clue: 'Blocks arrows, insults, and bad puns',
      lore: "Raise it on your arm to turn a blow aside.",
      monster: { name: 'Pun Wraith', hp: 20, attack: 4, icon: '👻' },
    },
    {
      word: 'SCROLL',
      clue: 'Rolled parchment packed with spells',
      lore: "Unroll it to read the spell written inside.",
      monster: { name: 'Ink Specter', hp: 20, attack: 4, icon: '✒️' },
    },
    {
      word: 'VAULT',
      clue: 'Where treasure and rare words are locked away',
      lore: "A strongroom with a heavy door, for gold and secrets.",
      monster: { name: 'Vault Golem', hp: 34, attack: 6, boss: true, icon: '🗿' },
    },
    {
      word: 'ARMOR',
      clue: 'Protective gear worn into battle',
      lore: "Knights clank around in a suit of it.",
      monster: { name: 'Rust Mite', hp: 14, attack: 3, icon: '🐜' },
    },
    {
      word: 'SWORD',
      clue: 'A sharp synonym for blade',
      lore: "The hero draws it from a scabbard.",
      monster: { name: 'Blade Wisp', hp: 16, attack: 4, icon: '🔥' },
    },
    {
      word: 'TRAP',
      clue: 'Hidden danger triggered by one wrong step',
      lore: "Pressure plates and tripwires are the classic kinds.",
      monster: { name: 'Trap Imp', hp: 12, attack: 3, icon: '😈' },
    },
    {
      word: 'RUNE',
      clue: 'An ancient magical letter-symbol',
      lore: "Carved into stone and glowing with old magic.",
      reward: { type: 'letters', amount: 2 },
    },
    {
      word: 'GOLD',
      clue: 'Shiny reward for winning battles',
      lore: "What dragons hoard and heroes collect.",
      reward: { type: 'score', amount: 50 },
    },
    {
      word: 'POTION',
      clue: 'Bubbling brew that restores HP',
      lore: "Drink it from a small glass vial to feel better fast.",
      reward: { type: 'heal', amount: 10 },
    },
  ],
};
