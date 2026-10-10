# Wordsmith's Gambit

A puzzle-RPG hybrid where every run's crossword grid **is** the dungeon map.
Answer clues to unlock corridors, fight word-themed monsters by building real
words from a letter rack, and chain vocabulary for bonus damage.

This repo is a playable browser prototype of the core loop: crossword-as-map
generation, corridor unlocking, and word-building combat. It's vanilla
JS/HTML/CSS with no build step and no external runtime dependencies.

There's also a parallel Godot 4.3 build in [`godot/`](godot/) — an
independent implementation of the same core mechanic (grid generation,
navigation, rendering), with its own README, data, and tests.

## Run it

Any static file server works (ES modules need `http://`, not `file://`):

```
python3 -m http.server 8080
# or: npx serve .
```

Then open `http://localhost:8080/`.

## How it plays

- The crossword grid on the left is the dungeon. Every entry in the word list
  (`src/wordlist.js`) becomes one corridor — an across or down word.
- Solving a corridor's clue (in the Across/Down panel) reveals its letters.
  A corridor can only be attempted once it's adjacent to an already-solved
  one, starting from the auto-unlocked entrance (`QUEST`).
- Corridors with a `monster` drop you into a battle when solved. Corridors
  with a `reward` (heal / score / bonus) pay out immediately instead.
- In battle, click letter tiles to build a word and hit "Cast Word." A valid
  dictionary word (3+ letters) damages the monster — longer words and
  consecutive hits (combo streak) hit harder, and casting one of the
  dungeon's own theme words ("VOCABULARY COMBO") doubles the damage. An
  invalid word wastes the turn and the monster hits back.
- Losing a battle sends you back to the map at half HP; the monster isn't
  cleared, so you can walk back in and try again once you've healed up.
- Clearing every monster corridor wins the run.

## Architecture

- `src/crossword.js` — the generator. Places the longest word first, then
  greedily interlocks the rest through shared letters (classic
  crossword-construction algorithm), with retries and a guaranteed
  "secret passage" fallback so no word is ever unplaceable. Runs several
  randomized attempts and keeps the most interlocked result.
- `src/wordlist.js` — level content: theme words, clues, monster stats,
  and treasure-room rewards for "The Lexicon Crypt."
- `src/dungeon.js` (`DungeonRun`) — turns the generated grid into a
  corridor-adjacency graph, tracks solved/cleared state, and enforces
  reachability so the map can't soft-lock.
- `src/combat.js` (`BattleSession`) — the letter rack, Scrabble-style
  letter values and bag distribution (with a standing guarantee of at
  least two vowels in the rack, even after mid-battle refills), word
  validation, and damage/combo scoring.
- `src/main.js` — DOM rendering and event wiring between the three
  modules above; no framework.
- `data/dictionary.json` — ~16k common English words used to validate
  combat words, built from a public dictionary word list intersected
  with a frequency list (to skip obscure entries) and filtered against a
  profanity blocklist.

## Mobile

The page is responsive: the 16-column grid scales to the screen width (capped
at the original 32px cells on desktop), the header and battle controls wrap,
the clue list becomes part of the normal page scroll on narrow screens, and
touch devices get 44px tap targets and 16px answer text (so iOS Safari does not
zoom when you focus an answer box).

`tools/mobile_layout_check.mjs` plays the game headlessly at phone, tablet and
desktop sizes and fails on horizontal overflow, an unreachable grid, undersized
touch targets, or a word overflowing the battle view:

```
npm i -D playwright            # once, plus a Chromium (npx playwright install chromium)
node tools/mobile_layout_check.mjs [screenshot-dir]
```

## Known scope / next steps

This is a single-level prototype proving out the map-is-a-crossword and
word-combat mechanics. Not yet built: multiple dungeon levels/runs,
persistent meta-progression, deck/spell unlocks, audio, and any
storefront/purchase integration (this repo is just the game client).
