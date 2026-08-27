// Combat: word-building battles. The player draws a rack of letters and
// forms real words to damage the monster; a rejected word costs a turn and
// the monster hits back. Forming one of the dungeon's own theme words is a
// "Vocabulary Combo" for bonus damage.

export const LETTER_VALUES = {
  A: 1, B: 3, C: 3, D: 2, E: 1, F: 4, G: 2, H: 4, I: 1, J: 8, K: 5, L: 1,
  M: 3, N: 1, O: 1, P: 3, Q: 10, R: 1, S: 1, T: 1, U: 1, V: 4, W: 4, X: 8,
  Y: 4, Z: 10,
};

// Scrabble-style bag distribution so rare letters stay rare
const LETTER_BAG_COUNTS = {
  A: 9, B: 2, C: 2, D: 4, E: 12, F: 2, G: 3, H: 2, I: 9, J: 1, K: 1, L: 4,
  M: 2, N: 6, O: 8, P: 2, Q: 1, R: 6, S: 4, T: 6, U: 4, V: 2, W: 2, X: 1,
  Y: 2, Z: 1,
};

const BAG = Object.entries(LETTER_BAG_COUNTS).flatMap(([letter, count]) =>
  Array(count).fill(letter)
);

const VOWELS = new Set(['A', 'E', 'I', 'O', 'U']);

function randomLetter() {
  return BAG[Math.floor(Math.random() * BAG.length)];
}

function randomVowel() {
  return ['A', 'E', 'I', 'O', 'U'][Math.floor(Math.random() * 5)];
}

/** Draw `count` fresh letters, topping up with vowels if `existingVowels`
 * (vowels already elsewhere in the rack) plus these wouldn't reach 2 —
 * keeps every rack state playable, including after mid-battle refills. */
function drawLetters(count, existingVowels = 0) {
  const needed = Math.max(0, Math.min(count, 2 - existingVowels));
  const letters = [];
  for (let i = 0; i < needed; i++) letters.push(randomVowel());
  for (let i = needed; i < count; i++) letters.push(randomLetter());
  return letters;
}

function drawRack(size) {
  return drawLetters(size, 0);
}

let tileSeq = 0;
function makeTile(letter) {
  tileSeq += 1;
  return { id: `t${tileSeq}`, letter };
}

export class BattleSession {
  /**
   * @param {{name:string, hp:number, attack:number, boss?:boolean}} monster
   * @param {Set<string>} dictionary uppercase valid words
   * @param {Set<string>} themeWords uppercase dungeon theme words (combo bonus)
   * @param {number} playerHP
   * @param {number} playerMaxHP
   */
  constructor(monster, dictionary, themeWords, playerHP, playerMaxHP, rackSize = 8) {
    this.monster = { ...monster, maxHp: monster.hp };
    this.dictionary = dictionary;
    this.themeWords = themeWords;
    this.playerHP = playerHP;
    this.playerMaxHP = playerMaxHP;
    this.rackSize = rackSize;
    this.rack = drawRack(rackSize).map(makeTile);
    this.selected = []; // array of tile ids, in pick order
    this.comboStreak = 0;
    this.scoreGained = 0;
    this.log = [];
    this.over = false;
    this.won = false;
  }

  currentWord() {
    return this.selected
      .map((id) => this.rack.find((t) => t.id === id)?.letter ?? '')
      .join('');
  }

  selectTile(id) {
    if (this.over) return;
    if (this.selected.includes(id)) return;
    if (!this.rack.some((t) => t.id === id)) return;
    this.selected.push(id);
  }

  deselectTile(id) {
    this.selected = this.selected.filter((tid) => tid !== id);
  }

  clearSelection() {
    this.selected = [];
  }

  availableTiles() {
    const chosen = new Set(this.selected);
    return this.rack.filter((t) => !chosen.has(t.id));
  }

  /**
   * Submit the currently selected word.
   * @returns {{valid:boolean, word:string, damage?:number, combo?:boolean,
   *   monsterDefeated?:boolean, playerDamage?:number, playerDefeated?:boolean}}
   */
  submit() {
    if (this.over) return { valid: false, word: '' };
    const word = this.currentWord();

    if (word.length < 3 || !this.dictionary.has(word)) {
      this.comboStreak = 0;
      const playerDamage = Math.max(1, this.monster.attack + Math.floor(Math.random() * 3) - 1);
      this.playerHP = Math.max(0, this.playerHP - playerDamage);
      this.clearSelection();
      this.log.unshift(`"${word || '—'}" isn't a word the dungeon recognizes. ${this.monster.name} hits you for ${playerDamage}.`);
      if (this.playerHP <= 0) {
        this.over = true;
        this.won = false;
        return { valid: false, word, playerDamage, playerDefeated: true };
      }
      return { valid: false, word, playerDamage };
    }

    const base = [...word].reduce((sum, l) => sum + (LETTER_VALUES[l] ?? 1), 0);
    const lengthBonus = word.length >= 7 ? 2 : word.length >= 5 ? 1.5 : 1;
    const combo = this.themeWords.has(word);
    const comboMultiplier = Math.min(2, 1 + this.comboStreak * 0.15);
    const damage = Math.round(base * lengthBonus * comboMultiplier * (combo ? 2 : 1));

    this.comboStreak += 1;
    this.monster.hp = Math.max(0, this.monster.hp - damage);
    this.scoreGained += damage;

    this._refillUsedTiles();
    this.clearSelection();

    this.log.unshift(
      combo
        ? `Vocabulary Combo! "${word}" deals ${damage} damage!`
        : `"${word}" deals ${damage} damage.`
    );

    if (this.monster.hp <= 0) {
      this.over = true;
      this.won = true;
      return { valid: true, word, damage, combo, monsterDefeated: true };
    }
    return { valid: true, word, damage, combo };
  }

  _refillUsedTiles() {
    const usedIds = new Set(this.selected);
    const keptVowels = this.rack.filter((t) => !usedIds.has(t.id) && VOWELS.has(t.letter)).length;
    const usedCount = this.rack.filter((t) => usedIds.has(t.id)).length;
    const replacements = drawLetters(usedCount, keptVowels);
    let i = 0;
    this.rack = this.rack.map((t) => (usedIds.has(t.id) ? makeTile(replacements[i++]) : t));
  }
}
