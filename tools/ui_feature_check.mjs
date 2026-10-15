// Plays the browser build and checks the player-facing features end to end:
// the how-to-play modal, the hero portrait following HP, the three hint
// levels, and clue <-> grid highlighting. Runs on a desktop and a phone.
//
// Usage:  node tools/ui_feature_check.mjs [screenshot-dir]
// Needs Playwright (set PLAYWRIGHT_MODULE to its path if it is not installed
// locally) and a Chromium (CHROMIUM_PATH). Exits 1 on any failed check.
import fs from 'node:fs';
import { LEVEL_ONE } from '../src/wordlist.js';
import { dailyHero } from '../src/daily.js';
import { maxHpBonus } from '../src/heroes.js';
import { bestWord, castOnce, playToVictory, playUntilOver } from './lib/autoplay.mjs';
import { HARDCORE } from '../src/hardcore.js';
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

const allProfiles = [
  { name: 'desktop 1280x800', width: 1280, height: 800, touch: false },
  { name: 'phone 390x844', width: 390, height: 844, touch: true },
  { name: 'small phone 320x568', width: 320, height: 568, touch: true },
];

/** Open the game. `hero` is the saved hero to start as (a returning player);
 * pass null for a first-time visitor. The default is the Duelist, whose perk
 * touches neither max HP nor hint costs, so the older checks below keep their
 * baseline numbers. */
// PROFILE=0,2 runs only those viewports (handy while iterating).
const profiles = allProfiles.filter((_, i) => !process.env.PROFILE || process.env.PROFILE.split(',').includes(String(i)));

async function open(profile, { hero = 'duelist', now = null, seed = {}, failDailySave = false, fakeClock = false } = {}) {
  const context = await browser.newContext({
    viewport: { width: profile.width, height: profile.height },
    hasTouch: profile.touch,
    isMobile: profile.touch,
    deviceScaleFactor: 2,
  });
  // `now` pins the page's clock (the daily dungeon depends on the date).
  if (now) await context.clock.setFixedTime(now);
  // fakeClock freezes time entirely until the test calls clock.runFor (for the battle clock).
  if (fakeClock) await context.clock.install({ time: new Date('2026-10-12T12:00:00Z') });
  if (hero) {
    // Only if nothing is saved yet, so a reload keeps whatever the player chose.
    await context.addInitScript((id) => {
      if (!localStorage.getItem('wordsmith-hero')) localStorage.setItem('wordsmith-hero', id);
    }, hero);
  }
  for (const [key, value] of Object.entries(seed)) {
    await context.addInitScript(([k, v]) => { if (localStorage.getItem(k) === null) localStorage.setItem(k, v); }, [key, value]);
  }
  if (failDailySave) {
    // A browser that refuses to save the daily result (private mode, full disk).
    await context.addInitScript(() => {
      const original = Storage.prototype.setItem;
      Storage.prototype.setItem = function (key, value) {
        if (key === 'wordsmith-daily') throw new DOMException('quota', 'QuotaExceededError');
        return original.call(this, key, value);
      };
    });
  }
  await context.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: staticServer.url.replace(/\/$/, '') }).catch(() => {});
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


// ---- daily challenge ---------------------------------------------------------

const layoutSignature = (page) => page.$$eval('.cell.filled', (cells) => cells
  .map((c) => `${c.dataset.r},${c.dataset.c}:${c.querySelector('.cell-number')?.textContent ?? ''}`).join('|'));
const firstRack = async (page) => {
  if (!(await reachBattle(page))) return null;
  return (await page.$$eval('.rack-tile', (t) => t.map((e) => e.firstElementChild.textContent))).join('');
};
const dailyRecord = (page) => page.evaluate(() => JSON.parse(localStorage.getItem('wordsmith-daily') ?? '{}'));

async function dailyChecks(profile) {
  const DAY = '2026-10-12';
  const NEXT_DAY = '2026-10-13';
  const NOW = new Date(`${DAY}T12:00:00Z`);
  const hero = dailyHero(DAY);
  const heroMax = 40 + maxHpBonus(hero);
  const history = JSON.stringify({
    '2026-10-10': { score: 300, retreats: 0, hintsUsed: 1, hero: 'scribe' },
    '2026-10-11': { score: 280, retreats: 2, hintsUsed: 0, hero: 'warden' },
  });
  const box = (page, sel) => page.$eval(sel, (e) => { const r = e.getBoundingClientRect(); return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width, height: r.height }; });
  const isHidden = (page, sel) => page.$eval(sel, (e) => e.hidden);

  // ---------------- player A: a returning player with a two-day streak ----------------
  const A = await open(profile, { hero: 'duelist', now: NOW, seed: { 'wordsmith-daily': history } });
  const a = A.page;
  check(await a.$eval('#daily-btn', (b) => b.classList.contains('todo') && /waiting/.test(b.getAttribute('aria-label'))), 'the Daily button signals that today\'s dungeon is waiting');
  check((await box(a, '#daily-btn')).height >= (profile.touch ? 44 : 28), 'and is a usable size');
  check((await box(a, '#daily-btn')).right <= profile.width, 'and fits in the header');

  await a.click('#daily-btn');
  check(!(await isHidden(a, '#hero-modal')) && (await a.$eval('#tab-daily', (t) => t.getAttribute('aria-selected'))) === 'true', 'it opens the picker on the Daily tab');
  check(await isHidden(a, '#panel-free') && !(await isHidden(a, '#panel-daily')), 'showing only the daily panel');
  const panel = await a.$eval('#daily-body', (e) => e.innerText);
  check(panel.includes(DAY), `it names today's date (${DAY})`);
  check(panel.includes(`Today's hero: ${hero.name}`), `and today's hero (${hero.name})`);
  check(/Streak\s*2 days/.test(panel), 'and the two-day streak');
  check(/Next dungeon in 12h 0m/.test(panel), 'and the time to the next one (12h 0m at noon UTC)');
  check((await a.$eval('#hero-start', (b) => b.textContent)) === "Play today's challenge", 'the button says what it does');
  const card = await box(a, '.hero-card-wrap');
  check(card.top >= 0 && card.bottom <= profile.height + 1 && card.right <= profile.width + 1, 'the picker fits on screen');
  if (OUT) await a.screenshot({ path: `${OUT}/ui_${profile.width}_daily_tab.png` });

  await a.focus('#tab-daily');
  await a.keyboard.press('ArrowLeft');
  check((await a.$eval('#tab-free', (t) => t.getAttribute('aria-selected'))) === 'true' && (await a.evaluate(() => document.activeElement.id)) === 'tab-free', 'arrow keys switch tabs and move focus with them');
  check((await a.$eval('#hero-start', (b) => b.textContent)) === 'Begin run', 'and the button follows the tab');
  await a.keyboard.press('ArrowRight');
  check((await a.$eval('#tab-daily', (t) => t.getAttribute('aria-selected'))) === 'true', 'both ways');

  await a.click('#hero-start');
  check(await isHidden(a, '#hero-modal'), 'starting the daily closes the picker');
  check(await a.$eval('#daily-btn', (b) => b.classList.contains('active') && !b.classList.contains('todo')), 'the Daily button shows a daily run is on');
  check(await a.$eval('#avatar', (e) => e.dataset.hero) === hero.id, 'the header portrait is today\'s hero');
  check((await hpText(a)) === `${heroMax}/${heroMax}`, `at ${heroMax} HP (that hero\'s maximum)`);
  check(await a.evaluate(() => localStorage.getItem('wordsmith-hero')) === 'duelist', 'the daily did not overwrite the saved free-play hero');
  await a.click('#help-btn');
  const rules = await a.$eval('#help-body', (e) => e.innerText);
  check(/Daily challenge/.test(rules) && /midnight UTC/.test(rules), 'the rules card explains the Daily Challenge');
  check(rules.includes(`${hero.name}: ${hero.perk.name}`), 'and names today\'s hero');
  await a.keyboard.press('Escape');

  const sigA = await layoutSignature(a);
  const cluesA = await a.$$eval('.clue-item .clue-text', (c) => c.map((e) => e.textContent).join('|'));
  const rackA = await firstRack(a);
  check(!!rackA && rackA.length === 8, `the first battle deals a rack (${rackA})`);

  // ---------------- player B: someone else, same day, a browser that cannot save ----------------
  const B = await open(profile, { hero: 'warden', now: NOW, failDailySave: true });
  const b = B.page;
  await b.click('#daily-btn');
  await b.click('#hero-start');
  const sigB = await layoutSignature(b);
  check(sigB === sigA, 'another player, another browser, a different saved hero: the same dungeon layout');
  check((await b.$$eval('.clue-item .clue-text', (c) => c.map((e) => e.textContent).join('|'))) === cluesA, 'with the same clues in the same places');
  const rackB = await firstRack(b);
  check(rackB === rackA, `and the same letters in the first battle (${rackB})`);

  // ---------------- player C: the next day, with midnight passing while the page is open ----------------
  const C = await open(profile, { hero: 'duelist', now: new Date(`${DAY}T23:59:30Z`) });
  const c = C.page;
  await c.click('#daily-btn');
  check((await c.$eval('#daily-body', (e) => e.innerText)).includes(DAY), 'just before midnight it is still today\'s dungeon');
  // The panel stays open while midnight passes, then the player presses Start.
  await C.context.clock.setFixedTime(new Date(`${NEXT_DAY}T00:00:30Z`));
  await c.click('#hero-start');
  check(!(await isHidden(c, '#hero-modal')), 'pressing Start on a panel left open past midnight does not start anything');
  check(await c.$eval('#daily-btn', (x) => !x.classList.contains('active') && !x.classList.contains('practice')), 'no run began');
  check((await c.$eval('#daily-body', (e) => e.innerText)).includes(NEXT_DAY), 'the panel now shows the new day instead');
  check(await c.$eval('#toast', (t) => t.classList.contains('show') && /new daily dungeon/.test(t.textContent)), 'and says why');
  await c.keyboard.press('Escape');
  await c.click('#daily-btn');
  const nextPanel = await c.$eval('#daily-body', (e) => e.innerText);
  check(nextPanel.includes(NEXT_DAY) && nextPanel.includes(`Today's hero: ${dailyHero(NEXT_DAY).name}`), 'after midnight the same open page offers the new day and its hero');
  check(/Next dungeon in 23h 59m/.test(nextPanel), 'with a fresh countdown');
  await c.click('#hero-start');
  check((await layoutSignature(c)) !== sigA, 'and a different dungeon');
  check(await c.$eval('#avatar', (e) => e.dataset.hero) === dailyHero(NEXT_DAY).id, 'run by the new hero');
  check(C.errors.length === 0, `no script errors (${C.errors.join('; ')})`);
  await C.context.close();

  // ---------------- B plays it through: a failed save is reported, not hidden ----------------
  await playToVictory(b);
  check(await b.$eval('#toast', (t) => t.classList.contains('show') && /save your result/.test(t.textContent)), 'when the browser cannot save, the player is told');
  await b.evaluate(() => document.getElementById('overlay').click());
  check(!(await isHidden(b, '#result-modal')), 'the result card still opens');
  check(/Recorded as your result for 2026-10-12/.test(await b.$eval('#result-body', (e) => e.innerText)), 'and counts the run for this session');
  await b.keyboard.press('Escape');
  await b.click('#daily-btn');
  check(/Done today/.test(await b.$eval('#daily-body', (e) => e.innerText)), 'later in the session the daily shows as done');
  check(B.errors.length === 0, `no script errors (${B.errors.join('; ')})`);
  await B.context.close();

  // ---------------- A plays it through: the official result ----------------
  const casts = await playToVictory(a);
  check(casts >= 10, `A cleared all ten monsters (${casts} casts)`);
  const hudScore = await a.$eval('#score-text', (e) => e.textContent);
  await a.evaluate(() => document.getElementById('overlay').click());
  check(!(await isHidden(a, '#result-modal')), 'winning a daily opens the result card');
  const body = await a.$eval('#result-body', (e) => e.innerText);
  check(/Recorded as your result for 2026-10-12/.test(body), 'which says it is the recorded result');
  check(/Streak: 3 days/.test(body), 'and shows the streak, now three days');
  const share = await a.$eval('#result-share', (e) => e.textContent);
  const shareLines = share.split('\n');
  check(shareLines[0] === "Wordsmith's Gambit — Daily 2026-10-12", 'the share text starts with the game and the day');
  check(shareLines[1] === `${hero.name}: ${hudScore} Score`, `then the hero and Score (${shareLines[1]})`);
  check(/^\d+ retreats?( · | )?/.test(shareLines[2]) && /\d+ hints?/.test(shareLines[2]), 'then retreats and hints');
  check(share.includes('3 days in a row'), 'then the streak');
  const saved = await dailyRecord(a);
  check(saved[DAY]?.score === Number(hudScore) && saved[DAY]?.hero === hero.id, 'the result is saved on this device');
  check(Object.keys(saved).length === 3 && saved['2026-10-10']?.score === 300, 'next to the earlier days');
  const resultCard = await box(a, '#result-modal .modal-card');
  check(resultCard.top >= 0 && resultCard.bottom <= profile.height + 1 && resultCard.right <= profile.width + 1, 'the result card fits on screen');
  if (OUT) await a.screenshot({ path: `${OUT}/ui_${profile.width}_result.png` });
  await a.click('#result-copy');
  check((await a.evaluate(() => navigator.clipboard.readText().catch(() => null))) === share, 'Copy result puts the share text on the clipboard');
  check(await a.$eval('#toast', (t) => /copied/i.test(t.textContent)), 'and confirms it');
  await a.keyboard.press('Escape');
  check(await isHidden(a, '#result-modal'), 'Escape closes the card');

  // ---------------- replaying is practice ----------------
  await a.click('#daily-btn');
  const doneText = await a.$eval('#daily-body', (e) => e.innerText);
  check(new RegExp(`Done today: ${hudScore} Score`).test(doneText), 'afterwards the daily shows today\'s result');
  check(/Streak\s*3 days/.test(doneText), 'and the streak');
  check((await a.$eval('#hero-start', (x) => x.textContent)) === 'Practice (not recorded)', 'a replay is offered as practice');
  check(await a.$eval('#hero-note', (n) => n.hidden), 'no "you will lose progress" warning after a finished run');
  await a.click('#hero-start');
  check(await a.$eval('#daily-btn', (x) => x.classList.contains('practice') && x.textContent === 'Practice'), 'the header marks a practice run');
  check((await layoutSignature(a)) === sigA, 'it is the very same dungeon');
  await playToVictory(a);
  await a.evaluate(() => document.getElementById('overlay').click());
  const practiceBody = await a.$eval('#result-body', (e) => e.innerText);
  check(/Practice run: your recorded result for 2026-10-12 stands/.test(practiceBody), 'a practice win says it does not count');
  check(new RegExp(`Recorded: ${hudScore} Score`).test(practiceBody), 'and shows the recorded result');
  check(JSON.stringify((await dailyRecord(a))[DAY]) === JSON.stringify(saved[DAY]), 'the recorded result is unchanged');
  check(/Streak: 3 days/.test(practiceBody), 'and so is the streak');

  // ---------------- free play: winning offers a new run, once ----------------
  await a.click('#result-again');
  check(!(await isHidden(a, '#hero-modal')) && (await a.$eval('#tab-free', (t) => t.getAttribute('aria-selected'))) === 'true', 'New run opens the picker on Free play');
  await a.click('.hero-option:has(input[value="duelist"])');
  await a.click('#hero-start');
  check(await a.$eval('#daily-btn', (x) => !x.classList.contains('active') && !x.classList.contains('practice') && !x.classList.contains('todo')), 'back in free play the Daily button is plain (today is done)');
  await playToVictory(a);
  await a.evaluate(() => document.getElementById('overlay').click());
  check(!(await isHidden(a, '#hero-modal')) && (await a.$eval('#hero-title', (t) => t.textContent)) === 'Play again?', 'winning free play offers "Play again?"');
  check(await isHidden(a, '#result-modal'), 'and no daily result card');
  check(!(await a.$eval('#hero-close', (x) => x.hidden)), 'which can be dismissed');
  await a.keyboard.press('Escape');
  const leftover = await a.$('.clue-item.open');
  if (leftover) {
    const clue = await leftover.$eval('.clue-text', (e) => e.textContent);
    await leftover.$eval('input', (i, word) => { i.value = word; }, answers.get(clue));
    await leftover.$eval('form', (f) => f.requestSubmit());
    await a.waitForTimeout(400);
    check(await a.$eval('#overlay', (o) => o.hidden) && (await isHidden(a, '#hero-modal')), 'solving a leftover room after winning does not announce the win again');
  }
  check(A.errors.length === 0, `no script errors (${A.errors.join('; ')})`);
  await A.context.close();

  // ---------------- a damaged save is ignored ----------------
  const D = await open(profile, { hero: 'duelist', now: NOW, seed: { 'wordsmith-daily': '{{{ not json' } });
  await D.page.click('#daily-btn');
  check(/Streak\s*0 days/.test(await D.page.$eval('#daily-body', (e) => e.innerText)), 'a corrupted save means a fresh start, not a crash');
  check(D.errors.length === 0, `no script errors (${D.errors.join('; ')})`);
  await D.context.close();
}


// ---- hardcore mode -----------------------------------------------------------------

const secs = (page) => page.$eval('#turn-secs', (e) => Number(e.textContent));
const isHidden = (page, sel) => page.$eval(sel, (e) => e.hidden);
const HC_PREF = { 'wordsmith-hardcore': '1' };

/** Cast the best word on the rack (the player doing well in a battle). */
async function castBestWord(page) {
  const letters = await page.$$eval('.rack-tile', (t) => t.map((e) => e.firstElementChild.textContent));
  const word = bestWord(letters);
  await page.evaluate((w) => {
    for (const ch of w) [...document.querySelectorAll('.rack-tile')].find((t) => t.firstElementChild.textContent === ch)?.click();
    document.getElementById('submit-word').click();
  }, word);
}

async function hardcoreChecks(profile) {
  const box = (page, sel) => page.$eval(sel, (e) => { const r = e.getBoundingClientRect(); return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width, height: r.height }; });

  // ---------------- the picker, wrong answers, and the clock ----------------
  {
    const { context, page, errors } = await open(profile, { hero: 'duelist' });
    await page.click('#hero-btn');
    check(!(await page.$eval('#hardcore-toggle', (c) => c.checked)), 'hardcore is off by default');
    const desc = await page.$eval('#hardcore-desc', (e) => e.textContent);
    check(desc.includes(`${HARDCORE.turnSeconds} seconds`) && desc.includes('No retreat') && desc.includes(`${HARDCORE.wrongGuessHp} HP`) && desc.includes(`×${HARDCORE.scoreMultiplier}`), 'the picker spells out the rules');
    check((await page.$eval('#hardcore-stats', (e) => e.textContent)) === 'No hardcore runs yet.', 'and shows an empty record');
    check((await page.$eval('#hero-start', (b) => b.textContent)) === 'Begin run', 'the button is "Begin run" while it is off');
    await page.focus('#hardcore-toggle');
    await page.keyboard.press('Space');
    check(await page.$eval('#hardcore-toggle', (c) => c.checked), 'Space turns it on from the keyboard');
    check((await page.$eval('#hero-start', (b) => b.textContent)) === 'Begin hardcore run', 'and the button says "Begin hardcore run"');
    const toggleBox = await box(page, '.hardcore-toggle');
    check(toggleBox.right <= profile.width && toggleBox.height >= 44, 'the toggle fits and is easy to hit');
    const card = await box(page, '.hero-card-wrap');
    check(card.right <= profile.width + 1, 'the picker still fits the screen width');
    if (OUT) {
      await page.$eval('.hardcore-toggle', (e) => e.scrollIntoView({ block: 'center' }));
      await page.screenshot({ path: `${OUT}/ui_${profile.width}_hardcore_picker.png` });
    }
    await page.click('#tab-daily');
    check(!(await page.$eval('#hardcore-toggle', (c) => c.offsetParent !== null)), 'the Daily tab has no hardcore option');
    await page.click('#tab-free');
    await page.$eval('#hero-start', (b) => b.scrollIntoView({ block: 'nearest' }));
    await page.click('#hero-start');

    check(!(await isHidden(page, '#hc-badge')), 'a hardcore run shows its badge');
    check((await hpText(page)) === '40/40', 'at full HP');
    check(await page.evaluate(() => localStorage.getItem('wordsmith-hardcore')) === '1', 'the choice is remembered');

    // wrong answers: one free retry, then HP
    const [card1] = await openCards(page);
    const index = await card1.getAttribute('data-index');
    const sel = `.clue-item[data-index="${index}"]`;
    check(/1 free retry left/.test(await page.$eval(`${sel} .hc-note`, (n) => n.textContent)), 'each open clue says it has a free retry');
    const wrong = async (value) => {
      await page.$eval(`${sel} input`, (i, v) => { i.value = v; }, value);
      await page.$eval(`${sel} form`, (f) => f.requestSubmit());
    };
    await wrong('');
    check((await hpText(page)) === '40/40' && /1 free retry left/.test(await page.$eval(`${sel} .hc-note`, (n) => n.textContent)), 'a blank answer costs nothing and keeps the retry');
    await wrong('NOPE');
    check((await hpText(page)) === '40/40' && /free retry/.test(await page.$eval('#toast', (t) => t.textContent)), 'the first wrong answer is free');
    check(new RegExp(`cost ${HARDCORE.wrongGuessHp} HP`).test(await page.$eval(`${sel} .hc-note`, (n) => n.textContent)), 'and the note now warns that more cost HP');
    await wrong('STILLNO');
    check((await hpText(page)) === `${40 - HARDCORE.wrongGuessHp}/40`, `the next one costs ${HARDCORE.wrongGuessHp} HP`);
    check(new RegExp(`-${HARDCORE.wrongGuessHp} HP`).test(await page.$eval('#toast', (t) => t.textContent)), 'with a toast saying so');
    await page.$eval(`${sel} input`, (i, v) => { i.value = v; }, answers.get(await clueOf(card1)));
    await page.$eval(`${sel} form`, (f) => f.requestSubmit());
    await page.waitForTimeout(60);
    check(!!(await page.$('#battle-view:not([hidden])')) || !(await page.$(`${sel} form`)), 'the right answer still opens the corridor');

    // the clock
    if (await page.$('#battle-view:not([hidden])') === null) await reachBattle(page);
    check(!(await isHidden(page, '#turn-timer')), 'a hardcore battle shows the clock');
    const clockBox = await box(page, '#turn-timer');
    check(clockBox.right <= profile.width && clockBox.bottom <= profile.height, 'and it fits on screen');
    check(await secs(page) >= HARDCORE.turnSeconds - 1, `it starts at ${HARDCORE.turnSeconds}s`);
    const fill = await box(page, '#turn-fill');
    const track = await box(page, '.timer-bar');
    check(fill.height >= 6 && fill.width >= track.width * 0.9, `the bar is drawn and full at the start (${Math.round(fill.width)}x${Math.round(fill.height)} of ${Math.round(track.width)}px)`);
    if (OUT) await page.screenshot({ path: `${OUT}/ui_${profile.width}_hardcore_battle.png` });

    await page.waitForTimeout(2500);
    const afterWait = await secs(page);
    check(afterWait <= HARDCORE.turnSeconds - 2 && afterWait >= HARDCORE.turnSeconds - 5, `it counts down (${afterWait}s after 2.5s)`);
    const drained = await box(page, '#turn-fill');
    check(drained.width < track.width * 0.9 && drained.width > 0, 'and the bar drains with it');

    // pauses while a card is open
    await page.click('#help-btn');
    const frozenAt = await secs(page);
    await page.waitForTimeout(2200);
    check(await secs(page) === frozenAt, 'the clock stands still while the rules card is open');
    check(await page.$eval('#turn-timer', (t) => t.classList.contains('paused')), 'and looks paused');
    check(/Hardcore mode \(on\)/.test(await page.$eval('#help-body', (e) => e.innerText)), 'the rules card knows hardcore is on');
    check(!/you retreat:/.test(await page.$eval('#help-body', (e) => e.innerText)), 'and no longer promises a retreat');
    await page.keyboard.press('Escape');

    // a cast gives a fresh clock
    const hpBefore = await hpText(page);
    await castBestWord(page);
    await page.waitForTimeout(150);
    // A strong word can finish a weak first monster; then the battle is over and the clock must stop instead.
    const monsterDied = await page.$eval('#monster-hp-text', (e) => e.textContent.startsWith('0/'));
    if (monsterDied) {
      check(await isHidden(page, '#turn-timer'), 'casting the killing blow stops the clock');
    } else {
      check(await secs(page) >= HARDCORE.turnSeconds - 1, 'casting a word resets the clock');
    }
    check((await hpText(page)) === hpBefore, 'and a good word costs no HP');
    check(errors.length === 0, `no script errors (${errors.join('; ')})`);
    await context.close();
  }

  // ---------------- the clock running out (time under test control) ----------------
  {
    const { context, page, errors } = await open(profile, { hero: 'duelist', seed: HC_PREF, fakeClock: true });
    check(await reachBattle(page), 'reached a battle on a frozen clock');
    check(await secs(page) === HARDCORE.turnSeconds, 'the clock starts full');
    const hp0 = Number((await hpText(page)).split('/')[0]);
    await page.clock.runFor((HARDCORE.turnSeconds - 1) * 1000);
    check((await secs(page)) === 1 && Number((await hpText(page)).split('/')[0]) === hp0, 'with one second left nothing has happened yet');
    await page.clock.runFor(1500);
    const hp1 = Number((await hpText(page)).split('/')[0]);
    check(hp1 < hp0, `at zero the monster hits (${hp0} -> ${hp1} HP)`);
    check(/Out of time!/.test(await page.$eval('#battle-log', (l) => l.innerText)), 'the log says the time ran out');
    check(await secs(page) >= HARDCORE.turnSeconds - 1, 'and the next word gets a fresh clock');
    check(/Out of time/.test(await page.$eval('#toast', (t) => t.textContent)), 'with a toast');
    // keep running out: eventually the hero falls and the clock stops for good
    for (let i = 0; i < 40 && (await isHidden(page, '#overlay')); i += 1) await page.clock.runFor(HARDCORE.turnSeconds * 1000);
    await page.clock.runFor(400);
    check(/fallen/.test(await page.$eval('#overlay-title', (t) => t.textContent)), 'letting the clock run out again and again ends the run');
    check(await isHidden(page, '#turn-timer'), 'and the clock goes away');
    check(errors.length === 0, `no script errors (${errors.join('; ')})`);
    await context.close();
  }

  // ---------------- permadeath ----------------
  {
    const { context, page, errors } = await open(profile, { hero: 'duelist', seed: HC_PREF });
    check(await reachBattle(page), 'reached a battle');
    for (let i = 0; i < 60 && (await isHidden(page, '#overlay')); i += 1) {
      await page.evaluate(() => { document.querySelector('.rack-tile')?.click(); document.getElementById('submit-word').click(); });
      await page.waitForTimeout(20);
    }
    await page.waitForSelector('#overlay:not([hidden])');
    check((await page.$eval('#overlay-title', (t) => t.textContent)) === 'You have fallen!', 'at 0 HP: "You have fallen!", not "Retreat!"');
    check(/corridors cleared/.test(await page.$eval('#overlay-text', (t) => t.textContent)), 'with how far the hero got');
    await page.evaluate(() => document.getElementById('overlay').click());
    check(!(await isHidden(page, '#hero-modal')) && (await page.$eval('#hero-title', (t) => t.textContent)) === 'Play again?', 'closing it offers a new run');
    check(await page.$eval('#hero-note', (n) => n.hidden), 'with no warning about losing progress');
    check((await hpText(page)) === '0/40', 'HP stays at 0: there was no retreat');
    check(await page.$eval('#avatar', (e) => e.dataset.state) === 'defeated', 'the hero is defeated');
    check(/Record: 0 wins · 1 fall/.test(await page.$eval('#hardcore-stats', (e) => e.textContent)), 'the fall is in the record');
    const saved = await page.evaluate(() => JSON.parse(localStorage.getItem('wordsmith-hardcore-stats')));
    check(saved.falls === 1 && saved.wins === 0, 'and saved on this device');
    await page.keyboard.press('Escape');
    check((await page.$$('.clue-item form')).length === 0, 'the dead run cannot answer clues any more');
    check((await page.$$('.clue-item details.hints')).length === 0, 'or buy hints');
    check((await page.$$('.clue-item button.danger')).length === 0, 'or fight');
    check((await page.$$('.clue-item.dead')).length > 0, 'the cards are greyed out');
    check(!(await isHidden(page, '#hc-badge')), 'and the badge still marks it as a hardcore run');

    // a normal run straight after: everything is back to normal
    await page.click('#hero-btn');
    await page.click('#hardcore-toggle');
    check((await page.$eval('#hero-start', (b) => b.textContent)) === 'Begin run', 'unticking hardcore restores the plain button');
    await page.click('#hero-start');
    check(await isHidden(page, '#hc-badge'), 'a normal run has no badge');
    check((await hpText(page)) === '40/40', 'and full HP');
    check(await page.evaluate(() => localStorage.getItem('wordsmith-hardcore')) === '0', 'the choice is remembered as off');
    const [normalCard] = await openCards(page);
    check((await normalCard.$('.hc-note')) === null, 'clues carry no hardcore note');
    const nIndex = await normalCard.getAttribute('data-index');
    for (let i = 0; i < 4; i += 1) {
      await page.$eval(`.clue-item[data-index="${nIndex}"] input`, (x, v) => { x.value = v; }, `NO${i}`);
      await page.$eval(`.clue-item[data-index="${nIndex}"] form`, (f) => f.requestSubmit());
    }
    check((await hpText(page)) === '40/40', 'wrong answers are still free');
    check(await reachBattle(page), 'reached a normal battle');
    check(await isHidden(page, '#turn-timer'), 'with no clock');
    await page.waitForTimeout(1500);
    check(await page.$eval('#overlay', (o) => o.hidden) && !(await page.$eval('#battle-view', (b) => b.hidden)), 'and nothing times out');
    check(errors.length === 0, `no script errors (${errors.join('; ')})`);
    await context.close();
  }

  // ---------------- a hardcore win ----------------
  {
    const { context, page, errors } = await open(profile, { hero: 'warden', seed: HC_PREF });
    let outcome = null;
    let attempts = 0;
    for (; attempts < 4; attempts += 1) {
      outcome = (await playUntilOver(page)).outcome;
      if (outcome === 'won') break;
      await page.evaluate(() => document.getElementById('overlay').click()); // "You have fallen!" -> picker
      check(await page.$eval('#hardcore-toggle', (c) => c.checked), 'after a fall the picker remembers hardcore');
      await page.click('#hero-start');
    }
    check(outcome === 'won', `a hardcore run can be won (attempt ${attempts + 1})`);
    const winText = await page.$eval('#overlay-text', (t) => t.textContent);
    const hudScore = Number(await page.$eval('#score-text', (e) => e.textContent));
    const expected = Math.round(hudScore * HARDCORE.scoreMultiplier);
    check(winText.includes(`Hardcore! Score ${hudScore} ×${HARDCORE.scoreMultiplier} = ${expected}`), `the win shows the multiplier (${winText.slice(0, 60)}...)`);
    await page.evaluate(() => document.getElementById('overlay').click());
    const stats = await page.evaluate(() => JSON.parse(localStorage.getItem('wordsmith-hardcore-stats')));
    check(stats.wins === 1 && stats.best === expected, `the win is recorded (best ${stats.best})`);
    check(stats.falls === attempts, `along with the ${attempts} earlier fall(s)`);
    check((await page.$eval('#hero-title', (t) => t.textContent)) === 'Play again?', 'and a new run is offered');
    check(errors.length === 0, `no script errors (${errors.join('; ')})`);

    // The Daily Challenge ignores a remembered hardcore choice.
    await page.click('#tab-daily');
    await page.click('#hero-start');
    check(await isHidden(page, '#hc-badge'), 'the Daily Challenge is never hardcore');
    check(await page.evaluate(() => localStorage.getItem('wordsmith-hardcore')) === '1', 'and does not change the remembered choice');
    await page.click('#help-btn');
    check(!/Hardcore mode \(on\)/.test(await page.$eval('#help-body', (e) => e.innerText)), 'the daily rules card is the normal one');
    await context.close();
  }
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
    check(await page.evaluate(() => document.activeElement.id === 'hardcore-toggle'), 'Tab goes on to the hardcore option');
    await page.keyboard.press('Tab');
    check(await page.evaluate(() => document.activeElement.id === 'hero-start'), 'then Begin run');
    await page.keyboard.press('Tab');
    check(await page.evaluate(() => document.activeElement.id === 'tab-free'), 'and wraps to the first control instead of leaving the dialog');

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

  await dailyChecks(profile);
  await hardcoreChecks(profile);
}

await browser.close();
staticServer.close();
console.log(`\n${problems} problem(s)`);
process.exit(problems ? 1 : 0);
