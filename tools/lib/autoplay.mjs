// Plays the browser build to victory for the end-to-end checks: solves every
// corridor (the answers are in the word list) and wins each battle by casting
// the best dictionary word the rack allows.
import fs from 'node:fs';
import { LETTER_VALUES } from '../../src/combat.js';
import { LEVEL_ONE } from '../../src/wordlist.js';
import { ROOT } from './static_server.mjs';

const WORDS = JSON.parse(fs.readFileSync(`${ROOT}/data/dictionary.json`, 'utf8'))
  .map((w) => w.toUpperCase())
  .filter((w) => w.length >= 3 && w.length <= 8);

export const ANSWERS = new Map(LEVEL_ONE.entries.map((e) => [e.clue, e.word]));

function damage(word) {
  const base = [...word].reduce((sum, ch) => sum + (LETTER_VALUES[ch] ?? 1), 0);
  return base * (word.length >= 7 ? 2 : word.length >= 5 ? 1.5 : 1);
}

/** The strongest dictionary word that can be spelled from [letters], or null. */
export function bestWord(letters) {
  const pool = {};
  for (const ch of letters) pool[ch] = (pool[ch] ?? 0) + 1;
  let best = null;
  for (const word of WORDS) {
    const need = {};
    let ok = true;
    for (const ch of word) {
      need[ch] = (need[ch] ?? 0) + 1;
      if (need[ch] > (pool[ch] ?? 0)) { ok = false; break; }
    }
    if (ok && (!best || damage(word) > damage(best))) best = word;
  }
  return best;
}

const victoryShowing = (page) => page.evaluate(() => {
  const overlay = document.getElementById('overlay');
  return !overlay.hidden && /Cleared/.test(document.getElementById('overlay-title').textContent);
});

/** Casts one word (or a wasted single tile if nothing can be spelled). */
async function castOnce(page) {
  const letters = await page.$$eval('.rack-tile', (tiles) => tiles.map((t) => t.firstElementChild.textContent));
  const word = bestWord(letters);
  await page.evaluate((w) => {
    for (const ch of w ?? '') {
      [...document.querySelectorAll('.rack-tile')].find((t) => t.firstElementChild.textContent === ch)?.click();
    }
    if (!w) document.querySelector('.rack-tile')?.click();
    document.getElementById('submit-word').click();
  }, word);
}

/**
 * Plays until the "Cleared!" overlay is on screen (it is left open for the
 * caller to dismiss). Returns the number of battle casts it took.
 */
export async function playToVictory(page, { maxSteps = 600 } = {}) {
  let casts = 0;
  for (let step = 0; step < maxSteps; step += 1) {
    if (await victoryShowing(page)) return casts;

    const state = await page.evaluate(() => ({
      overlay: !document.getElementById('overlay').hidden,
      battle: !document.getElementById('battle-view').hidden,
    }));
    let cast = false;
    if (state.overlay) {                       // a battle result: dismiss it
      await page.evaluate(() => document.getElementById('overlay').click());
    } else if (state.battle) {
      await castOnce(page);
      casts += 1;
      cast = true;
    } else {
      // Map view: fight a monster waiting from an earlier retreat, else solve a clue.
      const acted = await page.evaluate((answers) => {
        const fight = document.querySelector('.clue-item.pending-battle button.danger');
        if (fight) { fight.click(); return true; }
        const card = document.querySelector('.clue-item.open');
        if (!card) return false;
        const answer = answers[card.querySelector('.clue-text').textContent];
        const input = card.querySelector('input[type="text"]');
        input.value = answer;
        card.querySelector('form').requestSubmit();
        return true;
      }, Object.fromEntries(ANSWERS));
      if (!acted) throw new Error('autoplay is stuck: nothing to solve, fight or dismiss');
    }
    // The battle view stays up behind its result overlay, so only wait for the
    // overlay (it appears 300ms after the last blow) if this step cast a word.
    if (cast && await page.evaluate(() => /^0\//.test(document.getElementById('player-hp-text').textContent) || document.getElementById('monster-hp-text').textContent.startsWith('0/'))) {
      await page.waitForSelector('#overlay:not([hidden])', { timeout: 3000 });
    }
  }
  throw new Error(`autoplay did not finish in ${maxSteps} steps`);
}
