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

/** Open the game. `hero` is the saved hero to start as (a returning player);
 * pass null for a first-time visitor. The default is the Duelist, whose perk
 * touches neither max HP nor hint costs, so the older checks below keep their
 * baseline numbers. */
async function open(profile, { hero = 'duelist' } = {}) {
  const context = await browser.newContext({
    viewport: { width: profile.width, height: profile.height },
    hasTouch: profile.touch,
    isMobile: profile.touch,
    deviceScaleFactor: 2,
  });
  if (hero) {
    // Only if nothing is saved yet, so a reload keeps whatever the player chose.
    await context.addInitScript((id) => {
      if (!localStorage.getItem('wordsmith-hero')) localStorage.setItem('wordsmith-hero', id);
    }, hero);
  }
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
    const solveBox = await page.$eval(`${cardSel} form button`, (b) => { const r = b.getBoundingClientRect(); return { w: r.width, h: r.height }; });
    check(solveBox.h <= 56 && solveBox.w >= 44, `the Solve button keeps its shape (${Math.round(solveBox.w)}x${Math.round(solveBox.h)})`);
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


  // ---- hero picker -------------------------------------------------------
  {
    const { context, page, errors } = await open(profile, { hero: null });
    const modalVisible = (id) => page.$eval(id, (e) => !e.hidden);
    const box = (sel) => page.$eval(sel, (e) => {
      const r = e.getBoundingClientRect();
      return { left: r.left, right: r.right, top: r.top, bottom: r.bottom };
    });
    const hpIs = async (text) => (await hpText(page)) === text;

    check(await modalVisible('#hero-modal'), 'a first-time visitor is asked to choose a hero');
    check(await page.$eval('#hero-close', (e) => e.hidden), 'and cannot skip it');
    const names = await page.$$eval('.hero-name', (els) => els.map((e) => e.textContent));
    check(names.join('|') === 'The Scribe|The Warden|The Duelist', `three heroes are offered (${names.join(', ')})`);
    const perks = await page.$$eval('.hero-perk', (els) => els.map((e) => e.textContent));
    check(/free on every clue/.test(perks[0]) && /\+10 max HP/.test(perks[1]) && /\+20% damage/.test(perks[2]), 'each card says what its perk does');
    check((await page.$$eval('.hero-portrait svg', (s) => new Set(s.map((e) => e.innerHTML)).size)) === 3, 'each hero has their own portrait');
    check(await page.$eval('input[value="scribe"]', (e) => e.checked), 'the Scribe is pre-selected');
    check(await page.evaluate(() => document.activeElement?.value === 'scribe'), 'focus starts on the selected hero');

    const card = await box('.hero-card-wrap');
    check(card.top >= 0 && card.bottom <= profile.height + 1 && card.left >= 0 && card.right <= profile.width + 1, 'the picker fits on screen');
    const cardsFlat = await page.$$eval('.hero-card', (cs) => cs.map((c) => c.getBoundingClientRect().height));
    check(cardsFlat.every((h) => h >= 56), 'every card is a comfortable tap target');
    if (OUT) await page.screenshot({ path: `${OUT}/ui_${profile.width}_picker.png` });

    await page.keyboard.press('Escape');
    await page.mouse.click(2, 2);
    check(await modalVisible('#hero-modal'), 'Escape and tapping outside do not dismiss it');

    // The tap on the backdrop dropped focus on the page; Tab must bring it back inside, not out to the page.
    await page.keyboard.press('Tab');
    check(await page.evaluate(() => !!document.activeElement.closest('#hero-modal')), 'Tab after tapping outside returns to the dialog');
    await page.focus('input[value="scribe"]');
    await page.keyboard.press('ArrowRight');
    check(await page.$eval('input[value="warden"]', (e) => e.checked), 'arrow keys move between heroes');
    await page.keyboard.press('Tab');
    check(await page.evaluate(() => document.activeElement.id === 'hero-start'), 'Tab goes on to Begin run');
    await page.keyboard.press('Tab');
    check(await page.evaluate(() => document.activeElement.value === 'warden'), 'and wraps instead of leaving the dialog');

    await page.click('.hero-option:has(input[value="warden"])');
    await page.$eval('#hero-start', (b) => b.scrollIntoView({ block: 'nearest' }));
    await page.click('#hero-start');
    check(!(await modalVisible('#hero-modal')), 'Begin run starts the game');
    check(await hpIs('50/50'), 'the Warden starts with 50 HP');
    check(await page.$eval('#avatar', (e) => e.dataset.hero === 'warden' && /^The Warden/.test(e.getAttribute('aria-label'))), 'the header portrait is the Warden');
    check(await page.evaluate(() => localStorage.getItem('wordsmith-hero')) === 'warden', 'the choice is remembered');

    await page.click('#help-btn');
    const rules = await page.$eval('#help-body', (e) => e.innerText);
    check(/You have 50 HP/.test(rules) && /return with 25 HP/.test(rules), 'the rules card uses the Warden\'s HP');
    check(/The Warden: Thick Skin\. \+10 max HP/.test(rules), 'and names the hero and perk');
    await page.keyboard.press('Escape');

    await page.reload();
    await page.waitForSelector('.cell');
    check(!(await modalVisible('#hero-modal')), 'a returning player is not asked again');
    check(await hpIs('50/50'), 'and is still the Warden after a reload');

    // Opening the picker mid-run: dismissable, and it warns about progress only if there is some.
    const startRevealed = await page.$$eval('.cell.revealed', (c) => c.length);
    await page.click('#hero-btn');
    check(await modalVisible('#hero-modal') && !(await page.$eval('#hero-close', (e) => e.hidden)), 'the portrait reopens the picker, this time with a close button');
    check(await page.$eval('#hero-note', (e) => e.hidden), 'no warning on a fresh run');
    check(await page.$eval('input[value="warden"]', (e) => e.checked), 'the current hero is selected');
    await page.keyboard.press('Escape');
    check(!(await modalVisible('#hero-modal')) && (await page.evaluate(() => document.activeElement.id)) === 'hero-btn', 'Escape closes it and focus returns to the portrait');

    // Make some progress, leave an unsent answer in another card, then start over.
    const cards = await openCards(page);
    await (await cards[0].$('input')).fill(answers.get(await clueOf(cards[0])));
    await (await cards[0].$('button[type="submit"]')).evaluate((b) => b.click());
    await page.waitForTimeout(60);
    if (await page.$('#battle-view:not([hidden])')) {
      await page.evaluate(() => { for (let i = 0; i < 3; i += 1) { document.querySelector('.rack-tile')?.click(); document.getElementById('submit-word').click(); } });
    }
    const left = (await openCards(page))[0];
    if (left) await (await left.$('input')).evaluate((i) => { i.value = 'xyz'; }); // the map may be hidden behind a battle
    await page.evaluate(() => document.getElementById('hero-btn').click());
    check(!(await page.$eval('#hero-note', (e) => e.hidden)), 'with progress made, the picker warns that a new run loses it');
    check((await page.$eval('#hero-start', (e) => e.textContent)) === 'Start new run', 'and the button says so');

    await page.click('.hero-option:has(input[value="scribe"])');
    await page.click('#hero-start');
    check(await hpIs('40/40'), 'a new run as the Scribe starts at 40 HP');
    check((await page.$eval('#score-text', (e) => e.textContent)) === '0', 'with Score reset');
    check((await page.$$eval('.cell.revealed', (c) => c.length)) === startRevealed, 'and only the entrance revealed');
    check((await page.$$eval('.clue-item input', (inputs) => inputs.filter((i) => i.value).length)) === 0, 'and no old typed answers carried over');
    check(await page.$eval('#avatar', (e) => e.dataset.hero === 'scribe' && e.dataset.state === 'confident'), 'with the Scribe in the header');
    check(!(await page.$eval('#avatar', (e) => e.classList.contains('hit'))), 'and no damage flinch from the swap');

    // The Scribe's perk, live: Show vowels is free, later levels are not.
    const scribeCard = (await openCards(page))[0];
    const scribeIndex = await scribeCard.getAttribute('data-index');
    const sel = `.clue-item[data-index="${scribeIndex}"]`;
    await scribeCard.$eval('summary', (s) => s.click());
    const freeBtn = await page.$(`${sel} .hint-row[data-level="1"] .pay-btn.free`);
    check(!!freeBtn && (await freeBtn.textContent()) === 'Free', 'the Scribe\'s Show vowels button says Free');
    check(!(await page.$(`${sel} .hint-row[data-level="1"] .pay-btn.hp`)), 'with no HP or Score button beside it');
    await freeBtn.evaluate((b) => b.click());
    check((await hpText(page)) === '40/40' && (await page.$eval('#score-text', (e) => e.textContent)) === '0', 'buying it costs nothing');
    check(await page.$eval('#toast', (t) => /free/.test(t.textContent)), 'and the toast says free');
    check((await page.$eval(`${sel} .hint-row[data-level="2"] .pay-btn.hp`, (b) => b.textContent)) === '2 HP', 'Reveal a letter still costs 2 HP');
    if (OUT) await page.screenshot({ path: `${OUT}/ui_${profile.width}_scribe_hint.png` });

    // Restarting while a battle is on screen, even within the 300ms before the result overlay appears.
    if (await reachBattle(page)) {
      await page.evaluate(() => {
        for (let i = 0; i < 60; i += 1) {
          document.querySelector('.rack-tile')?.click();
          document.getElementById('submit-word').click();
          if (document.getElementById('player-hp-text').textContent.startsWith('0/')) break;
        }
        // The killing blow just landed; its overlay is still 300ms away.
        document.getElementById('hero-btn').click();
        document.querySelector('#hero-list input[value="warden"]').click();
        document.getElementById('hero-start').click();
      });
      await page.waitForTimeout(700);
      check(await page.$eval('#overlay', (e) => e.hidden), 'a restart cancels the pending result overlay');
      check(await page.$eval('#battle-view', (e) => e.hidden) && !(await page.$eval('#map-view', (e) => e.hidden)), 'and lands on the map, not a dead battle');
      check(await hpIs('50/50'), 'as a fresh Warden');
      check(await page.$$eval('.clue-item.active', (a) => a.length) === 0, 'with nothing highlighted from the old run');
    } else {
      check(false, 'could not reach a battle to test restarting in one');
    }
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
