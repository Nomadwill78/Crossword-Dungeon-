# Wordsmith's Gambit — Godot Prototype (Milestone 1)

A Godot 4.3 implementation of the same core concept as the browser build at
the repo root: a procedurally generated crossword grid that doubles as a
dungeon map. This milestone covers grid generation, navigation, and
rendering, with combat auto-resolved for demonstration purposes (real
combat UI is Milestone 2).

## Running it

Open `godot/` as a project in Godot 4.3+, or headless:

```
godot --headless --path godot/ tests/unit/TestRunner.tscn   # unit tests
godot --headless --path godot/ tests/bots/BotRunner.tscn    # 100-run soft-lock/crash bot
godot --path godot/                                          # play it (main menu -> Start Demo)
```

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
  (5 enemies + 1 boss).

## Known scope

Milestone 1 only. No combat UI, meta-progression, or persistence UI yet —
see the root README's roadmap section for what's next across both builds.
