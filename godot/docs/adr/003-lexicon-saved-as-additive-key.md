# ADR-003: The Lexicon is persisted as an additive save key, not a new schema version

## Status
Accepted

## Context

Milestone 3 must persist vocabulary-tree purchases, owned/equipped tomes,
achievements, and a few new profile fields (`ink_drops`, `player_level`, login
streak). Until now `SaveManager` saved only `player_profile`, `settings` and
`statistics`, at `schema_version` 1. Also until now, **nothing ever called
`save_game()` or `load_game()`** - Milestones 1-2 had no persistent state worth
keeping.

CLAUDE.md 9.5 forbids changing the save file format version without explicit
human approval.

## Decision

Keep `schema_version` at **1** and add the new data as an **additive**
top-level `lexicon` key, plus new keys inside `player_profile` and
`statistics`. Make loading tolerant instead of version-gated:

- `SaveManager.merge_with_defaults` lays the loaded data over pristine
  defaults (`GameState.default_profile()` etc.), so any key that did not exist
  when the save was written is defaulted rather than missing. It also coerces
  numbers to the default's int/float type, because JSON hands back every
  number as a float.
- `LexiconState.normalize` is the single gate for the lexicon: it drops ids
  that no longer exist in the data files, removes duplicates, requires an
  equipped tome to be an owned one, resizes the slot list to the configured
  count, and recomputes `total_invested` and `nodes_unlocked` from what is
  genuinely owned.
- `_repair_progression` clamps the Ink balance to lifetime Ink and raises (never
  lowers) the level to match lifetime Ink.
- `SaveManager._ready` now calls `load_game()`, and the Lexicon and run end
  save immediately after every purchase / settlement.

A save written by Milestone 1-2 therefore loads cleanly (covered by
`TestSaveManager._test_old_save_gets_defaults`), and a save written by this
build still loads in the older one - it simply ignores the extra key.

## Consequences

Positive:
- No format version bump, so no approval needed and no migration to maintain.
- Self-healing: removing a tome or node in a later content patch cannot strand
  a player with an unresolvable id.

Negative:
- A *real* breaking change later still needs `_migrate` and a version bump;
  this decision only covers additive growth.
- `SaveManager.save_path` / `backup_dir` became public variables so tests can
  redirect writes away from the player's real save.

## Alternatives Considered

- **Bump to `schema_version` 2 with a migration.** Rejected for now: forbidden
  without approval, and unnecessary - nothing in the old format needs
  rewriting, only supplementing.
- **A separate `lexicon.json` file.** Rejected: two files can be restored from
  different backups and disagree (balance in one, purchases in the other).
  One atomic file keeps the profile and the Lexicon consistent.
