import { DungeonRun } from './dungeon.js';
import { BattleSession, LETTER_VALUES } from './combat.js';
import { LEVEL_ONE } from './wordlist.js';

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
};

let dictionary = new Set();
let themeWords = new Set(LEVEL_ONE.entries.map((e) => e.word.toUpperCase()));
let dungeon = new DungeonRun(LEVEL_ONE);
let battle = null;
let activeBattlePlacementIndex = null;

async function loadDictionary() {
  const res = await fetch('data/dictionary.json');
  const words = await res.json();
  dictionary = new Set(words);
}

function renderHud() {
  const pct = Math.round((dungeon.playerHP / dungeon.playerMaxHP) * 100);
  els.playerHpFill.style.width = `${pct}%`;
  els.playerHpText.textContent = `${dungeon.playerHP}/${dungeon.playerMaxHP}`;
  els.scoreText.textContent = dungeon.score;
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
        const k = `${r},${c}`;
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
}

function clueLabel(p) {
  const status = statusFor(p);
  if (status === 'cleared' || status === 'pending-battle') return p.word;
  return `(${p.word.length} letters)`;
}

function renderClueItem(p) {
  const status = statusFor(p);
  const item = document.createElement('div');
  item.className = `clue-item ${status}`;
  item.dataset.index = p.index;

  const head = document.createElement('div');
  head.className = 'clue-head';
  head.innerHTML = `<span>#${p.number} ${p.dir}</span><span>${clueLabel(p)}</span>`;
  item.appendChild(head);

  const text = document.createElement('div');
  text.className = 'clue-text';
  text.textContent = p.clue ?? (p.isEntrance ? 'Your starting corridor.' : '');
  item.appendChild(text);

  if (status === 'open') {
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
  els.acrossList.innerHTML = '';
  els.downList.innerHTML = '';
  for (const p of dungeon.cluesByDirection('across')) {
    els.acrossList.appendChild(renderClueItem(p));
  }
  for (const p of dungeon.cluesByDirection('down')) {
    els.downList.appendChild(renderClueItem(p));
  }
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
    remainingPlayerHP: won ? battle.playerHP : Math.round(dungeon.playerMaxHP * 0.5),
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

  els.playerHpFill.style.width = `${Math.round((battle.playerHP / battle.playerMaxHP) * 100)}%`;
  els.playerHpText.textContent = `${battle.playerHP}/${battle.playerMaxHP}`;

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

async function init() {
  await loadDictionary();
  renderMap();
}

init();
