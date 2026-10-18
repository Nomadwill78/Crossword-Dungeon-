# ADR-004: How enemy abilities, weaknesses and The Thesaurus are implemented

## Status
Accepted. Several interpretations below are mine, not the design docs'; each is
data-driven and called out so it can be changed without touching code.

## Context

Milestone 4 builds the parts of Design Doc 4.4 that were data-only: each regular
enemy's special ability, three weaknesses left `null` in Milestone 2, and the
boss fight. The docs specify them in one line each ("Reverses player input",
"Changes clue mid-fight") and, in places, describe things the game has no data
for. Two things were decided with the user before building:

- **Runs are multi-floor.** Abilities unlock at depths 3 / 6 / 10 / 15, but every
  run was a single floor at depth 1, so no ability could ever fire. A cleared
  floor now offers *Descend* (depth + 1, HP and Ink carry over, 30% heal) or
  *Cash Out* (bank the run). Dying anywhere is a loss (the existing 50% Ink
  retention applies to the whole run, which is what makes descending a gamble).
- **The boss guards the exit of every 5th floor** for a player with the Lv 30
  `thesaurus_boss` unlock (Design Doc 5.2). Facing it is the price of descending
  past that floor; cashing out first skips it. Both knobs are in
  `game_config.json` -> `boss_encounter` (`require_unlock: ""` shows it to everyone).

## Decision

### Abilities (`EnemyAbilities`, applied by `CombatStateMachine`)

| Enemy | Trigger | What it does here |
|---|---|---|
| Anagram - Letter Swap | player takes damage | swaps the *displayed* letters of 2 pairs of solved grid cells. Only the map (and so what chains can spell) changes; word slots and answers are untouched, so nothing becomes unsolvable |
| Palindrome - Mirror Input | on attempt | *armed before the player types* and announced, so the next answer is read backwards. A player who types the word backwards gets through - a fair puzzle, not a trap |
| Homophone - Mishearing | clue reveal | garbles the clue text: words are swapped for sound-alikes, then phonetic spelling rules apply (`ability_rules.json`). The answer is unchanged |
| Acronym - Abbreviate | attempt failed | halves the clock of the *next* attempt (the clock only runs while input is open, so halving "remaining" time at the moment of failure would do nothing). Does nothing in untimed fights |
| Portmanteau - Blend | clue reveal | merges a second clue with a same-length, different answer into the prompt, in random order, so only one of the two is real |

`cooldown_turns` counts *attempts against that enemy type across the run*
(`player_state.ability_cooldowns`, never saved). For a clue-reveal ability that
means "roughly every Nth encounter with that enemy"; counting per encounter would
make the cooldown meaningless, since a reveal happens once per fight.

### Weaknesses

Weaknesses are read from clue `tags` in `clues_master.json` (`compound`,
`homophone`, `abbreviation`), via new `clue_tag` / `not_clue_tag` rule types.

- **Portmanteau - compound answers**: 20 clues tagged `compound`, each checked by a
  test to really be two dictionary words joined.
- **Homophone**: the doc says "context clues", which cannot be computed. Read as
  "answers with a same-sounding twin" (RAIN / REIGN, VEIL / VALE, WITCH / WHICH,
  BOW / BOUGH, SEWER / SOWER). **This is a reinterpretation.**
- **Acronym - full-word answers**: only meaningful if some answers are *not*
  full words, so this adds a seventh clue category, `GAME_JARGON`, with six
  abbreviations (NPC, RPG, MMO, DPS, AOE, TPK) and a matching seventh vocabulary
  tree (Metagame, 3 nodes). The rule is `not_clue_tag: abbreviation`; a test
  guarantees it cannot be an always-on bonus by requiring both tagged and
  untagged clues to exist. Abbreviations are deliberately not chain words.

### The Thesaurus (`BossEncounter`)

A fight is a series of single-clue **rounds** against one shared HP pool. Each
round is an ordinary `CombatStateMachine` with `round_mode = true` (a correct
answer ends the round with the boss still standing), so timers, attempts, damage
and the player's Lexicon bonuses are the same code as any duel. Boss HP and damage
come from the data (as first built: 200 + 10/depth + 2/grid size and 20 + 3/depth;
retuned in [ADR-005](005-tuning-the-thesaurus.md), see `enemies_master.json`). The boss has
`no_counter_on_hit`: it strikes only on a miss or timeout. Without that, the
counter-attack every non-lethal hit draws would make a 260 HP boss unbeatable.

Phases start when HP falls to their `hp_threshold` (100% / 50% / 25%):

1. **synonym_swap** - after your first miss the clue is *reworded*
   (`boss_rounds.json` -> `synonym_variants`, 40 clues). The doc's "synonyms deal
   50%" half is not implemented: it would need synonym *answers*.
2. **antonym_inversion** - the prompt asks for the **opposite of** another clue's
   answer (7 pairs, both directions: HERO/FOE, ICE/FIRE, ...). A clue may be in
   only one pair, enforced by a test, because "opposite of pure delight" must not
   have two right answers.
3. **obscure_variant** - an archaic spelling is demanded (GOBELIN, SWERD, CASTEL,
   SPYDER, FYRE, FANTASM, HELME, SORCERIE). The modern spelling is still *accepted*
   but deals only the boss's `exact_match` penalty (x0.5): this is how "only exact
   matches deal full damage" is realised, via a new `alternates` field on a clue
   that `ClueResolver` and `CombatEngine` understand.

## Consequences

Positive:
- Every ability, weakness and phase is exercised in tests, in headless scene tests
  that fight a whole boss, and by the playtest bot (the four abilities that work
  untimed all fire; 20+ boss fights per 100 runs reach all three phases;
  Abbreviate needs a clock and has its own timed unit test).
- All round content is data; adding a variant, an opposite pair or an archaic
  spelling is a JSON edit.

Negative:
- The Homophone weakness and the three boss-phase mechanics are my readings of
  one-line descriptions.
- Only 7 opposite pairs and 8 archaic spellings exist, so a long boss career will
  see repeats (a fight never repeats within itself until a pool is exhausted).
- The boss was untuned when this was written: the playtest bot, which is far
  better at typing than a person, wins ~90% of fights. It has since been tuned
  against a simulated person: see [ADR-005](005-tuning-the-thesaurus.md).

## Alternatives Considered

- **Keep single-floor runs and tie abilities to player level.** Rejected by the
  user in favour of depth, which the design docs use.
- **Make the boss a plain high-HP duel on one clue.** Rejected: repeating one
  clue for ~7 rounds is not a boss fight, and the doc's three phases need
  different prompts.
- **Leave the three weaknesses null.** Rejected: that was the Milestone 2 stopgap;
  the tag approach makes them computable and testable.
- **A new boss scene.** Rejected: reusing `CombatScene` per round meant no
  duplicated UI or input handling.
