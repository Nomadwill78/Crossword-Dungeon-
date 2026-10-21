// The "How to play" text. Every number in it is passed in from the game's own
// data (max HP, hint costs, heal amounts, monster count) so the modal cannot
// quietly disagree with the rules it describes.

function escapeHtml(text) {
  return String(text).replace(/[&<>"']/g, (ch) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]
  ));
}

/**
 * @param {{maxHp:number, retreatHp:number, monsterCount:number,
 *   healAmount:number|null, goldAmount:number|null, hintLevels:Array,
 *   hero?:{name:string, perkName:string, perkText:string},
 *   hardcore?:{active:boolean, rules:{turnSeconds:number, freeWrongGuesses:number,
 *   wrongGuessHp:number, scoreMultiplier:number}}}} facts
 * @returns {Array<{title:string, paragraphs?:string[], items?:string[]}>}
 */
export function rulesSections(facts) {
  const { maxHp, retreatHp, monsterCount, healAmount, goldAmount, hintLevels, hero, hardcore } = facts;
  const hc = hardcore?.active ? hardcore.rules : null;
  const retries = hc?.freeWrongGuesses;
  const treasure = [
    goldAmount ? `gold is worth +${goldAmount} Score` : null,
    healAmount ? `a potion heals ${healAmount} HP` : null,
  ].filter(Boolean);

  return [
    {
      title: 'Goal',
      paragraphs: [
        `Clear the dungeon by defeating all ${monsterCount} monsters. The crossword grid is the map, and every word on it is a corridor.`,
      ],
    },
    {
      title: 'Opening corridors',
      paragraphs: [
        `Read a clue, type the answer, and press Solve to open that corridor. You can only try a corridor that touches one you have already opened. ${
          hc
            ? `Hardcore: ${retries === 1 ? 'your first wrong answer' : `your first ${retries} wrong answers`} on each clue ${retries === 1 ? 'is' : 'are'} free; after that each wrong answer costs ${hc.wrongGuessHp} HP (never your last HP).`
            : 'A wrong answer costs nothing, so guess freely.'
        }`,
      ],
    },
    {
      title: 'Battles',
      paragraphs: [
        `Opening a monster corridor starts a battle: the crossword steps aside and you fight the monster with words. Tap letter tiles to spell a word of 3 or more letters, then Cast Word to attack with it. Real words hurt the monster; longer words, rare letters and unbroken streaks hurt more, and the dungeon's own theme words deal double. Defeat the monster to clear the corridor.${
          hc ? ` Hardcore: you have ${hc.turnSeconds} seconds for each word. If the clock runs out the turn is wasted and the monster hits you.` : ''
        }`,
      ],
    },
    {
      title: 'Your HP',
      paragraphs: [
        `You have ${maxHp} HP. You lose HP when you cast something that is not a word (the monster hits back, and bosses hit hardest) and when you pay for a hint with HP.`,
        hc
          ? 'If your HP reaches 0 the run is over. There is no retreat in hardcore.'
          : `If your HP reaches 0 you retreat: the battle is lost, the monster stays, and you return with ${retreatHp} HP to try again.`,
      ],
    },
    {
      title: 'Score',
      paragraphs: [
        `Your score is the damage you deal in battles${treasure.length ? `, plus treasure rooms (${treasure.join(', ')})` : ''}. Paying for hints with Score takes it back out.${hc ? ` Hardcore multiplies your final Score by \u00d7${hc.scoreMultiplier}.` : ''}`,
      ],
    },
    {
      title: 'Winning',
      paragraphs: [`You win when every monster corridor is cleared. Treasure rooms are optional.`],
    },
    {
      title: 'Hints',
      paragraphs: ['Stuck? Open Hints on any clue you can answer. The levels unlock in order, and you pay with Score or HP, your choice (you can never spend your last HP):'],
      items: hintLevels.map((h) => `${h.name}: ${h.blurb} Costs ${h.cost.score} Score or ${h.cost.hp} HP.`),
    },
    ...(hardcore
      ? [{
        title: hc ? 'Hardcore mode (on)' : 'Hardcore mode',
        paragraphs: [
          'A harsher way to play free runs, chosen when you start a new run. The Daily Challenge is always played on normal rules.',
        ],
        items: [
          'No retreat: if your HP reaches 0 the run is over.',
          `${hardcore.rules.turnSeconds} seconds for each word in battle. When the clock runs out the turn is wasted and the monster hits you. It pauses while this card is open or the tab is hidden.`,
          `${hardcore.rules.freeWrongGuesses === 1 ? 'One free retry' : `${hardcore.rules.freeWrongGuesses} free retries`} per clue. After that each wrong answer costs ${hardcore.rules.wrongGuessHp} HP, but never your last HP.`,
          `Your final Score is multiplied by \u00d7${hardcore.rules.scoreMultiplier}.`,
        ],
      }]
      : []),
    ...(hero
      ? [{
        title: 'Your hero',
        paragraphs: [`${hero.name}: ${hero.perkName}. ${hero.perkText} Tap your portrait to start a new run with a different hero.`],
      }]
      : []),
    {
      title: 'Daily challenge',
      paragraphs: [
        'Once a day (the day changes at midnight UTC) there is a Daily Challenge: everyone plays the same dungeon, as the same hero, with the same starting letters in each battle. Open it from the Daily button.',
        'Your first finished run of the day is recorded, with your Score, retreats and hints used, and it extends your streak. Replays are practice and do not count. You can copy your result to share it.',
      ],
    },
    {
      title: 'Tips',
      items: [
        'Tap a clue to light up its word on the grid. Tap a letter on the grid to find its clue.',
        'Open the corridors next to treasure first: a potion before a boss is worth a lot.',
      ],
    },
  ];
}

/** The sections as HTML. */
export function renderRulesHtml(facts) {
  return rulesSections(facts)
    .map((section) => {
      const paragraphs = (section.paragraphs ?? []).map((p) => `<p>${escapeHtml(p)}</p>`).join('');
      const items = section.items
        ? `<ul>${section.items.map((i) => `<li>${escapeHtml(i)}</li>`).join('')}</ul>`
        : '';
      return `<section><h3>${escapeHtml(section.title)}</h3>${paragraphs}${items}</section>`;
    })
    .join('');
}
