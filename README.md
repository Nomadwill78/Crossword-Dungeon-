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
- A battle is framed as a fight so it does not read as another puzzle: a
  BATTLE! (or BOSS BATTLE!) banner that says how you attack, your hero
  facing the monster's portrait with a VS between them and both HP bars, a
  brief splash as it opens, and a floating "-7" over whoever was hit after
  every cast. The wording lives in `src/battlefx.js` (unit tested).
- In battle, click letter tiles to build a word and hit "Cast Word." A valid
  dictionary word (3+ letters) damages the monster — longer words and
  consecutive hits (combo streak) hit harder, and casting one of the
  dungeon's own theme words ("VOCABULARY COMBO") doubles the damage. An
  invalid word wastes the turn and the monster hits back.
- Losing a battle sends you back to the map at half HP; the monster isn't
  cleared, so you can walk back in and try again once you've healed up.
- Clearing every monster corridor wins the run.
- The **?** next to the HP bar opens a how-to-play card (HP, Score, winning,
  hints). It is generated from the game's real constants (`src/rules.js`), so
  it cannot drift out of date, and pulses once for first-time visitors.
- Pick a hero before each run (the picker opens on your first visit; tap the
  portrait beside the HP bar to start a new run as someone else). Each has one
  passive perk, defined as plain numbers in `src/heroes.js` so the game, the
  picker and the How-to-play card always agree:
  - **The Scribe**: Show vowels hints are free on every clue.
  - **The Warden**: +10 max HP.
  - **The Duelist**: +20% damage on every word.

  Your last hero is remembered. To add one: give it an entry in `HEROES` and
  `HERO_LIST`, a palette in `main.css` (`[data-hero="..."]`) and its gear in
  `GEAR` in `src/avatar.js`.
- **Hardcore mode** (a checkbox in the Free play tab of the new-run picker; your
  choice is remembered): a harsher way to play free runs, with its numbers in
  one place (`src/hardcore.js`) so the game, the picker and the rules card agree.
  - **No retreat**: at 0 HP the run is over.
  - **A 15-second clock** on every word you cast in battle; when it runs out the
    turn is wasted and the monster hits you. It pauses while a dialog is open or
    the tab is hidden.
  - **One free retry per clue**: after that each wrong answer costs 2 HP, but
    never your last HP (so a typo cannot end the run).
  - **Final Score x1.5**, and your hardcore wins, falls and best Score are kept
    on this device.

  Hardcore also has its own daily (see **Daily Hardcore** below). The Godot
  design doc gates hardcore behind player level 15; this build has no player
  levels, so it is available from the start.
- **Daily Challenge** (the Daily button in the header, or the Daily tab in the
  new-run picker): one dungeon a day, the same for everyone. The day is the UTC
  date and it fixes the grid layout, the hero, and every dice roll (battle
  letters, monster hits, hint letters), all drawn from a seeded generator
  (`src/rng.js`, `src/daily.js`). Your first finished run each day is recorded
  on this device with its Score, retreats and hints used, and extends your
  streak. Replays are practice and do not count. The result card has a
  copy-to-clipboard share text. There is no server, so there is no global
  leaderboard; results are compared by sharing them (online boards are planned,
  see below).
- **Daily Hardcore** (the Hardcore switch on the Daily tab): a second daily with
  its **own dungeon and hero** each day (seeded with a different salt, so it is
  a different puzzle from the standard daily, not the same one made harder),
  played under the hardcore rules above. It has its own once-a-day result, kept
  apart from the standard one: the first finished run counts, and a fall counts
  as finished as much as a win does. It has its own streak, its own share text
  ("Daily Hardcore ... Cleared / Fell"), and does not touch your free-play
  hardcore record.
- The hero portrait beside the HP bar reacts to health: confident, wary,
  battered, then defeated at 0 HP (`src/avatar.js`).
- Stuck on a clue? Open **Stuck? Hints** on its card. Pay in Score or HP
  (HP never drops below 1, Score never below 0). Levels unlock in order:
  1. *Show vowels* (10 Score / 1 HP)
  2. *Reveal a letter* (50 Score / 2 HP), repeatable, never gives away the last letter
  3. *Lore hint* (25 Score / 2 HP), an extra, simpler clue

  Costs live in `src/hints.js`. Hints never solve a word for you.
- Tapping a clue card scrolls to and glows its word on the grid; tapping a
  grid cell does the reverse (tap a crossing cell again to switch between
  across and down).

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
- `src/battlefx.js` — the battle screen's banner, hint and floating strike text.
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

## Tests

```
node --test "tests/web/*.test.mjs"      # hints, heroes, avatar, rules, seeding, daily, hardcore (no dependencies)
node tools/ui_feature_check.mjs [dir]   # Playwright: ? modal, hero picker, portrait, hints, highlighting,
                                        # and full daily and hardcore playthroughs (PROFILE=0 for one viewport)
```

`tools/ui_feature_check.mjs` plays the game at desktop, phone and small-phone
sizes, including whole runs to victory (`tools/lib/autoplay.mjs` solves every
clue and wins each battle with the best word on the rack).

**Changing the daily:** the pinned values in `tests/web/rng.test.mjs` and
`tests/web/seeded.test.mjs` (the hash, the generator, and one day's layout)
exist so nobody changes everyone's puzzle by accident. Editing the word list,
the generator or the seed derivation changes every day's dungeon (both dailies);
update those pins on purpose when you do. The two dailies' salts live in
`src/daily.js` and must never change once players have results saved under them. Set `PLAYWRIGHT_MODULE` / `CHROMIUM_PATH` if Playwright or Chromium
are not installed in the usual place.

## Known scope / next steps

This is a single-level prototype proving out the map-is-a-crossword and
word-combat mechanics. Not yet built: multiple dungeon levels/runs,
persistent meta-progression, deck/spell unlocks, audio, and any
storefront/purchase integration (this repo is just the game client).

Online daily and weekly leaderboards, with free guest play and email
registration, are designed but not built: see
[docs/online-leaderboards.md](docs/online-leaderboards.md).
