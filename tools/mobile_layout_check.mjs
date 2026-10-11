// Plays the browser build at phone, tablet and desktop sizes and reports layout
// problems: horizontal overflow, an unreachable grid, undersized touch targets,
// iOS-zoom-triggering input text, and a full word overflowing the battle view.
//
// Usage:  node tools/mobile_layout_check.mjs [screenshot-dir]
// Needs Playwright (npm i -D playwright, or set PLAYWRIGHT_MODULE to its path)
// and a Chromium (set CHROMIUM_PATH, or let Playwright use its own). Starts its
// own static server, so nothing else needs to be running. Exits 1 on any problem.
import fs from 'node:fs';
import { LEVEL_ONE } from '../src/wordlist.js';
import { startStaticServer } from './lib/static_server.mjs';

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const OUT = process.argv[2];
const TAG = 'layout';
if (OUT) fs.mkdirSync(OUT, { recursive: true });

const staticServer = await startStaticServer();
const BASE = staticServer.url;

const answers = new Map(LEVEL_ONE.entries.map((e) => [e.clue, e.word]));
const sizes = [[320, 568], [375, 667], [390, 844], [768, 1024], [1280, 800]];

const browser = await chromium.launch(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {});
let problems = 0;
const report = (ok, msg) => { if (!ok) problems++; console.log(`${ok ? '  ok ' : '  BAD'} ${msg}`); };

for (const [w, h] of sizes) {
  const touch = w < 800;
  const ctx = await browser.newContext({ viewport: { width: w, height: h }, hasTouch: touch, isMobile: touch, deviceScaleFactor: 2 });
  // A returning player (no first-visit hero picker in the way). The Duelist has no HP or hint perks.
  await ctx.addInitScript(() => { if (!localStorage.getItem('wordsmith-hero')) localStorage.setItem('wordsmith-hero', 'duelist'); });
  const page = await ctx.newPage();
  await page.goto(BASE);
  await page.waitForSelector('.cell');
  console.log(`\n== ${w}x${h} map view`);

  const m = await page.evaluate(() => {
    const grid = document.getElementById('grid').getBoundingClientRect();
    const cell = document.querySelector('.cell').getBoundingClientRect();
    const input = document.querySelector('.clue-item input');
    const btn = document.querySelector('.clue-item button');
    return {
      docW: document.documentElement.scrollWidth, winW: window.innerWidth,
      gridRight: grid.right, cell: cell.width,
      inputFont: input ? parseFloat(getComputedStyle(input).fontSize) : null,
      inputH: input ? input.getBoundingClientRect().height : null,
      btnH: btn ? btn.getBoundingClientRect().height : null,
      hudRight: document.getElementById('hud').getBoundingClientRect().right,
      hudScrollW: document.getElementById('hud').scrollWidth, hudW: document.getElementById('hud').clientWidth,
    };
  });
  report(m.docW <= w, `page is not wider than the device (content ${m.docW}px vs ${w}px)`);
  report(m.gridRight <= w, `grid fits on screen (right edge ${Math.round(m.gridRight)} vs ${w})`);
  report(m.hudScrollW <= m.hudW + 1, `header fits (${m.hudScrollW} vs ${m.hudW})`);
  if (touch) {
    report(m.cell >= 16, `grid cells stay legible (${m.cell.toFixed(1)}px)`);
    report(m.inputFont >= 16, `answer input is >=16px so iOS does not zoom (${m.inputFont}px)`);
    report(m.inputH >= 40 && m.btnH >= 40, `answer input/button are tap sized (${m.inputH && m.inputH.toFixed(0)}/${m.btnH && m.btnH.toFixed(0)}px)`);
  }
  if (OUT) await page.screenshot({ path: `${OUT}/${TAG}_${w}_map.png` });

  // Play until a battle starts.
  let battleStarted = false;
  for (let i = 0; i < 30 && !battleStarted; i++) {
    const item = await page.$('.clue-item.open, .clue-item:not(.locked):not(.cleared):not(.pending-battle)');
    if (!item) break;
    const clue = await item.$eval('.clue-text', (e) => e.textContent);
    const word = answers.get(clue);
    if (!word) break;
    await (await item.$('input')).fill(word);
    const covered = await item.$eval('button', (b) => { const r = b.getBoundingClientRect(); const top = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2); return top !== b; });
    if (covered && i === 0) report(false, 'the Solve button is covered by another element (cannot be tapped)');
    await (await item.$('button')).evaluate((b) => b.click());
    await page.waitForTimeout(80);
    battleStarted = await page.evaluate(() => !document.getElementById('battle-view').hidden);
  }
  if (!battleStarted) { report(false, 'could not reach a battle to test'); await ctx.close(); continue; }

  console.log(`== ${w}x${h} battle view`);
  const b = await page.evaluate(() => {
    const q = (s) => document.querySelector(s);
    const tile = q('.rack-tile').getBoundingClientRect();
    const sub = q('#submit-word').getBoundingClientRect();
    const rack = q('#battle-rack').getBoundingClientRect();
    return { docW: document.documentElement.scrollWidth, winW: window.innerWidth, tileW: tile.width, tileH: tile.height, subH: sub.height, rackRight: rack.right, subBottom: sub.bottom, winH: window.innerHeight };
  });
  report(b.docW <= w, `battle view is not wider than the device (content ${b.docW}px vs ${w}px)`);
  if (touch) {
    report(b.tileW >= 40 && b.tileH >= 40, `rack tiles are tap sized (${b.tileW.toFixed(0)}x${b.tileH.toFixed(0)}px)`);
    report(b.subH >= 40, `Cast Word is tap sized (${b.subH.toFixed(0)}px)`);
  }
  const clear = await page.$eval('#clear-word', (e) => getComputedStyle(e).backgroundColor);
  const cast = await page.$eval('#submit-word', (e) => getComputedStyle(e).backgroundColor);
  report(clear !== cast, 'Clear is styled differently from Cast Word (readable contrast)');
  // Select enough letters to make a long word and make sure the slots do not overflow.
  const tiles = await page.$$('.rack-tile');
  for (const t of tiles) await t.evaluate((e) => e.click());
  const s = await page.evaluate(() => {
    const el = document.getElementById('word-slots');
    return { scrollW: el.scrollWidth, clientW: el.clientWidth, docW: document.documentElement.scrollWidth, winW: window.innerWidth };
  });
  report(s.scrollW <= s.clientW + 1 && s.docW <= w, `a full word fits on one screen width (slots ${s.scrollW}/${s.clientW})`);
  if (OUT) await page.screenshot({ path: `${OUT}/${TAG}_${w}_battle.png` });
  await ctx.close();
}
await browser.close();
staticServer.close();
console.log(`\n${problems} problem(s)`);
process.exit(problems ? 1 : 0);
