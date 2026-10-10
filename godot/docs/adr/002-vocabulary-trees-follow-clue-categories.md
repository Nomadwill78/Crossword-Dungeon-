# ADR-002: Vocabulary Trees follow the game's clue categories

## Status
Accepted (reversible by editing one JSON file - see Consequences)

## Context

Design Doc 4.5 names four Vocabulary Trees - **Science, History, Arts,
Nature** - and Technical Design Doc 2.4 shows a `science` tree whose nodes
boost answers where `"category": "science"`.

The clue database that actually ships (`data/clues/clues_master.json`, 115
clues) uses six different categories: `FANTASY_CREATURES`, `MAGIC_ARCANE`,
`WEAPONS_ARMOR`, `DUNGEON_PLACES`, `NATURE_ELEMENTS` and `EMOTIONS_ABSTRACT`.
There is no science, history or arts clue. A Science tree would therefore
grant a "+10% damage for science answers" bonus that can never trigger - a
purchasable node that does nothing, which is the worst kind of dead content.
Only Nature has a counterpart (`NATURE_ELEMENTS`).

The two documents are describing different content sets; the design docs were
written before the clue categories existed.

## Decision

Ship **one tree per real clue category** (six trees, 20 nodes in total, which
matches Design Doc 5.3's "20 vocabulary nodes" launch target), each keeping
the *kind* of bonus the design doc gave its tree:

| Design doc idea | Where it lives now |
|---|---|
| Science: +damage for category answers | every tree's first node (`damage_multiplier`) |
| History: +timer for category clues | Bestiary, Arcana, Armory, Sentiment (`timer_bonus`) |
| Arts: +chain duration | Arcana's *Lingering Spell* (`chain_duration`); Sentiment's *Resonance* (`chain_bonus`) |
| Nature: +healing from category words | Wilds' *Wild Remedy*, Cartography's *Safe Passage* (`heal_on_solve`) |

Plus two effect types the design doc did not mention but the trees needed to
be worth buying: `ink_bonus` and `damage_reduction`.

Each tree carries a `category` field. `TestLexiconData` fails the build if a
tree targets a category that does not exist in `Constants.CATEGORIES`, if two
trees share a category, or if a category has no tree - so this mapping cannot
silently rot as clues are added.

## Update (Milestone 4)

Milestone 4 added a seventh clue category, `GAME_JARGON` (abbreviations such as NPC
and RPG, needed for the Acronym's weakness - see ADR-004), so there is now a
seventh tree, **Metagame**, with 3 nodes: 7 trees and 23 nodes in total. The
"one tree per category" tests picked it up automatically; the node-count check
was loosened from exactly 20 to at least 20.

## Consequences

Positive:
- Every node does something the player can see in the next run.
- When real Science/History/Arts clues are added, a tree for them is a JSON
  edit (new tree object, new `category`) and no code change. The effect
  types are already general.

Negative:
- Departs from the names in the design docs. The player-facing text in the
  design docs still says Science/History/Arts/Nature; that is a documentation
  gap, not a behavioural one.

## Alternatives Considered

- **Ship the four documented trees as written.** Rejected: three of four
  would be inert (see Context).
- **Ship the four documented trees and map them onto the existing
  categories** (e.g. Science -> `MAGIC_ARCANE`). Rejected: the names would
  mislead - a "Science" node boosting wizard-spell clues - and break the
  moment real science clues exist.
- **Stop and wait for science/history/arts clues.** Rejected: that is a
  content milestone, and it would block the whole Lexicon on writing clues.
