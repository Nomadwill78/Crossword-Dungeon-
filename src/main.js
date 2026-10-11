import { DungeonRun, RETREAT_HP_FRACTION } from './dungeon.js';
import { BattleSession, LETTER_VALUES } from './combat.js';
import { LEVEL_ONE } from './wordlist.js';
import { HINT_LEVELS } from './hints.js';
import { HeroAvatar } from './avatar.js';
import { renderRulesHtml } from './rules.js';

const els = {
  grid: document.getElementById('grid'),
  acrossList: document.getElementById('across-list'),
  downList: document.getElementById('down-list'),
  mapView: document.getElementById('map-view'),
  battleView: document.getElementById('battle-view'),
  monsterName: document.getElementById('monster-name'),
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
  toast: document.getElementById('toast'),
};

let dictionary = new Set();
let themeWords = new Set(LEVEL_ONE.entries.map((e) => e.word.toUpperCase()));
let dungeon = new DungeonRun(LEVEL_ONE);
let battle = null;
let activeBattlePlacementIndex = null;

const avatar = new HeroAvatar(els.avatar);
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
}

function renderHud() {
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

  if (status === 'open') {
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
    item.appendChild(renderHintPanel(p));
  } else if (status === 'pending-battle') {
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
  showToast(`${name}: -${result.paid.amount} ${result.paid.currency === 'score' ? 'Score' : 'HP'}`);

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

function handleAttempt(index, guess, itemEl) {
  const result = dungeon.attemptSolve(index, guess);
  if (!result.correct) {
    itemEl.classList.remove('shake');
    void itemEl.offsetWidth;
    itemEl.classList.add('shake');
    return;
  }
  renderMap();
  if (result.outcome === 'battle') {
    startBattle(index);
  } else if (result.outcome === 'reward') {
    checkVictory();
  } else {
    checkVictory();
  }
}

function startBattle(index) {
  const p = dungeon.placements[index];
  activeBattlePlacementIndex = index;
  battle = new BattleSession(p.monster, dictionary, themeWords, dungeon.playerHP, dungeon.playerMaxHP);
  els.mapView.hidden = true;
  els.battleView.hidden = false;
  window.scrollTo(0, 0);
  renderBattle();
}

function endBattle() {
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
  els.wordFeedback.textContent = battle.currentWord()
    ? `${battle.currentWord()} (${battle.currentWord().length} letters)`
    : 'Select letters to build a word';

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
  battle.submit();
  if (battle.over) {
    renderBattle();
    setTimeout(() => {
      showOverlay(
        battle.won ? 'Victory!' : 'Retreat!',
        battle.won
          ? `${battle.monster.name} is defeated. The corridor is clear.`
          : `You barely escape ${battle.monster.name}. Patch up and try again.`,
        () => endBattle()
      );
    }, 300);
    return;
  }
  renderBattle();
});

els.clearWord.addEventListener('click', () => {
  if (!battle) return;
  battle.clearSelection();
  renderBattle();
});

function showOverlay(title, text, onClose) {
  els.overlayTitle.textContent = title;
  els.overlayText.textContent = text;
  els.overlay.hidden = false;
  const close = () => {
    els.overlay.hidden = true;
    els.overlay.removeEventListener('click', close);
    if (onClose) onClose();
  };
  els.overlay.addEventListener('click', close, { once: true });
}

function checkVictory() {
  if (dungeon.isVictory()) {
    showOverlay(
      'The Lexicon Crypt is Cleared!',
      `Final score: ${dungeon.score}. Every monster corridor has been silenced.`
    );
  }
}

// ---- how to play -------------------------------------------------------

const HELP_SEEN_KEY = 'wordsmith-help-seen';
let helpReturnFocus = null;

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
  });
  helpReturnFocus = document.activeElement;
  els.helpModal.hidden = false;
  document.body.classList.add('modal-open');
  els.helpBtn.classList.remove('attention');
  try { localStorage.setItem(HELP_SEEN_KEY, '1'); } catch { /* private mode: fine */ }
  els.helpClose.focus();
}

function closeHelp() {
  if (els.helpModal.hidden) return;
  els.helpModal.hidden = true;
  document.body.classList.remove('modal-open');
  helpReturnFocus?.focus?.();
}

els.helpBtn.addEventListener('click', openHelp);
els.helpClose.addEventListener('click', closeHelp);
els.helpDone.addEventListener('click', closeHelp);
els.helpModal.addEventListener('click', (event) => {
  if (event.target === els.helpModal) closeHelp();
});
document.addEventListener('keydown', (event) => {
  if (els.helpModal.hidden) return;
  if (event.key === 'Escape') {
    closeHelp();
  } else if (event.key === 'Tab') {
    // Two focusable controls: keep Tab inside the dialog.
    const [first, last] = [els.helpClose, els.helpDone];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }
});

// First visit: gently pulse the ? so new players notice it.
try {
  if (!localStorage.getItem(HELP_SEEN_KEY)) els.helpBtn.classList.add('attention');
} catch { /* no storage: skip the nudge */ }

async function init() {
  await loadDictionary();
  renderMap();
}

init();
