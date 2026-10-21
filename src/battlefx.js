// What the battle screen says and shows, kept out of the DOM code so it can be
// tested. A fight is built from word-puzzle parts (a tile rack, a Cast button),
// so on its own it reads as another puzzle. These helpers supply the framing
// that tells the player they are in a FIGHT and that spelling words is how they
// attack: the banner, the hint under it, the portrait, and the floating
// "-7" / "Not a word!" that follows every cast.

export const DEFAULT_ICON = '👹'; // a fallback ogre mask for a monster with no portrait

/** The banner, hint and portrait for a fresh fight against [monster]. */
export function battleFraming(monster) {
  const name = monster.name;
  return {
    title: monster.boss ? 'BOSS BATTLE!' : 'BATTLE!',
    hint: monster.boss
      ? `${name} guards the way. Spell strong words and Cast them to wear it down. A bad word and it hits back hard.`
      : `You are fighting ${name}. Spell words from your tiles and Cast them to attack. Not a word? It strikes back.`,
    icon: monster.icon || DEFAULT_ICON,
    boss: Boolean(monster.boss),
    splashName: name,
  };
}

/** The prompt above the tiles, before and while a word is being built. */
export function wordPrompt(word, monsterName) {
  if (!word) return `Tap tiles to spell an attack on ${monsterName}`;
  return `${word} (${word.length} ${word.length === 1 ? 'letter' : 'letters'}). Cast it to attack!`;
}

/**
 * The floating text that follows a cast or a timeout, from what
 * BattleSession.submit() / timeOut() returned. null when nothing happened.
 *   side   which fighter it floats over ('foe' = your attack landed, 'hero' = you were hit)
 *   amount the number, e.g. "-7"
 *   label  a short word above it
 *   kind   'hit' | 'combo' | 'kill' | 'miss' | 'timeout' | 'down' (the style)
 */
export function strikeEffect(result) {
  if (!result) return null;
  if (result.valid) {
    return {
      side: 'foe',
      amount: `-${result.damage}`,
      label: result.monsterDefeated ? 'Defeated!' : result.combo ? 'Combo!' : 'Hit!',
      kind: result.monsterDefeated ? 'kill' : result.combo ? 'combo' : 'hit',
    };
  }
  if (typeof result.playerDamage !== 'number') return null;
  return {
    side: 'hero',
    amount: `-${result.playerDamage}`,
    label: result.timedOut ? 'Out of time!' : 'Not a word!',
    kind: result.playerDefeated ? 'down' : result.timedOut ? 'timeout' : 'miss',
  };
}
