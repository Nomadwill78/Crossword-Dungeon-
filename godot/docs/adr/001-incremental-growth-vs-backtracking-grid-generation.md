# ADR-001: Incremental-growth grid generation instead of backtracking-with-templates

## Status
Accepted

## Context

The Technical Design Doc (`docs/design/technical_design_document.md`, section
3.1) specifies grid generation as: select a pre-designed black-cell template
for the target size, identify the resulting word slots, then fill those
slots with clue-database answers via backtracking with constraint
propagation — retrying with a different template if a slot has no valid
candidate.

This is the approach I built and tested first. It failed almost
immediately:

- On a fully-open 5×5 grid (10 slots, all length 5), 0/30 trials succeeded
  against a clue bank with 16 five-letter words. The solver typically died
  within ~15 search nodes.
- On a hand-tuned "easier" 5×5 pattern (8 length-3 slots + 2 length-5 slots,
  chosen specifically to reduce constraint density), it was *still* 0/15.
  Tracing the search showed the four length-3 slots meeting at a shared
  corner needed mutual letter consistency — e.g. slot A's first letter had
  to equal slot B's first letter, using a *different* word than A since
  each clue can only be used once — and with only 12 words of length 3 in
  the bank, most first-letter choices left no valid second word at all.
- The same failure reproduced across every black-cell pattern I tried
  (5×5, 7×7, 9×9, sparse and dense), including patterns explicitly
  optimized to minimize the number of long/fully-open slots.

This is the well-known "word square" problem: filling several short words
that must all agree at their intersections is dramatically harder than
filling one long word through several already-placed shorter ones, and it
gets *worse*, not better, as slot length shrinks — the opposite of what
"reduce constraint density with more black cells" assumes. It requires
either a purpose-built word-square corpus or a clue bank several orders of
magnitude larger than what exists today (the design doc's own long-term
target is 10,000+ clues; Milestone 1 shipped with 115).

## Decision

Grid generation instead grows a grid incrementally, starting from one seed
word and greedily placing each subsequent candidate word at its
best-scoring valid intersection with whatever is already placed — the same
algorithm already proven out in this project's separate browser-JS
prototype (`src/crossword.js` in the repo root, not the Godot project).
Words that don't fit anywhere yet are retried once as the grid grows, then
dropped (there's no requirement to place every candidate — the clue bank is
larger than any single grid needs). A black-cell "template" concept is
gone; instead, `data/config/grid_presets.json` gives each size a target word
count and the algorithm fills toward it inside a fixed size×size canvas,
leaving anything not covered by a placed word as a black cell.

This never needs two different words to agree at a shared cell chosen in
advance — every intersection is discovered and validated against a word
that's *already down*, one word at a time, so there's no simultaneous
multi-way constraint to fail on.

Validated before being ported to GDScript: a Python prototype of the same
algorithm ran 200+ trials per size/density preset (six presets total) at
100% success. After porting, the actual GDScript `GridGenerator.gd` was
verified against the real Godot 4.3 engine: 42/42 unit test assertions
(`tests/unit/TestRunner.tscn`) and 100/100 random-bot playthroughs
(`tests/bots/BotRunner.tscn`) with zero soft-locks or crashes, plus 480/480
clean generations via the standalone (no-Godot-required) Python validator
(`tools/balance_simulator/standalone_validator.py`).

## Consequences

**Positive:**
- Grid generation is reliable today, with a 115-clue bank, rather than
  blocked on a clue database that doesn't exist yet.
- The same algorithm is validated in two independent implementations (this
  project's JS prototype and this Godot port), reducing the chance either
  has an undiscovered edge case.
- Generation is fast (no backtracking search) and has a simple, well-tested
  fallback path for any grid size without a matching preset.

**Negative:**
- Grids are sparser than the TDD's model implies — roughly 40-90% of cells
  filled depending on size, not "every row and column is a real crossword
  word." A 5×5 grid averages ~4-5 words, not the ~10 a fully-filled 5×5
  crossword would have.
- `grid_presets.json`'s schema (`target_slots` instead of `black_cells`) no
  longer matches the TDD's example JSON in section 3.1 — anyone implementing
  from the TDD directly needs to know this ADR exists.
- If a future clue database grows large enough (and is curated for
  intersection compatibility, not just word variety) to make
  backtracking-with-templates viable, that would be a *second* documented
  algorithm change, not a return to a previously-working state — per
  CLAUDE.md 9.5, that also needs explicit human approval.

## Alternatives Considered

- **Backtracking-with-templates exactly as specified** — rejected: measured
  0% success across every configuration tried, not a marginal or
  edge-case failure.
- **Backtracking with a much larger generated word list** (e.g. every word
  in a system dictionary, not just curated clues) — not attempted for
  Milestone 1. Would fix the *supply* problem but not necessarily the
  *compatibility* problem (a large but uncurated word list is still mostly
  incompatible letter-for-letter at forced intersections); real crossword
  construction tools typically need a dictionary purpose-scored for exactly
  this. Worth revisiting if/when the clue database grows substantially and
  denser, more traditional-looking grids become a priority.
- **Keep templates but relax "one clue per answer" (allow duplicate
  words)** — not attempted; would reduce realism (repeated answers in one
  grid) and only partially addresses the corner case shown above, since the
  actual bottleneck is letter compatibility, not just supply count.
