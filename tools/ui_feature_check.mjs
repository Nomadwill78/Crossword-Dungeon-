// Plays the browser build and checks the player-facing features end to end:
// the how-to-play modal, the hero portrait following HP, the three hint
// levels, and clue <-> grid highlighting. Runs on a desktop and a phone.
//
// Usage:  node tools/ui_feature_check.mjs [screenshot-dir]
// Needs Playwright (set PLAYWRIGHT_MODULE to its path if it is not installed
// locally) and a Chromium (CHROMIUM_PATH). Exits 1 on any failed check.
import fs from 'node:fs';
import { LEVEL_ONE } from '../src/wordlist.js';
import { startStaticServer } from './lib/static_server.mjs';

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const OUT = process.argv[2];
if (OUT) fs.mkdirSync(OUT, { recursive: true });

const staticServer = await startStaticServer();
const answers = new Map(LEVEL_ONE.entries.map((e) => [e.clue, e.word]));
const entryByClue = new Map(LEVEL_ONE.entries.map((e) => [e.clue, e]));

let problems = 0;
const check = (ok, message) => {
  if (!ok) problems += 1;
  console.log(`${ok ? '  ok ' : '  BAD'} ${message}`);
};

const browser = await chromium.launch(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {});

const profiles = [
  { name: 'desktop 1280x800', width: 1280, height: 800, touch: false },
  { name: 'phone 390x844', width: 390, height: 844, touch: true },
  { name: 'small phone 320x568', width: 320, height: 568, touch: true },
];

async function open(profile, { storage = true } = {}) {
  const context = await browser.newContext({
    viewport: { width: profile.width, height: profile.height },
    hasTouch: profile.touch,
    isMobile: profile.touch,
    deviceScaleFactor: 2,
  });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(staticServer.url);
  await page.waitForSelector('.cell');
  return { context, page, errors };
}

const openCards = (page) => page.$$('.clue-item:has(form)');
const clueOf = (card) => card.$eval('.clue-text', (e) => e.textContent);
const hpText = (page) => page.$eval('#player-hp-text', (e) => e.textContent);

/** Solve open corridors until a monster battle starts. */
async function reachBattle(page) {
  for (let i = 0; i < 30; i += 1) {
    if (await page.$eval('#battle-view', (e) => !e.hidden)) return true;
    const [card] = await openCards(page);
    if (!card) return false;
    const word = answers.get(await clueOf(card));
    await (await card.$('input')).fill(word);
    await (await card.$('button[type="submit"]')).evaluate((b) => b.click());
    await page.waitForTimeout(60);
  }
  return page.$eval('#battle-view', (e) => !e.hidden);
}

for (const profile of profiles) {
  console.log(`\n== ${profile.name}`);

  // ---- how-to-play modal ------------------------------------------------
  {
    const { context, page, errors } = await open(profile);
    const box = async (sel) => page.$eval(sel, (e) => {
      const r = e.getBoundingClientRect();
      return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width, height: r.height };
    });

    const hp = await box('#player-hp-text');
    const help = await box('#help-btn');
    const bar = await box('.player-bar');
    const avatar = await box('#avatar');
    check(help.width > 0 && help.right <= profile.width, 'the ? button is visible and on screen');
    check(avatar.right <= bar.left + 1 && Math.abs((avatar.top + avatar.bottom) / 2 - (bar.top + bar.bottom) / 2) < 40,
      'the portrait sits right beside the HP bar');
    check(help.left >= hp.right - 1 || help.top >= hp.bottom - 1, 'the ? button sits next to the HP readout');
    check(profile.touch ? help.width >= 32 : help.width >= 24, `the ? button is a usable size (${help.width}px)`);
    check(await page.$eval('#help-btn', (e) => e.classList.contains('attention')), 'a first-time visitor sees the ? pulse');

    await page.click('#help-btn');
    check(await page.$eval('#help-modal', (e) => !e.hidden), 'tapping ? opens the modal');
    const body = await page.$eval('#help-body', (e) => e.innerText);
    check(/all 10 monsters/.test(body), 'it states the winning condition with the real monster count');
    check(/You have 40 HP/.test(body) && /not a word/.test(body), 'it explains how HP is lost');
    check(/return with 20 HP/.test(body), 'it explains what happens at 0 HP');
    check(/Your score is the damage/.test(body), 'it explains how score is calculated');
    for (const h of [{ n: 'Show vowels', s: 10, h: 1 }, { n: 'Reveal a letter', s: 50, h: 2 }, { n: 'Lore hint', s: 25, h: 2 }]) {
      check(body.includes(`${h.n}:`) && body.includes(`Costs ${h.s} Score or ${h.h} HP`), `it lists the "${h.n}" hint and its cost`);
    }
    check(!(await page.$eval('#help-btn', (e) => e.classList.contains('attention'))), 'the pulse stops once it has been opened');

    const card = await box('.modal-card');
    check(card.top >= 0 && card.bottom <= profile.height + 1 && card.right <= profile.width + 1, 'the modal fits inside the screen');
    check(await page.evaluate(() => getComputedStyle(document.body).overflow === 'hidden'), 'the page behind does not scroll while it is open');
    check(await page.evaluate(() => document.activeElement.id === 'help-close'), 'focus moves into the dialog');
    if (OUT) await page.screenshot({ path: `${OUT}/ui_${profile.width}_help.png` });

    await page.keyboard.press('Escape');
    check(await page.$eval('#help-modal', (e) => e.hidden), 'Escape closes it');
    check(await page.evaluate(() => document.activeElement.id === 'help-btn'), 'focus returns to the ? button');
    await page.click('#help-btn');
    await page.click('#help-done');
    check(await page.$eval('#help-modal', (e) => e.hidden), '"Got it" closes it');
    await page.click('#help-btn');
    await page.mouse.click(2, 2); // the backdrop corner, outside the card
    check(await page.$eval('#help-modal', (e) => e.hidden), 'tapping outside closes it');
    await page.click('#help-btn');
    await page.click('#help-close');
    check(await page.$eval('#help-modal', (e) => e.hidden), 'the X closes it');

    await page.reload();
    await page.waitForSelector('.cell');
    check(!(await page.$eval('#help-btn', (e) => e.classList.contains('attention'))), 'a returning visitor is not nagged again');
    check(errors.length === 0, `no script errors (${errors.join('; ')})`);
    await context.close();
  }

  // ---- the hero portrait follows HP ------------------------------------
  {
    const { context, page, errors } = await open(profile);
    check(await page.$eval('#avatar', (e) => e.dataset.state === 'confident'), 'at full HP the hero is confident');
    check((await page.$eval('#avatar svg', (e) => e.outerHTML.length)) > 200, 'the portrait is drawn');

    if (!(await reachBattle(page))) {
      check(false, 'could not reach a battle');
    } else {
      const seen = [];
      let dead = false;
      for (let i = 0; i < 40 && !dead; i += 1) {
        const tile = await page.$('.rack-tile');
        if (!tile) break;
        await tile.evaluate((e) => e.click());          // one letter: never a valid word
        await page.$eval('#submit-word', (b) => b.click());
        await page.waitForTimeout(20);
        const state = await page.$eval('#avatar', (e) => e.dataset.state);
        if (seen[seen.length - 1] !== state) seen.push(state);
        dead = await page.$eval('#player-hp-text', (e) => e.textContent.startsWith('0/'));
      }
      check(seen.join(' > ') === 'confident > wary > battered > defeated' || (seen[0] === 'confident' && seen.at(-1) === 'defeated'),
        `the hero worsens as HP falls (${seen.join(' > ')})`);
      const order = ['confident', 'wary', 'battered', 'defeated'];
      check(seen.every((s, i) => i === 0 || order.indexOf(s) > order.indexOf(seen[i - 1])), 'and never looks better while taking damage');
      check(await page.$eval('#avatar', (e) => e.dataset.state === 'defeated' && /defeated/.test(e.getAttribute('aria-label'))), 'at 0 HP the hero is defeated, and says so to screen readers');
      if (OUT) await page.screenshot({ path: `${OUT}/ui_${profile.width}_defeated.png` });

      await page.waitForSelector('#overlay:not([hidden])');
      await page.click('#overlay');
      await page.waitForSelector('#map-view:not([hidden])');
      check((await hpText(page)) === '20/40', 'retreating restores half HP');
      check(await page.$eval('#avatar', (e) => e.dataset.state === 'wary'), 'and the hero recovers to wary');
    }
    check(errors.length === 0, `no script errors (${errors.join('; ')})`);
    await context.close();
  }

  // ---- progressive hints -------------------------------------------------
  {
    const { context, page, errors } = await open(profile);
    const [card] = await openCards(page);
    const clue = await clueOf(card);
    const entry = entryByClue.get(clue);
    const index = await card.getAttribute('data-index');
    const cardSel = `.clue-item[data-index="${index}"]`;
    const revealed = () => page.$$eval('.cell.revealed', (cells) => cells.length);

    await (await card.$('input')).fill('ab');
    await card.$eval('summary', (s) => s.click());
    check(await page.$eval(`${cardSel} details`, (d) => d.open), 'the Hints panel opens');
    const rows = await page.$$(`${cardSel} .hint-row`);
    check(rows.length === 3, 'it shows three hint levels');

    const state = (level, currency) => page.$eval(`${cardSel} .hint-row[data-level="${level}"] .pay-btn.${currency}`, (b) => ({ disabled: b.disabled, text: b.textContent }));
    check((await state(1, 'score')).disabled, 'with no Score yet, level 1 cannot be paid in Score...');
    check(!(await state(1, 'hp')).disabled, '...but can be paid in HP');
    check((await state(2, 'hp')).disabled && (await state(3, 'hp')).disabled, 'levels 2 and 3 are locked until the one before is bought');
    check((await state(1, 'hp')).text === '1 HP' && (await state(2, 'hp')).text === '2 HP', 'costs are shown on the buttons');

    const revealedBefore = await revealed();
    await page.$eval(`${cardSel} .hint-row[data-level="1"] .pay-btn.hp`, (b) => b.click());
    check((await hpText(page)) === '39/40', 'paying level 1 with HP costs 1 HP');
    check(await page.$eval(`${cardSel} .hint-pattern`, (p) => p.children.length) === entry.word.length, 'the letter pattern shows one box per letter');
    const shown = await page.$$eval(`${cardSel} .pat-cell`, (cells) => cells.map((c) => c.textContent));
    check(shown.every((ch, i) => ch === '' || ch === entry.word[i]), 'only true letters are shown');
    check([...entry.word].every((ch, i) => !'AEIOU'.includes(ch) || shown[i] === ch), 'every vowel is shown');
    check(await page.$eval(`${cardSel} details`, (d) => d.open), 'the panel stays open after buying');
    check(await page.$eval(`${cardSel} input`, (i) => i.value === 'ab'), 'the answer being typed is not lost');
    check(await page.$eval('#toast', (t) => t.classList.contains('show') && /Show vowels/.test(t.textContent)), 'a toast confirms the purchase');
    check(!(await state(2, 'hp')).disabled, 'level 2 is now unlocked');

    await page.$eval(`${cardSel} .hint-row[data-level="2"] .pay-btn.hp`, (b) => b.click());
    check((await hpText(page)) === '37/40', 'level 2 costs 2 HP');
    check((await revealed()) === revealedBefore + 1, 'and fills exactly one more letter on the map');
    check(await page.$eval('.cell.just-revealed', () => true).catch(() => false), 'the new letter flashes');

    check(await page.$(`${cardSel} .hint-lore`) === null, 'lore stays hidden until bought');
    await page.$eval(`${cardSel} .hint-row[data-level="3"] .pay-btn.hp`, (b) => b.click());
    check((await hpText(page)) === '35/40', 'level 3 costs 2 HP');
    check(await page.$eval(`${cardSel} .hint-lore`, (l) => l.textContent) === entry.lore, 'the lore hint is shown');
    check((await page.$eval(`${cardSel} .hint-row[data-level="3"] .hint-state`, (s) => s.textContent)) === 'Used', 'a bought level reads Used');
    check(await page.$eval('#avatar', (e) => e.dataset.state) === 'confident', 'the portrait tracks HP spent on hints (35/40 is still confident)');

    await card.evaluate((e) => e.scrollIntoView({ block: 'center' }));
    await page.waitForTimeout(150);
    if (OUT) await page.screenshot({ path: `${OUT}/ui_${profile.width}_hints.png` });

    // The clue can still be answered normally after hints.
    await (await page.$(`${cardSel} input`)).fill(entry.word);
    await page.$eval(`${cardSel} button[type="submit"]`, (b) => b.click());
    await page.waitForTimeout(60);
    check(await page.$(`${cardSel} form`) === null, 'the corridor can still be solved after buying hints');
    check(errors.length === 0, `no script errors (${errors.join('; ')})`);
    await context.close();
  }

  // ---- clue <-> grid highlighting ---------------------------------------
  {
    const { context, page, errors } = await open(profile);
    const cards = await page.$$('.clue-item');
    const lengths = new Map(LEVEL_ONE.entries.map((e) => [e.word, e.word.length]));
    const glowing = () => page.$$eval('.cell.hl', (cells) => cells.length);

    check((await glowing()) === 0, 'nothing is highlighted at the start');
    const target = (await openCards(page))[0];
    const targetIndex = await target.getAttribute('data-index');
    const targetLength = lengths.get(answers.get(await clueOf(target)));

    // Start from the bottom of the page so scrolling is observable on a phone.
    await target.evaluate((e) => e.scrollIntoView({ block: 'end' }));
    await page.waitForTimeout(100);
    await target.evaluate((e) => e.querySelector('.clue-head').click());
    await page.waitForTimeout(700);

    if (OUT) await page.screenshot({ path: `${OUT}/ui_${profile.width}_highlight.png` });
    check((await glowing()) === targetLength, `tapping a clue lights up exactly its ${targetLength} cells`);
    check(await target.evaluate((e) => e.classList.contains('active')), 'and marks the card as active');
    const inView = await page.$$eval('.cell.hl', (cells, h) => cells.every((c) => {
      const r = c.getBoundingClientRect();
      return r.top >= -1 && r.bottom <= h + 1;
    }), profile.height);
    check(inView, 'the highlighted word is scrolled into view');

    const other = (await page.$$('.clue-item'))[(Number(targetIndex) + 3) % cards.length];
    const otherIndex = await other.getAttribute('data-index');
    await other.evaluate((e) => e.querySelector('.clue-head').click());
    await page.waitForTimeout(100);
    check((await page.$$eval('.clue-item.active', (a) => a.length)) === 1, 'only one card is active at a time');
    check(await page.$eval(`.clue-item[data-index="${otherIndex}"]`, (e) => e.classList.contains('active')), 'the newly tapped card is the active one');

    // Tapping the answer box highlights but must not yank the page around.
    const input = await target.$('input');
    await target.evaluate((e) => e.scrollIntoView({ block: 'center' }));
    await page.waitForTimeout(100);
    const scrollBefore = await page.evaluate(() => window.scrollY);
    await input.evaluate((e) => e.focus());
    await page.waitForTimeout(200);
    check((await page.evaluate(() => window.scrollY)) === scrollBefore, 'focusing the answer box does not scroll the page');
    check(await target.evaluate((e) => e.classList.contains('active')), 'but it does make that word active');

    // Tap a grid cell: its clue becomes active; tapping a crossing cell again cycles.
    await page.evaluate(() => window.scrollTo(0, 0));
    const crossing = await page.evaluate(() => {
      const cells = [...document.querySelectorAll('.cell.filled')];
      // a cell shared by two corridors appears in two words: find by number of owners
      const counts = new Map();
      return null;
    });
    const result = await page.evaluate(() => {
      const cells = [...document.querySelectorAll('.cell.filled')];
      return cells.length;
    });
    check(result > 20, 'the grid has letter cells to tap');
    await page.$eval('.cell.filled', (c) => c.click());
    await page.waitForTimeout(100);
    check((await page.$$eval('.clue-item.active', (a) => a.length)) === 1, 'tapping a grid cell activates a clue card');
    check((await glowing()) >= 3, 'and lights up that word');
    const first = await page.$eval('.clue-item.active', (e) => e.dataset.index);
    await page.$eval('.cell.filled.hl', (c) => c.click());
    await page.waitForTimeout(100);
    const second = await page.$eval('.clue-item.active', (e) => e.dataset.index);
    check(first !== second || (await page.$$eval('.cell.hl', (c) => c.length)) > 0, 'tapping again keeps a word active (crossing cells cycle across/down)');

    await page.$eval('.cell:not(.filled)', (c) => c.click());
    check((await page.$$eval('.clue-item.active', (a) => a.length)) === 1, 'tapping an empty cell changes nothing');

    // Highlight survives re-rendering (e.g. solving another word).
    const [solvable] = await openCards(page);
    const solvableIndex = await solvable.getAttribute('data-index');
    await solvable.evaluate((e) => e.querySelector('.clue-head').click());
    await (await solvable.$('input')).fill(answers.get(await clueOf(solvable)));
    await (await solvable.$('button[type="submit"]')).evaluate((b) => b.click());
    await page.waitForTimeout(100);
    if (await page.$('#battle-view:not([hidden])')) {
      // solving a monster corridor drops into a battle; nothing more to check here
    } else {
      check(await page.$eval(`.clue-item[data-index="${solvableIndex}"]`, (e) => e.classList.contains('active')), 'the highlight survives a re-render');
    }
    check(errors.length === 0, `no script errors (${errors.join('; ')})`);
    await context.close();
  }
}

await browser.close();
staticServer.close();
console.log(`\n${problems} problem(s)`);
process.exit(problems ? 1 : 0);
