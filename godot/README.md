# Wordsmith's Gambit — Godot Prototype (Milestones 1-3)

A Godot 4.3 implementation of the same core concept as the browser build at
the repo root: a procedurally generated crossword grid that doubles as a
dungeon map.

* **Milestone 1** — grid generation, navigation, rendering.
* **Milestone 2** — the Word Duel: combat UI, clue input, countdown timer,
  the full damage formula, and Vocabulary Chains.
* **Milestone 3** — the Lexicon: Ink Drops, Vocabulary Trees, Tomes, a
  1-50 player level with unlocks, achievements, a daily login reward, run
  settlement, and real persistence. What you buy now changes how runs play.

## Running it

Open `godot/` as a project in Godot 4.3+, or headless:

```
godot --headless --path godot/ tests/unit/TestRunner.tscn   # unit tests + perf benchmarks
godot --headless --path godot/ tests/bots/BotRunner.tscn    # 100-run soft-lock/crash bot
godot --path godot/                                          # play it (main menu -> The Lexicon / Quick Delve)
```

Walk into an unsolved letter with the arrow keys to start a Word Duel: type
the answer before the clock runs out. A correct answer damages the enemy
(faster and first-try hits harder); a wrong one costs HP and an attempt.
Solving a word that spells a dictionary word triggers a Vocabulary Chain.

Also runnable with no Godot binary at all, against the same data files and
the same fill algorithm (kept in sync by hand — see the note at the top of
`tools/balance_simulator/gridgen_reference.py`):

```
python3 tools/balance_simulator/standalone_validator.py [trials_per_preset]
```

### A note on `--script` / `--main-loop`

`tests/unit/test_grid_generator.gd` and `tests/bots/random_bot.gd` are
`SceneTree`-based scripts, and their headers say to run them with
`godot --headless --script <path>`. Don't — in Godot 4.3, `--script` (and
`--main-loop`) replace the main loop *before* project autoloads become
resolvable as bare identifiers at compile time, so anything referencing
`ConfigLoader`, `EventBus`, etc. fails with `Identifier not found`, even
though the autoload nodes genuinely exist under `/root` at runtime by then.
`TestRunner.tscn` / `BotRunner.tscn` sidestep this with a thin Node wrapper
that `.new()`s the SceneTree class from inside a normal scene run (which
boots autoloads first, same as any real gameplay scene) — no changes to the
test/bot logic itself. Use those two scenes, not `--script`, to actually run
them.

## Architecture

### The Lexicon (Milestone 3)

The between-run hub. Everything is data-driven (`data/lexicon/*.json`, the
`progression` and `ink_economy` blocks of `game_config.json`) and every rule
is a static function over plain Dictionaries, so it is unit-testable without
a scene (CLAUDE.md 2.4: no new autoloads).

- `src/core/lexicon/InkDropManager.gd` — the Ink ledger. Two counters: the
  spendable `ink_drops` balance, and `total_ink_drops` (everything ever
  collected), which alone drives the level. Also run payouts and the daily
  login.
- `PlayerLevel.gd` — level 1-50 from lifetime Ink (`round(40 * (L-1)^1.6)`,
  tunable in config), the level-unlock list, and which grid sizes a player may
  pick.
- `VocabularyTree.gd` / `TomeManager.gd` — buying, prerequisites, slots.
- `AchievementTracker.gd` — Trophy Room conditions and one-time Ink rewards.
- `LexiconEffects.gd` — **the bridge into combat.** Folds purchased nodes and
  equipped tomes into one loadout and stamps it onto the run's `player_state`
  at run start, filling the `category_multipliers`, `tome_multipliers`,
  `timer_modifiers`, `damage_reduction` and `chain_duration_bonus` hooks that
  Milestone 2 left at 1.0 / 0.
- `RunSettlement.gd` — what a finished run does to the profile: counters,
  Ink payout, level-ups, achievements.
- `LexiconState.gd` — builds the default lexicon and repairs a loaded one.
- `src/scenes/lexicon/` — `LexiconScene` (Vocabulary / Tomes / Trophy Room /
  Delve tabs) and `RunSummaryPanel` (shown when a run ends).

Run flow: **Lexicon -> Delve -> dungeon -> run ends -> summary -> back to the
Lexicon.** Ink earned in a run (letters, chains, category bonuses) is only
banked at the end: a cleared dungeon adds a completion bonus; a lost run keeps
`ink_economy.defeat_retention` (50%) of it. Equipped tomes multiply the haul.

Where the Lexicon touches Milestone 2 code (all small, all defaulting to the
old behaviour when no Lexicon bonus is present): `CombatEngine` applies a
`combat_first_attempt` tome scope on first tries; `CombatStateMachine`
adds the per-category timer bonus when it starts the clock; `ChainEffects`
lengthens a damage buff by `chain_duration_bonus`.

Design decisions worth knowing about: [ADR-002](docs/adr/002-vocabulary-trees-follow-clue-categories.md)
(why the trees are not Science/History/Arts/Nature) and
[ADR-003](docs/adr/003-lexicon-saved-as-additive-key.md) (how the Lexicon is
saved without a schema version bump).

### Combat (Milestone 2)

- `src/core/combat/CombatStateMachine.gd` — drives one encounter through
  reveal / input / validate / damage / resolution. Synchronous and
  `RefCounted`, so tests and the playtest bot drive it headlessly without a
  SceneTree; see the note in its header for why that differs from the
  CLAUDE.md 4.2 sketch.
- `src/core/combat/CombatEngine.gd` — the damage formula from Technical
  Design Doc 3.2, every multiplier data-driven from `game_config.json`.
- `src/core/combat/ClueResolver.gd` — answer normalization and validation.
- `src/core/combat/TimerSystem.gd` — the countdown, built on Timer nodes
  rather than the spec's `_process` loop (CLAUDE.md 2.5 forbids `_process`
  for game logic, and the sketched per-frame ratio check can miss warnings
  on a frame hitch). Header explains the tradeoff.
- `src/core/combo/ChainDetector.gd` — finds runs of solved letters that
  spell dictionary words; `ChainEffects.gd` pays out the tiered rewards
  from Design Doc 4.3.
- `src/scenes/combat/CombatScene.gd` — the Word Duel UI. Presentation and
  input only; all encounter logic lives in the state machine.
- `src/utils/ClueDatabase.gd` / `EnemyDatabase.gd` — typed data-access
  wrappers (CLAUDE.md 4.3) with fallbacks, so a bad id degrades instead of
  crashing a run.

### Grid (Milestone 1)

- `src/core/grid/GridGenerator.gd` — builds one grid by growing outward from
  a seed word, greedily placing each subsequent candidate word at its
  best-scoring intersection with what's already down (the same algorithm,
  independently validated, as the browser build's `src/crossword.js`).
  Falls back to a trivial guaranteed-valid grid for any unsupported size.
  An earlier version tried solving a fixed black-cell skeleton as an exact
  constraint-satisfaction problem instead — it failed almost immediately in
  testing (a handful of short intersecting slots need mutual consistency
  that a ~100-word clue bank essentially never satisfies, the classic "word
  square" trap). See `tools/balance_simulator/` for how this was validated:
  480/480 clean generations across all six presets, and 100/100 real-engine
  bot runs (via `BotRunner.tscn`) with zero soft-locks or crashes.
- `src/core/grid/GridNavigator.gd` — player position, movement/reachability
  rules, and word-solving (revealing every cell of a word at once, not just
  the one the player is standing next to).
- `src/core/grid/GridRenderer.gd` — custom-drawn grid visualization.
- `src/core/grid/GridCell.gd` — typed cell data with Dictionary (de)serialization.
- `src/autoload/` — `ConfigLoader` (cached JSON loading), `EventBus` (global
  signals), `GameState` (current run + persistent profile), `SaveManager`
  (atomic saves, rotating backups, schema migration), `AssetRegistry`
  (cached asset loading).
- `src/utils/Constants.gd` — enums, data paths, render colors.
- `src/scenes/` — `MainMenuScene` and `DungeonScene` (the playable demo).
- `data/` — `clues/clues_master.json` (115 clues, 6 categories, lengths
  3-10), `config/grid_presets.json` (6 size/density presets),
  `config/game_config.json` (balance constants), `enemies/enemies_master.json`
  (5 enemies + 1 boss), `dictionaries/words_en.json` (16,360 words for
  chain validation).

## Known scope and deliberate gaps

Everything below is a conscious gap, not an oversight:

- **The boss fight does not exist yet.** Design Doc 4.2's loop is "fill the
  grid -> boss encounter", so The Thesaurus is a fight *after* the grid, not
  a cell in it. `grid_state.final_word_clue_ids` records which word gated
  the exit, ready for that encounter to be built.
- **Three enemies ship with `weakness: null`.** Homophone, Acronym and
  Portmanteau each have a Design Doc weakness that depends on data or a
  system that does not exist yet (homophone-tagged clues, abbreviation-style
  answers, compound-word tagging). Each carries a `weakness_pending` field
  saying exactly what it is waiting on. Encoding a guess would have meant a
  weakness that silently never fires, or one that fires on every hit.
- **The Thesaurus's synonym rule is inert** for the same reason:
  ClueResolver accepts exact matches only, so "synonyms deal 50%" has
  nothing to act on.
- **Enemy special abilities are data, not behaviour.** Every enemy has its
  ability defined with an unlock depth; nothing invokes them yet.
- **Level unlocks other than grid sizes are listed but not enforced.**
  Chain stacking (Lv 10), Hardcore mode (15), custom grid themes (25), the
  Thesaurus boss (30), daily-challenge participation (40) and the Grandmaster
  title (50) appear in the Lexicon's "Level rewards" list; only the 7x7 and
  9x9 grid sizes (Lv 5, 20) actually gate anything, because the other
  features do not exist yet. Hardcore mode's permadeath rule in particular is
  not implemented.
- **Dictionary Upgrades and the Dictionary-fragment drop are not built.**
  `ink_economy.dictionary_fragment_*` and `player_profile.dictionary_fragments`
  exist as config/state, but nothing drops or spends fragments, and the clue
  pool is never gated by an "unlocked dictionary" (the 115-clue pool is too
  small to shrink).
- **Cosmetic grid themes** are stored (`unlocked_themes`, `active_theme`) and
  survive a save, but there is nothing to buy or render yet.
- **Ink per letter is 2** (`ink_economy.ink_per_letter`), not Design Doc
  5.1's 10. A random-play bot earns about 115 Ink per run (137 per cleared
  run), which puts level 5 a few runs away and level 50 roughly 150 cleared
  runs away; at 10 per letter those figures drop sharply. It is a one-line
  config change once real play data exists.
- **A timer bonus also nudges the time-damage bonus.** The speed multiplier
  compares time left to the *base* clue time, so a node/tome that adds seconds
  makes a fast answer slightly stronger as well. Changing that would alter the
  Technical Design Doc 3.2 damage formula, so it is left as is.
- **Tome healing fires once per solved word**, not per letter: Technical
  Design Doc 2.5 words it as "after each solved letter", which would heal a
  5-letter word five times over. The data calls the trigger `combat_won`.
- **The daily login uses the device clock.** It refuses a clock set backwards
  but cannot stop a player skipping forward; fine for an offline single-player
  reward.
- **Runs are not resumable.** A run is not
  saved mid-dungeon (`current_run` is not persisted), so closing the game
  mid-run forfeits that run's Ink.
- **Chain dictionary is ~16k common words**, not the 100k+ Technical Design
  Doc 3.3 targets. A curated list avoids chains firing on obscure junk, and
  it is a superset of every clue answer (a test enforces that). Swapping in
  a bigger list is a one-file change.
