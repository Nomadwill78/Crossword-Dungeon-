# Wordsmith's Gambit — Godot Prototype (Milestones 1-4)

A Godot 4.3 implementation of the same core concept as the browser build at
the repo root: a procedurally generated crossword grid that doubles as a
dungeon map.

* **Milestone 1** — grid generation, navigation, rendering.
* **Milestone 2** — the Word Duel: combat UI, clue input, countdown timer,
  the full damage formula, and Vocabulary Chains.
* **Milestone 3** — the Lexicon: Ink Drops, Vocabulary Trees, Tomes, a
  1-50 player level with unlocks, achievements, a daily login reward, run
  settlement, and real persistence. What you buy now changes how runs play.
* **Milestone 4** — multi-floor runs (descend deeper or cash out), enemy
  special abilities that unlock by depth, tag-based enemy weaknesses, and The
  Thesaurus, a three-phase boss that guards every 5th floor.

## Running it

Open `godot/` as a project in Godot 4.3+, or headless:

```
godot --headless --path godot/ tests/unit/TestRunner.tscn   # unit tests + perf benchmarks
godot --headless --path godot/ tests/bots/BotRunner.tscn    # 100-run soft-lock/crash bot
godot --headless --path godot/ tests/bots/BossBalanceRunner.tscn   # boss win rates by player skill (add -- --sensitivity, --grid=9)
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

### Floors, abilities and the boss (Milestone 4)

Design decisions and the places this departs from the design docs are in
[ADR-004](docs/adr/004-enemy-abilities-and-the-thesaurus.md); how the boss was
tuned, and how to retune it, is in
[ADR-005](docs/adr/005-tuning-the-thesaurus.md).

- **Floors.** A run is a ladder. Clearing a grid opens a *Floor cleared* panel:
  **Descend** (depth + 1, a fresh grid, HP and Ink carry over, +30% max HP heal)
  or **Cash Out** (bank the run). Enemy HP and damage scale with depth and their
  abilities wake at depths 3 / 6 / 10 / 15. Dying anywhere is a loss.
- **Abilities** (`src/core/combat/EnemyAbilities.gd`, applied by
  `CombatStateMachine`): Anagram swaps solved letters on the map, Palindrome
  reads your next answer backwards (it warns you first), Homophone garbles the
  clue, Acronym halves your next attempt's clock, Portmanteau merges in a decoy
  clue. Cooldowns are counted in attempts against that enemy type.
- **Weaknesses** now exist for every enemy, read from clue `tags` (`compound`,
  `homophone`, `abbreviation`) in `clues_master.json`. A seventh clue category,
  `GAME_JARGON`, holds the abbreviations the Acronym needs.
- **The Thesaurus** (`src/core/combat/BossEncounter.gd`) guards the exit of
  every 5th floor for a player with the Lv 30 unlock (`game_config.json` ->
  `boss_encounter`). It is a series of single-clue rounds against one HP pool,
  each an ordinary state machine in `round_mode`, in three phases: the clue is
  reworded after a miss; the prompt asks for the *opposite* of a clue; an
  archaic spelling is demanded (the modern one still counts, at half damage).
  It only strikes on a miss. Beating it pays Ink and earns *Thesaurus Slayer*.
- **Content** lives in `data/enemies/boss_rounds.json` (rewordings, opposite
  pairs, archaic spellings) and `ability_rules.json` (sound-alikes and phonetic
  rules).
- **UI**: `CombatScene` shows ability notices, the boss's phase banner and
  changed prompts; `FloorPanel` is the descend / cash-out / face-the-boss choice.

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
- `data/` — `clues/clues_master.json` (121 clues, 7 categories, lengths
  3-10), `config/grid_presets.json` (6 size/density presets),
  `config/game_config.json` (balance constants), `enemies/enemies_master.json`
  (5 enemies + 1 boss), `dictionaries/words_en.json` (16,360 words for
  chain validation).

## Known scope and deliberate gaps

Everything below is a conscious gap, not an oversight:

- **The Thesaurus is tuned against a simulated person, not real players.**
  `tests/bots/BossBalance.gd` plays the real fight with a model of a human
  (answer speed against the real clock, recall, typos, the harder opposite-of
  phase) and `tests/unit/test_boss_balance.gd` holds the boss to win-rate bands
  per skill level, at the smallest and the largest grid: for a geared Lv 30 player
  the first boss is close to a coin-flip for an average player (40-44%) and a fair
  test for a strong one (85%), and deeper bosses are harder but gently (depth 15:
  22-24% / 72-73%). The playtest bot still wins
  90-100% because it is untimed and near-perfect, which is why it is not the
  yardstick. The model's assumptions are guesses (answer speed above all: 30%
  slower answers cut the average player's win rate from 44% to 11%), so replace
  them with real playtest figures in `tests/bots/boss_balance.json` as soon as
  they exist; the boss's four numbers are in `enemies_master.json`. See ADR-005.
- **The Thesaurus's synonym rule is only half there.** Phase 1 rewords the clue
  but does not accept synonym *answers* ("synonyms deal 50%" would need synonym
  data); the 50% rule is realised through the phase-3 archaic/modern spelling
  instead.
- **Boss content is small.** 40 rewordings, 7 opposite pairs and 8 archaic
  spellings: a fight never repeats within itself until a pool runs out, but a
  long career will see repeats.
- **The Homophone's weakness is a reading, not the doc's.** Design Doc 4.4 says
  "context clues", which is not computable; it is weak to answers with a
  sound-alike (RAIN / REIGN) instead.
- **Abbreviate only works in timed fights**, so tests and the playtest bot (which
  are untimed) skip it; a unit test covers it with a real timer.
- **Depth is not saved mid-run** (like everything else about a run), and the
  Delve tab cannot start you below depth 1.
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
  pool is never gated by an "unlocked dictionary" (the 121-clue pool is too
  small to shrink).
- **Cosmetic grid themes** are stored (`unlocked_themes`, `active_theme`) and
  survive a save, but there is nothing to buy or render yet.
- **Ink per letter is 2** (`ink_economy.ink_per_letter`), not Design Doc
  5.1's 10. The playtest bot (a better typist than a person, and it climbs
  several floors) is paid about 250 Ink per run, which puts level 5 a couple of
  runs away and level 50 (20,000 lifetime Ink) roughly 80 runs away; a casual
  player earns far less. At 10 per letter those figures drop sharply. It is a
  one-line config change once real play data exists.
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
