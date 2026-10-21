import { DungeonRun, RETREAT_HP_FRACTION } from './dungeon.js';
import { BattleSession, LETTER_VALUES } from './combat.js';
import { battleFraming, strikeEffect, wordPrompt } from './battlefx.js';
import { LEVEL_ONE } from './wordlist.js';
import { HINT_LEVELS } from './hints.js';
import { HeroAvatar, avatarSvg } from './avatar.js';
import { HEROES, HERO_LIST, damageBonus, describePerk, heroById } from './heroes.js';
import { renderRulesHtml } from './rules.js';
import {
  HARDCORE, PREF_KEY as HARDCORE_PREF_KEY, describeHardcore, loadStats, recordRun, saveStats,
} from './hardcore.js';
import {
  computeStreak, dailyHero, dailyKey, dailySeed, formatCountdown, loadResults, msUntilNextDaily,
  recordResult, saveResults, shareText,
} from './daily.js';

const els = {
  grid: document.getElementById('grid'),
  acrossList: document.getElementById('across-list'),
  downList: document.getElementById('down-list'),
  mapView: document.getElementById('map-view'),
  battleView: document.getElementById('battle-view'),
  monsterName: document.getElementById('monster-name'),
  monsterIcon: document.getElementById('monster-icon'),
  battleTitle: document.getElementById('battle-title'),
  battleHint: document.getElementById('battle-hint'),
  battleHero: document.getElementById('battle-hero'),
  battleHpFill: document.getElementById('battle-hp-fill'),
  battleHpText: document.getElementById('battle-hp-text'),
  fxHero: document.getElementById('fx-hero'),
  fxFoe: document.getElementById('fx-foe'),
  battleSplash: document.getElementById('battle-splash'),
  splashTitle: document.getElementById('splash-title'),
  splashName: document.getElementById('splash-name'),
  monsterHpFill: document.getElementById('monster-hp-fill'),
  monsterHpText: document.getElementById('monster-hp-text'),
  playerHpFill: document.getElementById('player-hp-fill'),
  playerHpText: document.getElementById('player-hp-text'),
  scoreText: document.getElementById('score-text'),
  wordSlots: document.getElementById('word-slots'),
  wordFeedback: document.getElementById('word-feedback'),
  rack: document.getElementById('battle-rack'),
  submitWord: document.getElementById('submit-word'),
  clearWord: document.getElementById('clear-word'),
  comboIndicator: document.getElementById('combo-indicator'),
  battleLog: document.getElementById('battle-log'),
  overlay: document.getElementById('overlay'),
  overlayTitle: document.getElementById('overlay-title'),
  overlayText: document.getElementById('overlay-text'),
  avatar: document.getElementById('avatar'),
  helpBtn: document.getElementById('help-btn'),
  helpModal: document.getElementById('help-modal'),
  helpBody: document.getElementById('help-body'),
  helpClose: document.getElementById('help-close'),
  helpDone: document.getElementById('help-done'),
  heroBtn: document.getElementById('hero-btn'),
  heroModal: document.getElementById('hero-modal'),
  heroTitle: document.getElementById('hero-title'),
  heroNote: document.getElementById('hero-note'),
  heroList: document.getElementById('hero-list'),
  heroClose: document.getElementById('hero-close'),
  heroStart: document.getElementById('hero-start'),
  hcBadge: document.getElementById('hc-badge'),
  turnTimer: document.getElementById('turn-timer'),
  turnFill: document.getElementById('turn-fill'),
  turnSecs: document.getElementById('turn-secs'),
  hardcoreToggle: document.getElementById('hardcore-toggle'),
  hardcoreDesc: document.getElementById('hardcore-desc'),
  hardcoreStats: document.getElementById('hardcore-stats'),
  dailyBtn: document.getElementById('daily-btn'),
  tabFree: document.getElementById('tab-free'),
  tabDaily: document.getElementById('tab-daily'),
  panelFree: document.getElementById('panel-free'),
  panelDaily: document.getElementById('panel-daily'),
  dailyBody: document.getElementById('daily-body'),
  resultModal: document.getElementById('result-modal'),
  resultBody: document.getElementById('result-body'),
  resultShare: document.getElementById('result-share'),
  resultCopy: document.getElementById('result-copy'),
  resultAgain: document.getElementById('result-again'),
  resultClose: document.getElementById('result-close'),
  toast: document.getElementById('toast'),
};

let dictionary = new Set();
let themeWords = new Set(LEVEL_ONE.entries.map((e) => e.word.toUpperCase()));

const HERO_KEY = 'wordsmith-hero';

function savedHeroId() {
  try { return localStorage.getItem(HERO_KEY); } catch { return null; }
}

// Saved daily results. Reading `localStorage` can throw (private browsing), so
// it is only touched inside daily.js's try/catch; a mirror in memory keeps the
// session consistent even when nothing can be saved.
const storage = {
  getItem: (key) => localStorage.getItem(key),
  setItem: (key, value) => localStorage.setItem(key, value),
};
let dailyResults = loadResults(storage);
let hardcoreStats = loadStats(storage);
/** Whether the last free run was hardcore (the picker's toggle remembers it). */
let hardcorePref = false;
try { hardcorePref = localStorage.getItem(HARDCORE_PREF_KEY) === '1'; } catch { /* no storage */ }

/** Pick up anything saved by another tab, without losing what is only in memory. */
function refreshDailyResults() {
  dailyResults = { ...loadResults(storage), ...dailyResults };
  return dailyResults;
}

/** The hero for this run. In free play, the one chosen last time (or the
 * default); in the Daily Challenge, whoever the day assigns. */
let hero = heroById(savedHeroId());
/** The player's own pick, kept apart from the daily hero so a daily run never
 * overwrites it. */
let freeHero = hero;
/** Set during a Daily Challenge run: { key, official }. null in free play. */
let daily = null;
/** True once this run's win has been announced (and, for a daily, recorded). */
let victoryShown = false;
let dungeon = new DungeonRun(LEVEL_ONE, hero, { hardcore: hardcorePref });
let battle = null;
let activeBattlePlacementIndex = null;

const avatar = new HeroAvatar(els.avatar, hero);
/** The same hero, larger, facing the monster on the battle screen. */
const battleAvatar = new HeroAvatar(els.battleHero, hero);
/** The corridor whose clue is selected; its word glows on the grid. */
let activeIndex = null;
/** Corridors whose Hints panel is open (the panel is rebuilt on every render). */
const hintOpen = new Set();
/** Cell a Level 2 hint just filled in, so the next render can flash it. */
let lastRevealedKey = null;
let toastTimer = null;

const prefersReducedMotion = () =>
  window.matchMedia('(prefers-reduced-motion: reduce)').matches;

async function loadDictionary() {
  const res = await fetch('data/dictionary.json');
  const words = await res.json();
  dictionary = new Set(words);
}

/** Single place the HP bar, its number and the hero portrait are updated, so
 * they can never disagree (the map and the battle both go through here). */
function setHp(hp, maxHp) {
  els.playerHpFill.style.width = `${Math.round((hp / maxHp) * 100)}%`;
  els.playerHpText.textContent = `${hp}/${maxHp}`;
  avatar.update(hp, maxHp);
  els.battleHpFill.style.width = `${Math.round((hp / maxHp) * 100)}%`;
  els.battleHpText.textContent = `${hp}/${maxHp}`;
  battleAvatar.update(hp, maxHp);
  els.heroBtn.setAttribute('aria-label', `${els.avatar.getAttribute('aria-label')}. Change hero`);
}

function renderHud() {
  els.hcBadge.hidden = !dungeon.hardcore;
  setHp(dungeon.playerHP, dungeon.playerMaxHP);
  els.scoreText.textContent = dungeon.score;
}

function showToast(text) {
  els.toast.textContent = text;
  els.toast.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => els.toast.classList.remove('show'), 2600);
}

function statusFor(p) {
  if (!dungeon.isReachable(p.index)) return 'locked';
  if (!dungeon.isSolved(p.index)) return 'open';
  if (p.monster && !dungeon.isCleared(p.index)) return 'pending-battle';
  return 'cleared';
}

function renderGrid() {
  els.grid.innerHTML = '';
  // Cell size comes from CSS: the grid fills the available width (capped at the
  // desktop cell size), so only the column count is needed here.
  els.grid.style.setProperty('--cols', dungeon.width);
  els.grid.style.setProperty('--rows', dungeon.height);

  const monsterCellKeys = new Set();
  const clearedCellKeys = new Set();
  for (const p of dungeon.placements) {
    if (!p.monster) continue;
    for (const [r, c] of p.cells) {
      monsterCellKeys.add(`${r},${c}`);
      if (dungeon.isCleared(p.index)) clearedCellKeys.add(`${r},${c}`);
    }
  }

  for (let r = 0; r < dungeon.height; r++) {
    for (let c = 0; c < dungeon.width; c++) {
      const cellData = dungeon.grid[r][c];
      const div = document.createElement('div');
      div.className = 'cell';
      if (cellData) {
        div.classList.add('filled');
        div.dataset.r = r;
        div.dataset.c = c;
        const k = `${r},${c}`;
        if (k === lastRevealedKey) div.classList.add('just-revealed');
        if (cellData.revealed) {
          div.classList.add('revealed');
          div.textContent = cellData.letter;
        }
        if (monsterCellKeys.has(k)) {
          div.classList.add('monster-cell');
          if (clearedCellKeys.has(k)) div.classList.add('cleared');
        }
        if (cellData.number) {
          const num = document.createElement('span');
          num.className = 'cell-number';
          num.textContent = cellData.number;
          div.appendChild(num);
        }
      }
      els.grid.appendChild(div);
    }
  }
  lastRevealedKey = null;
  applyHighlight();
}

// ---- selecting a word -------------------------------------------------

function cellElement(r, c) {
  return els.grid.children[r * dungeon.width + c];
}

/** Corridors that pass through a cell (an across word and/or a down word). */
function ownersOf(r, c) {
  return dungeon.placements
    .filter((p) => p.cells.some(([pr, pc]) => pr === r && pc === c))
    .map((p) => p.index);
}

/** Glow the active word on the grid and mark its clue card. */
function applyHighlight() {
  for (const el of els.grid.querySelectorAll('.cell.hl')) el.classList.remove('hl');
  for (const el of document.querySelectorAll('.clue-item.active')) el.classList.remove('active');
  if (activeIndex === null) return;
  for (const [r, c] of dungeon.placement(activeIndex).cells) {
    cellElement(r, c)?.classList.add('hl');
  }
  document.querySelector(`.clue-item[data-index="${activeIndex}"]`)?.classList.add('active');
}

/** Scroll the page just enough that the whole rectangle is on screen. */
function scrollRectIntoView(rect) {
  const margin = 12;
  let delta = 0;
  if (rect.top < margin) delta = rect.top - margin;
  else if (rect.bottom > window.innerHeight - margin) delta = rect.bottom - window.innerHeight + margin;
  if (delta !== 0) {
    window.scrollBy({ top: delta, behavior: prefersReducedMotion() ? 'auto' : 'smooth' });
  }
}

function scrollWordIntoView(index) {
  const rects = dungeon
    .placement(index)
    .cells.map(([r, c]) => cellElement(r, c)?.getBoundingClientRect())
    .filter(Boolean);
  if (!rects.length) return;
  scrollRectIntoView({
    top: Math.min(...rects.map((r) => r.top)),
    bottom: Math.max(...rects.map((r) => r.bottom)),
  });
}

/**
 * Make [index] the active word. `scrollGrid` brings its cells into view (used
 * when a clue card is tapped); `scrollCard` brings its card into view (used
 * when a grid cell is tapped).
 */
function selectClue(index, { scrollGrid = false, scrollCard = false } = {}) {
  activeIndex = index;
  applyHighlight();
  if (scrollGrid) scrollWordIntoView(index);
  if (scrollCard) {
    document.querySelector(`.clue-item[data-index="${index}"]`)?.scrollIntoView({
      block: 'nearest',
      behavior: prefersReducedMotion() ? 'auto' : 'smooth',
    });
  }
}

els.grid.addEventListener('click', (event) => {
  const cell = event.target.closest('.cell.filled');
  if (!cell) return;
  const owners = ownersOf(Number(cell.dataset.r), Number(cell.dataset.c));
  if (!owners.length) return;
  // Tapping a crossing cell again cycles between its across and down words.
  const next = owners[(owners.indexOf(activeIndex) + 1) % owners.length];
  selectClue(next, { scrollCard: true });
});

function clueLabel(p) {
  const status = statusFor(p);
  if (status === 'cleared' || status === 'pending-battle') return p.word;
  return `(${p.word.length} letters)`;
}

function renderClueItem(p) {
  const status = statusFor(p);
  const item = document.createElement('div');
  item.className = `clue-item ${status}${p.index === activeIndex ? ' active' : ''}`;
  item.dataset.index = p.index;

  // Tapping a card lights its word up on the grid. Tapping the answer box or a
  // button must not scroll the page away from what the player is doing.
  item.addEventListener('click', (event) => {
    selectClue(p.index, { scrollGrid: !event.target.closest('input, button, summary, .hint-row') });
  });
  item.addEventListener('focusin', () => selectClue(p.index));

  const head = document.createElement('div');
  head.className = 'clue-head';
  head.innerHTML = `<span>#${p.number} ${p.dir}</span><span>${clueLabel(p)}</span>`;
  item.appendChild(head);

  const text = document.createElement('div');
  text.className = 'clue-text';
  text.textContent = p.clue ?? (p.isEntrance ? 'Your starting corridor.' : '');
  item.appendChild(text);

  if (dungeon.fallen) item.classList.add('dead');

  if (status === 'open' && !dungeon.fallen) {
    appendHintReadout(item, p);

    const form = document.createElement('form');
    const input = document.createElement('input');
    input.type = 'text';
    input.maxLength = p.word.length;
    input.autocomplete = 'off';
    input.placeholder = 'answer...';
    const btn = document.createElement('button');
    btn.type = 'submit';
    btn.textContent = 'Solve';
    form.appendChild(input);
    form.appendChild(btn);
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      handleAttempt(p.index, input.value, item);
    });
    item.appendChild(form);
    if (dungeon.hardcore) item.appendChild(hardcoreNote(p.index));
    item.appendChild(renderHintPanel(p));
  } else if (status === 'pending-battle' && !dungeon.fallen) {
    const btn = document.createElement('button');
    btn.className = 'danger';
    btn.textContent = `Fight ${p.monster.name}`;
    btn.addEventListener('click', () => startBattle(p.index));
    item.appendChild(btn);
  }

  return item;
}

function renderClues() {
  // Rebuilding the cards must not throw away answers the player is typing.
  const typed = new Map();
  for (const input of document.querySelectorAll('.clue-item input[type="text"]')) {
    if (input.value) typed.set(input.closest('.clue-item').dataset.index, input.value);
  }

  els.acrossList.innerHTML = '';
  els.downList.innerHTML = '';
  for (const p of dungeon.cluesByDirection('across')) {
    els.acrossList.appendChild(renderClueItem(p));
  }
  for (const p of dungeon.cluesByDirection('down')) {
    els.downList.appendChild(renderClueItem(p));
  }

  for (const [index, value] of typed) {
    const input = document.querySelector(`.clue-item[data-index="${index}"] input[type="text"]`);
    if (input) input.value = value;
  }
}

// ---- hints -------------------------------------------------------------

/** The letters the player knows so far, and any lore hint they bought. */
function appendHintReadout(item, p) {
  const state = dungeon.hintState.get(p.index);
  if (!state) return;

  if (state.vowels) {
    const pattern = document.createElement('div');
    pattern.className = 'hint-pattern';
    const known = dungeon.hintPattern(p.index);
    pattern.setAttribute('role', 'img');
    pattern.setAttribute('aria-label', `Known letters: ${known.map((ch) => ch ?? 'blank').join(' ')}`);
    for (const ch of known) {
      const cell = document.createElement('span');
      cell.className = 'pat-cell';
      cell.textContent = ch ?? '';
      pattern.appendChild(cell);
    }
    item.appendChild(pattern);
  }

  if (state.lore && p.lore) {
    const lore = document.createElement('div');
    lore.className = 'hint-lore';
    lore.textContent = p.lore;
    item.appendChild(lore);
  }
}

function payButton(currency, option, index) {
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = `pay-btn ${currency}`;
  const amount = option.cost[currency];
  const label = currency === 'score' ? 'Score' : 'HP';
  btn.textContent = `${amount} ${label}`;
  const affordable = currency === 'score' ? option.canPayScore : option.canPayHP;
  btn.disabled = option.status !== 'available' || !affordable;
  btn.setAttribute('aria-label', `${option.name}: pay ${amount} ${label}`);
  if (option.status === 'available' && !affordable) {
    btn.title = currency === 'score' ? 'Not enough Score' : 'You cannot spend your last HP';
  }
  btn.addEventListener('click', () => handleHint(index, option.level, currency));
  return btn;
}

/** One button for a level the hero's perk made free. */
function freeButton(option, index) {
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'pay-btn free';
  btn.textContent = 'Free';
  btn.disabled = option.status !== 'available';
  btn.setAttribute('aria-label', `${option.name}: free (${hero.perk.name})`);
  btn.title = hero.perk.name;
  btn.addEventListener('click', () => handleHint(index, option.level, 'score'));
  return btn;
}

function renderHintPanel(p) {
  const details = document.createElement('details');
  details.className = 'hints';
  details.open = hintOpen.has(p.index);
  details.addEventListener('toggle', () => {
    if (details.open) hintOpen.add(p.index);
    else hintOpen.delete(p.index);
  });

  const summary = document.createElement('summary');
  summary.textContent = 'Stuck? Hints';
  details.appendChild(summary);

  for (const option of dungeon.hintOptions(p.index)) {
    const row = document.createElement('div');
    row.className = 'hint-row';
    row.dataset.level = option.level;

    const info = document.createElement('div');
    info.className = 'hint-info';
    info.innerHTML = '<strong></strong><span></span>';
    info.querySelector('strong').textContent = `${option.level}. ${option.name}`;
    info.querySelector('span').textContent = option.blurb;
    row.appendChild(info);

    const pay = document.createElement('div');
    pay.className = 'hint-pay';
    if (option.status === 'done') {
      const done = document.createElement('span');
      done.className = 'hint-state';
      done.textContent = 'Used';
      pay.appendChild(done);
    } else if (option.free) {
      pay.appendChild(freeButton(option, p.index));
    } else {
      pay.appendChild(payButton('score', option, p.index));
      pay.appendChild(payButton('hp', option, p.index));
    }
    if (option.status === 'locked') {
      const note = document.createElement('span');
      note.className = 'hint-state';
      note.textContent = `Needs hint ${option.level - 1}`;
      pay.prepend(note);
    }
    row.appendChild(pay);
    details.appendChild(row);
  }
  return details;
}

function handleHint(index, level, currency) {
  const result = dungeon.buyHint(index, level, currency);
  if (!result.ok) {
    showToast(
      result.reason === 'cannot_afford' ? 'You cannot afford that hint.' : 'That hint is not available.'
    );
    return;
  }

  hintOpen.add(index);
  activeIndex = index;
  if (level === 2) {
    const [r, c] = dungeon.placement(index).cells[result.letterIndex];
    lastRevealedKey = `${r},${c}`;
  }
  renderMap();

  const name = dungeon.hintOptions(index).find((o) => o.level === level).name;
  showToast(
    result.paid.amount === 0
      ? `${name}: free`
      : `${name}: -${result.paid.amount} ${result.paid.currency === 'score' ? 'Score' : 'HP'}`
  );

  // Rebuilding the card dropped keyboard focus; put it back where it was.
  const row = document.querySelector(`.clue-item[data-index="${index}"] .hint-row[data-level="${level}"]`);
  (row?.querySelector('.pay-btn:not(:disabled)') ??
    document.querySelector(`.clue-item[data-index="${index}"] summary`))?.focus({ preventScroll: true });
}

function renderMap() {
  renderGrid();
  renderClues();
  renderHud();
}

/** The line under a clue's answer box in hardcore: what a wrong answer costs. */
function hardcoreNoteText(index) {
  const left = dungeon.retriesLeft(index);
  return left > 0
    ? `${left} free ${left === 1 ? 'retry' : 'retries'} left on this clue`
    : `Wrong answers on this clue cost ${HARDCORE.wrongGuessHp} HP`;
}

function hardcoreNote(index) {
  const note = document.createElement('p');
  note.className = `hc-note${dungeon.retriesLeft(index) > 0 ? '' : ' costly'}`;
  note.textContent = hardcoreNoteText(index);
  return note;
}

function handleAttempt(index, guess, itemEl) {
  if (dungeon.fallen) return;
  const result = dungeon.attemptSolve(index, guess);
  if (!result.correct) {
    itemEl.classList.remove('shake');
    void itemEl.offsetWidth;
    itemEl.classList.add('shake');
    if (dungeon.hardcore) {
      const note = itemEl.querySelector('.hc-note');
      if (note) {
        note.textContent = hardcoreNoteText(index);
        note.classList.toggle('costly', dungeon.retriesLeft(index) === 0);
      }
      if (result.penalty > 0) {
        renderHud();
        showToast(`Wrong answer: -${result.penalty} HP`);
      } else if (result.freeRetry) {
        showToast('Wrong answer. That was your free retry.');
      }
    }
    return;
  }
  renderMap();
  if (result.outcome === 'battle') {
    startBattle(index);
  } else {
    checkVictory();
  }
}

function startBattle(index) {
  const p = dungeon.placements[index];
  activeBattlePlacementIndex = index;
  battle = new BattleSession(
    p.monster, dictionary, themeWords, dungeon.playerHP, dungeon.playerMaxHP, undefined,
    { damageBonus: damageBonus(dungeon.hero) },
    dungeon.battleRng(index)
  );
  els.mapView.hidden = true;
  els.battleView.hidden = false;
  window.scrollTo(0, 0);
  introduceBattle(battle.monster);
  renderBattle();
  startTurnClock();
}

let splashTimer = null;

/**
 * Tell the player this is a fight, not another puzzle: the banner and hint, the
 * monster's portrait, and a brief BATTLE! splash. The splash does not catch taps
 * and does not hold the hardcore clock, so it never costs the player anything.
 */
function introduceBattle(monster) {
  const framing = battleFraming(monster);
  els.battleView.classList.toggle('boss', framing.boss);
  els.battleTitle.textContent = framing.title;
  els.battleHint.textContent = framing.hint;
  els.monsterIcon.textContent = framing.icon;
  els.monsterIcon.classList.remove('struck', 'defeated');
  els.fxFoe.innerHTML = '';
  els.fxHero.innerHTML = '';
  els.splashTitle.textContent = framing.title;
  els.splashName.textContent = framing.splashName;
  clearTimeout(splashTimer);
  els.battleSplash.hidden = true;
  void els.battleSplash.offsetWidth; // restart the animation
  els.battleSplash.hidden = false;
  splashTimer = setTimeout(() => { els.battleSplash.hidden = true; }, 1300);
}

/** Float the result of a cast over whoever it happened to. */
function playStrike(result) {
  const effect = strikeEffect(result);
  if (!effect) return;
  const layer = effect.side === 'foe' ? els.fxFoe : els.fxHero;
  const el = document.createElement('div');
  el.className = `strike ${effect.kind}`;
  el.innerHTML = `<span class="label"></span><span class="amount"></span>`;
  el.querySelector('.label').textContent = effect.label;
  el.querySelector('.amount').textContent = effect.amount;
  layer.appendChild(el);
  setTimeout(() => el.remove(), 1100);
  if (effect.side === 'foe') {
    els.monsterIcon.classList.remove('struck');
    void els.monsterIcon.offsetWidth;
    els.monsterIcon.classList.add('struck');
  }
}

// ---- the hardcore battle clock -----------------------------------------------

let turnClock = null; // { remainingMs, last, timer } while a hardcore word is on the clock

/** The clock stands still while the player reads a card, or is away. */
const turnPaused = () => document.hidden || openModalEl !== null || !els.overlay.hidden;

function renderTurnClock() {
  const seconds = HARDCORE.turnSeconds;
  const left = Math.max(0, turnClock.remainingMs) / 1000;
  els.turnFill.style.width = `${Math.round((left / seconds) * 100)}%`;
  els.turnSecs.textContent = Math.ceil(left);
  els.turnTimer.classList.toggle('low', left <= 5);
}

/** Give the player a fresh clock for the next word (hardcore battles only). */
function startTurnClock() {
  stopTurnClock();
  if (!dungeon.hardcore || !battle || battle.over) return;
  turnClock = {
    remainingMs: HARDCORE.turnSeconds * 1000,
    last: performance.now(),
    timer: setInterval(tickTurnClock, 100),
  };
  els.turnTimer.hidden = false;
  els.turnTimer.classList.remove('paused');
  renderTurnClock();
}

function stopTurnClock() {
  if (turnClock) clearInterval(turnClock.timer);
  turnClock = null;
  els.turnTimer.hidden = true;
}

function tickTurnClock() {
  if (!turnClock || !battle || battle.over) return;
  const now = performance.now();
  // A phone that suspended the page must not come back to an instant timeout.
  const elapsed = Math.min(now - turnClock.last, 500);
  turnClock.last = now;
  const paused = turnPaused();
  els.turnTimer.classList.toggle('paused', paused);
  if (paused) return;
  turnClock.remainingMs -= elapsed;
  if (turnClock.remainingMs <= 0) {
    const result = battle.timeOut();
    showToast('Out of time!');
    finishCast(result);
    return;
  }
  renderTurnClock();
}

/** What follows a cast (or a timeout): redraw, then either end the battle or restart the clock. */
function finishCast(result) {
  renderBattle();
  playStrike(result);
  if (battle.won) els.monsterIcon.classList.add('defeated');
  if (!battle.over) {
    startTurnClock();
    return;
  }
  stopTurnClock();
  const finished = battle;
  setTimeout(() => {
    // The player may have started a new run in the meantime.
    if (battle !== finished) return;
    const cleared = dungeon.monsterPlacements().filter((m) => dungeon.isCleared(m.index)).length;
    const total = dungeon.monsterPlacements().length;
    showOverlay(
      finished.won ? 'Victory!' : dungeon.hardcore ? 'You have fallen!' : 'Retreat!',
      finished.won
        ? `${finished.monster.name} is defeated. The corridor is clear.`
        : dungeon.hardcore
          ? `${finished.monster.name} ends your run. ${cleared} of ${total} monster corridors cleared.`
          : `You barely escape ${finished.monster.name}. Patch up and try again.`,
      () => endBattle()
    );
  }, 300);
}

function recordHardcoreRun(won) {
  hardcoreStats = recordRun(hardcoreStats, { won, score: dungeon.finalScore() });
  if (!saveStats(storage, hardcoreStats)) showToast("Couldn't save your hardcore record on this device.");
}

function endBattle() {
  stopTurnClock();
  const won = battle.won;
  dungeon.markBattleResolved(activeBattlePlacementIndex, {
    won,
    remainingPlayerHP: won ? battle.playerHP : Math.round(dungeon.playerMaxHP * RETREAT_HP_FRACTION),
    scoreGained: battle.scoreGained,
  });
  battle = null;
  activeBattlePlacementIndex = null;
  els.battleView.hidden = true;
  els.mapView.hidden = false;
  window.scrollTo(0, 0);
  renderMap();
  if (dungeon.fallen) {
    // Hardcore: no retreat. The run is over.
    recordHardcoreRun(false);
    openHeroPicker({ dismissable: true, title: 'Play again?' });
    return;
  }
  if (won) checkVictory();
}

function renderBattle() {
  els.monsterName.textContent = battle.monster.name;
  const monsterPct = Math.round((battle.monster.hp / battle.monster.maxHp) * 100);
  els.monsterHpFill.style.width = `${monsterPct}%`;
  els.monsterHpText.textContent = `${battle.monster.hp}/${battle.monster.maxHp}`;

  setHp(battle.playerHP, battle.playerMaxHP);

  els.wordSlots.innerHTML = '';
  for (const id of battle.selected) {
    const tile = battle.rack.find((t) => t.id === id);
    if (!tile) continue;
    const div = document.createElement('div');
    div.className = 'slot-tile';
    div.textContent = tile.letter;
    div.addEventListener('click', () => {
      battle.deselectTile(id);
      renderBattle();
    });
    els.wordSlots.appendChild(div);
  }
  els.wordFeedback.textContent = wordPrompt(battle.currentWord(), battle.monster.name);

  els.rack.innerHTML = '';
  for (const tile of battle.availableTiles()) {
    const div = document.createElement('div');
    div.className = 'rack-tile';
    div.innerHTML = `<span>${tile.letter}</span><span class="tile-value">${LETTER_VALUES[tile.letter]}</span>`;
    div.addEventListener('click', () => {
      battle.selectTile(tile.id);
      renderBattle();
    });
    els.rack.appendChild(div);
  }

  els.comboIndicator.textContent = battle.comboStreak > 0 ? `Combo x${battle.comboStreak}` : '';

  els.battleLog.innerHTML = '';
  for (const line of battle.log.slice(0, 6)) {
    const div = document.createElement('div');
    div.textContent = line;
    els.battleLog.appendChild(div);
  }
}

els.submitWord.addEventListener('click', () => {
  if (!battle || battle.over) return;
  const result = battle.submit();
  finishCast(result);
});

els.clearWord.addEventListener('click', () => {
  if (!battle) return;
  battle.clearSelection();
  renderBattle();
});

let overlayHandler = null;

function showOverlay(title, text, onClose) {
  dismissOverlay();
  els.overlayTitle.textContent = title;
  els.overlayText.textContent = text;
  els.overlay.hidden = false;
  overlayHandler = () => {
    dismissOverlay();
    if (onClose) onClose();
  };
  els.overlay.addEventListener('click', overlayHandler, { once: true });
}

/** Hide the overlay without running its onClose (a new run cancels it). */
function dismissOverlay() {
  if (overlayHandler) els.overlay.removeEventListener('click', overlayHandler);
  overlayHandler = null;
  els.overlay.hidden = true;
}

function checkVictory() {
  if (!dungeon.isVictory() || victoryShown) return;
  victoryShown = true;
  const title = 'The Lexicon Crypt is Cleared!';
  const text = dungeon.hardcore
    ? `Hardcore! Score ${dungeon.score} \u00d7${HARDCORE.scoreMultiplier} = ${dungeon.finalScore()}. Every monster corridor has been silenced.`
    : `Final score: ${dungeon.score}. Every monster corridor has been silenced.`;
  if (dungeon.hardcore) recordHardcoreRun(true);
  if (daily) {
    // Recorded now, not when the overlay is dismissed, so closing the tab can't lose it.
    const outcome = finishDaily();
    showOverlay(title, text, () => openResult(outcome));
  } else {
    showOverlay(title, text, () => openHeroPicker({ dismissable: true, title: 'Play again?' }));
  }
}

// ---- modals ------------------------------------------------------------

// One dialog is open at a time. Esc closes it if it can be dismissed, Tab stays
// inside it, the page behind does not scroll, and focus returns when it closes.
let openModalEl = null;
let modalDismiss = null;
let modalReturnFocus = null;

function openModal(modal, { focus, dismiss = null }) {
  modalReturnFocus = document.activeElement;
  openModalEl = modal;
  modalDismiss = dismiss;
  modal.hidden = false;
  document.body.classList.add('modal-open');
  focus?.focus();
}

function closeModal() {
  if (!openModalEl) return;
  openModalEl.hidden = true;
  openModalEl = null;
  modalDismiss = null;
  document.body.classList.remove('modal-open');
  modalReturnFocus?.focus?.({ preventScroll: true });
}

/** What Tab can reach inside a dialog, in order (one stop per radio group). */
function tabStops(modal) {
  return [...modal.querySelectorAll('button, input')].filter((el) => {
    if (el.disabled || el.closest('[hidden]') || el.tabIndex < 0) return false;
    if (el.type !== 'radio') return true;
    const group = [...modal.querySelectorAll(`input[type="radio"][name="${el.name}"]`)];
    return el === (group.find((r) => r.checked) ?? group[0]);
  });
}

document.addEventListener('keydown', (event) => {
  if (!openModalEl) return;
  if (event.key === 'Escape') {
    modalDismiss?.();
  } else if (event.key === 'Tab') {
    const stops = tabStops(openModalEl);
    const [first, last] = [stops[0], stops[stops.length - 1]];
    if (!openModalEl.contains(document.activeElement)) {
      // Focus drifted out (e.g. a tap on the backdrop): bring it back in.
      event.preventDefault();
      (event.shiftKey ? last : first).focus();
    } else if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }
});

for (const modal of [els.helpModal, els.heroModal, els.resultModal]) {
  modal.addEventListener('click', (event) => {
    if (event.target === modal) modalDismiss?.();
  });
}

// ---- how to play -------------------------------------------------------

const HELP_SEEN_KEY = 'wordsmith-help-seen';

function rewardAmount(type) {
  return dungeon.placements.find((p) => p.reward?.type === type)?.reward.amount ?? null;
}

function openHelp() {
  els.helpBody.innerHTML = renderRulesHtml({
    maxHp: dungeon.playerMaxHP,
    retreatHp: Math.round(dungeon.playerMaxHP * RETREAT_HP_FRACTION),
    monsterCount: dungeon.monsterPlacements().length,
    healAmount: rewardAmount('heal'),
    goldAmount: rewardAmount('score'),
    hintLevels: HINT_LEVELS,
    hero: { name: hero.name, perkName: hero.perk.name, perkText: describePerk(hero) },
    hardcore: { active: dungeon.hardcore, rules: HARDCORE },
  });
  els.helpBtn.classList.remove('attention');
  try { localStorage.setItem(HELP_SEEN_KEY, '1'); } catch { /* private mode: fine */ }
  openModal(els.helpModal, { focus: els.helpClose, dismiss: closeModal });
}

els.helpBtn.addEventListener('click', openHelp);
els.helpClose.addEventListener('click', closeModal);
els.helpDone.addEventListener('click', closeModal);

// First visit: gently pulse the ? so new players notice it.
try {
  if (!localStorage.getItem(HELP_SEEN_KEY)) els.helpBtn.classList.add('attention');
} catch { /* no storage: skip the nudge */ }

// ---- heroes and new runs -----------------------------------------------

function renderHeroList(selectedId) {
  els.heroList.innerHTML = '';
  for (const h of HERO_LIST) {
    const label = document.createElement('label');
    label.className = 'hero-option';

    const radio = document.createElement('input');
    radio.type = 'radio';
    radio.name = 'hero';
    radio.value = h.id;
    radio.checked = h.id === selectedId;
    label.appendChild(radio);

    const card = document.createElement('div');
    card.className = 'hero-card';

    const portrait = document.createElement('div');
    portrait.className = 'avatar hero-portrait';
    portrait.dataset.hero = h.id;
    portrait.dataset.state = 'confident';
    portrait.setAttribute('aria-hidden', 'true');
    portrait.innerHTML = avatarSvg('confident', h.id);
    card.appendChild(portrait);

    for (const [cls, text] of [
      ['hero-name', h.name],
      ['hero-tagline', h.tagline],
      ['hero-perk-name', h.perk.name],
      ['hero-perk', describePerk(h)],
    ]) {
      const line = document.createElement('span');
      line.className = cls;
      line.textContent = text;
      card.appendChild(line);
    }
    label.appendChild(card);
    els.heroList.appendChild(label);
  }
}

/** True if starting over would throw something away. */
function runHasProgress() {
  if (dungeon.isVictory() || dungeon.fallen) return false;
  return battle !== null || dungeon.solved.size > 1 || dungeon.score !== 0 || dungeon.hintsUsed > 0;
}

let activeTab = 'free';

/** Show the Free play or Daily challenge half of the picker. */
function selectTab(name) {
  activeTab = name;
  const isDaily = name === 'daily';
  for (const [tab, panel, on] of [
    [els.tabFree, els.panelFree, !isDaily],
    [els.tabDaily, els.panelDaily, isDaily],
  ]) {
    tab.setAttribute('aria-selected', String(on));
    tab.tabIndex = on ? 0 : -1;
    panel.hidden = !on;
  }
  if (isDaily) renderDailyPanel();
  updateStartButton();
}

function updateStartButton() {
  const progress = runHasProgress();
  if (activeTab === 'daily') {
    const done = !!refreshDailyResults()[dailyKey(new Date())];
    els.heroStart.textContent = done ? 'Practice (not recorded)' : "Play today's challenge";
  } else {
    const hard = els.hardcoreToggle.checked ? ' hardcore' : '';
    els.heroStart.textContent = progress ? `Start new${hard} run` : `Begin${hard} run`;
  }
}

function renderHardcoreToggle() {
  els.hardcoreToggle.checked = hardcorePref;
  els.hardcoreDesc.textContent = describeHardcore(HARDCORE).join(' ');
  const { wins, falls, best } = hardcoreStats;
  els.hardcoreStats.textContent = wins + falls === 0
    ? 'No hardcore runs yet.'
    : `Record: ${wins} ${wins === 1 ? 'win' : 'wins'} \u00b7 ${falls} ${falls === 1 ? 'fall' : 'falls'}${wins ? ` \u00b7 best ${best}` : ''}`;
}

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function describeResult(r) {
  return `${r.score} Score \u00b7 ${r.retreats} ${r.retreats === 1 ? 'retreat' : 'retreats'} \u00b7 ${r.hintsUsed} ${r.hintsUsed === 1 ? 'hint' : 'hints'}`;
}

/** The day the Daily tab is currently showing (it can go stale if left open past midnight UTC). */
let shownDailyKey = null;

function renderDailyPanel() {
  const now = new Date();
  const key = dailyKey(now);
  shownDailyKey = key;
  const todaysHero = dailyHero(key);
  const results = refreshDailyResults();
  const record = results[key];
  const streak = computeStreak(results, key);

  const date = element('p', 'daily-date');
  date.append("Today's dungeon \u00b7 ", element('strong', '', key), ' (UTC)');

  const card = element('div', 'daily-hero');
  const portrait = element('div', 'avatar hero-portrait');
  portrait.dataset.hero = todaysHero.id;
  portrait.dataset.state = 'confident';
  portrait.setAttribute('aria-hidden', 'true');
  portrait.innerHTML = avatarSvg('confident', todaysHero.id);
  card.append(
    portrait,
    element('span', 'hero-name', `Today's hero: ${todaysHero.name}`),
    element('span', 'hero-perk-name', todaysHero.perk.name),
    element('span', 'hero-perk', describePerk(todaysHero))
  );

  const status = element('p', `daily-status${record ? ' done' : ''}`);
  status.textContent = record
    ? `Done today: ${describeResult(record)}. Replays are practice and are not recorded.`
    : 'Same dungeon, hero and starting letters for everyone. Your first finished run today counts.';

  const meta = element('div', 'daily-meta');
  const streakText = element('span');
  streakText.append('Streak ', element('strong', '', `${streak} ${streak === 1 ? 'day' : 'days'}`));
  meta.append(streakText, element('span', '', `Next dungeon in ${formatCountdown(msUntilNextDaily(now))}`));

  els.dailyBody.replaceChildren(date, card, status, meta);
}

function openHeroPicker({ dismissable, title = 'New run', tab = 'free' }) {
  const progress = runHasProgress();
  els.heroTitle.textContent = title;
  els.heroNote.hidden = !progress;
  els.heroNote.textContent = 'Starting a new run will end your current one. Your progress will be lost.';
  els.heroClose.hidden = !dismissable;
  renderHeroList(freeHero.id);
  renderHardcoreToggle();
  selectTab(tab);
  openModal(els.heroModal, {
    focus: tab === 'daily' ? els.heroStart : els.heroList.querySelector('input:checked'),
    dismiss: dismissable ? closeModal : null,
  });
}

/** Throw the current run away and begin a fresh one as [chosen]. A Daily
 * Challenge run is `{ key, official }`: seeded by the date, and recorded if no
 * run has been recorded for that day yet. */
function startRun(chosen, dailyRun = null, hardcore = false) {
  dismissOverlay();
  stopTurnClock();
  hero = chosen;
  daily = dailyRun;
  victoryShown = false;
  if (!daily) {
    freeHero = hero;
    hardcorePref = hardcore;
    try {
      localStorage.setItem(HERO_KEY, hero.id);
      localStorage.setItem(HARDCORE_PREF_KEY, hardcore ? '1' : '0');
    } catch { /* private mode: fine */ }
  }

  // The Daily Challenge is always the standard run, the same for everyone.
  dungeon = new DungeonRun(LEVEL_ONE, hero, daily ? { seed: dailySeed(daily.key) } : { hardcore });
  battle = null;
  activeBattlePlacementIndex = null;
  activeIndex = null;
  hintOpen.clear();
  lastRevealedKey = null;

  // renderClues keeps whatever is typed in the old cards; there are none now.
  els.acrossList.innerHTML = '';
  els.downList.innerHTML = '';
  els.battleView.hidden = true;
  els.mapView.hidden = false;
  avatar.setHero(hero);
  battleAvatar.setHero(hero);
  window.scrollTo(0, 0);
  renderMap();
  updateDailyButton();
}

function startDaily() {
  const key = shownDailyKey ?? dailyKey(new Date());
  startRun(dailyHero(key), { key, official: !refreshDailyResults()[key] });
}

// ---- the daily result -----------------------------------------------------

/** Record a finished daily run (first one of the day counts). */
function finishDaily() {
  const { key } = daily;
  const result = {
    score: dungeon.score, retreats: dungeon.retreats, hintsUsed: dungeon.hintsUsed, hero: hero.id,
  };
  const outcome = recordResult(refreshDailyResults(), key, result);
  dailyResults = outcome.results;
  if (outcome.official && !saveResults(storage, dailyResults)) {
    showToast("Couldn't save your result on this device.");
  }
  updateDailyButton();
  return { key, result, official: outcome.official };
}

function openResult({ key, result, official }) {
  const record = dailyResults[key] ?? result;
  const recordHero = heroById(record.hero);
  const streak = computeStreak(dailyResults, dailyKey(new Date()));

  els.resultBody.replaceChildren();
  els.resultBody.append(
    element('p', `daily-status${official ? ' done' : ''}`,
      official
        ? `Recorded as your result for ${key}.`
        : `Practice run: your recorded result for ${key} stands.`)
  );
  const meta = element('div', 'daily-meta');
  meta.append(element('span', '', `This run: ${describeResult(result)}`));
  els.resultBody.append(meta);
  if (!official) {
    const recorded = element('div', 'daily-meta');
    recorded.append(element('span', '', `Recorded: ${describeResult(record)}`));
    els.resultBody.append(recorded);
  }
  const streakLine = element('div', 'daily-meta');
  streakLine.append(
    element('span', '', `Streak: ${streak} ${streak === 1 ? 'day' : 'days'}`),
    element('span', '', `Next dungeon in ${formatCountdown(msUntilNextDaily(new Date()))}`)
  );
  els.resultBody.append(streakLine);

  els.resultShare.textContent = shareText({
    key,
    hero: recordHero,
    result: record,
    streak,
    url: `${location.origin}${location.pathname}`,
  });
  openModal(els.resultModal, { focus: els.resultCopy, dismiss: closeModal });
}

async function copyResult() {
  const text = els.resultShare.textContent;
  try {
    await navigator.clipboard.writeText(text);
    showToast('Result copied.');
  } catch {
    // No clipboard access (insecure page, denied): select it so Ctrl/Cmd+C works.
    const range = document.createRange();
    range.selectNodeContents(els.resultShare);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    showToast('Press Ctrl+C (or Cmd+C) to copy.');
  }
}

/** Mark the Daily button: a dot while today's dungeon is unplayed, filled while in a daily. */
function updateDailyButton() {
  const key = dailyKey(new Date());
  const button = els.dailyBtn;
  button.classList.remove('todo', 'active', 'practice');
  if (daily) {
    button.classList.add(daily.official ? 'active' : 'practice');
    button.textContent = daily.official ? 'Daily' : 'Practice';
    button.setAttribute('aria-label', `${daily.official ? 'Daily challenge' : 'Daily challenge practice'} for ${daily.key} in progress. Open the menu`);
  } else {
    const todo = !refreshDailyResults()[key];
    if (todo) button.classList.add('todo');
    button.textContent = 'Daily';
    button.setAttribute('aria-label', todo ? "Daily challenge: today's dungeon is waiting" : 'Daily challenge');
  }
}

els.heroBtn.addEventListener('click', () => openHeroPicker({ dismissable: true }));
els.dailyBtn.addEventListener('click', () => openHeroPicker({ dismissable: true, tab: 'daily' }));
els.heroClose.addEventListener('click', closeModal);
els.heroStart.addEventListener('click', () => {
  if (activeTab === 'daily' && dailyKey(new Date()) !== shownDailyKey) {
    // The panel was left open across midnight UTC: what it shows (date, hero,
    // result) is yesterday's. Show the new day and let the player decide,
    // rather than silently starting a dungeon other than the one displayed.
    renderDailyPanel();
    updateStartButton();
    showToast('A new daily dungeon is ready. Check the details, then start.');
    return;
  }
  const asDaily = activeTab === 'daily';
  const chosen = heroById(els.heroList.querySelector('input:checked')?.value);
  closeModal();
  if (asDaily) startDaily();
  else startRun(chosen, null, els.hardcoreToggle.checked);
});
els.hardcoreToggle.addEventListener('change', updateStartButton);

// Tabs: click, or Left/Right to switch like a native tab list.
for (const [tab, name] of [[els.tabFree, 'free'], [els.tabDaily, 'daily']]) {
  tab.addEventListener('click', () => selectTab(name));
  tab.addEventListener('keydown', (event) => {
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
    event.preventDefault();
    const other = name === 'free' ? els.tabDaily : els.tabFree;
    selectTab(name === 'free' ? 'daily' : 'free');
    other.focus();
  });
}

els.resultCopy.addEventListener('click', copyResult);
els.resultClose.addEventListener('click', closeModal);
els.resultAgain.addEventListener('click', () => {
  closeModal();
  openHeroPicker({ dismissable: true });
});
// Back from another tab or a long break: the day may have turned over.
window.addEventListener('focus', updateDailyButton);

async function init() {
  await loadDictionary();
  renderMap();
  updateDailyButton();
  // A returning player goes straight in as their last hero; a new one chooses.
  const saved = savedHeroId();
  if (!saved || !Object.hasOwn(HEROES, saved)) openHeroPicker({ dismissable: false });
}

init();
