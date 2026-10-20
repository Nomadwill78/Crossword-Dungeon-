# ADR-006: A clock bonus for The Thesaurus's rounds

## Status
Accepted. It rests on the same simulated person as ADR-005, so it is only as
good as that model. It supersedes ADR-005's boss numbers (the method, targets and
retune procedure there still stand).

## Context

ADR-005 ended with one finding it could not fix: how fast people really answer is
the biggest unknown in the boss tuning, and the win rate moves a lot with it. If
real players answer 30% slower than modelled, the average geared player's depth-5
win rate falls from 44% to 11% and the depth-15 one to 3%. A boss whose difficulty
depends that much on a guess is a bad bet.

The boss's rounds also ask more than a plain clue does: phase 2 wants the
opposite of a clue's answer and phase 3 an archaic spelling. They get the same
clock as any other clue.

## Decision

### 1. The mechanism: `round_timer_bonus` (data, on the enemy)

An enemy may carry `round_timer_bonus`, seconds added to the clock of each of its
rounds. `CombatStateMachine._timer_modifiers()` adds it to the player's own
`timer_bonus` and any vocabulary-node bonus for the clue's category, so it stacks
with them, and the accessibility extended-timer multiplier still applies on top.
No other enemy sets it, so nothing else changes.

The speed bonus in the damage formula is `time_remaining / base_timer`, and
`base_timer` is the clue's standard clock, so extra seconds also make a fast answer
hit a little harder (a +10 s clock on a 30 s clue turns 1.42x into up to 1.58x for an
answer after 5 s). That is how every other timer bonus in the game (the Tome of
Patience, the vocabulary nodes) already works, and I did not change the damage formula
(CLAUDE.md 9.5). The simulation runs the real formula, so the effect is in the
numbers below.

### 2. The yardstick had to change

The simulation modelled a player's pace as a share of whatever clock they were
given. That makes extra seconds useless by construction: a player with a longer
clock simply answers more slowly. People answer in real seconds. The model now
measures pace against the clue's standard clock (`TimerSystem.base_seconds_for_difficulty`),
so a bonus is slack, not a reason to dawdle. With no bonus the numbers are
identical to ADR-005's, which is how the change was checked.

`BossBalanceRunner` takes `--bonus=N` and `--hp-offset=N` to try a boss tuning
without editing data.

### 3. The tuning

| | Before (ADR-005) | After |
|---|---|---|
| `round_timer_bonus` | none | 10 s |
| `base_hp` | 201 | 256 |
| `scaling.hp_per_depth` | 8 | 11 |
| `base_damage` / `damage_per_depth` | 30 / 0 | 30 / 0 |

On a 5x5 grid the boss has 321 HP at depth 5 (was 251), 376 at depth 10 (was 291)
and 431 at depth 15 (was 331). The bonus alone makes the boss easier (the geared
average player's depth-5 win rate rises from 46% to 65% with +10 s), so HP has to
rise to bring the win rates back into ADR-005's bands. Two numbers were needed
rather than one because the bonus helps deep fights more than the first one: a
flat +60 HP left the depth-10 average player just above that band (43%) and the
depth-15 strong player on its edge, so the per-depth slope rises too.

The win-rate bands are unchanged, and the two edges ADR-005 had widened by 2 points
(depth-10 average, depth-15 strong) are back at their original values: the new
tuning does not need the slack.

Geared win rates, depth 5 / 10 / 15 (1,000 fights a cell):

| 5x5 grid | Depth 5 | Depth 10 | Depth 15 |
|---|---|---|---|
| Novice | 14% | 7% | 4% |
| Average | 47% | 36% | 26% |
| Strong | 85% | 78% | 69% |
| Expert | 97% | 95% | 94% |

On 9x9 (boss +8 HP): average 46 / 32 / 25%, strong 84 / 77 / 69%.

### 4. What it bought: less dependence on the guess about pace

Geared win rates, depth 5 / 10 / 15, 400 fights a cell. "Before" is ADR-005's tuning.

| Everyone's pace | Average, before | Average, after | Strong, before | Strong, after |
|---|---|---|---|---|
| 30% slower | 11 / 7 / 3 | 21 / 16 / 12 | 61 / 52 / 43 | 75 / 64 / 60 |
| as modelled | 44 / 32 / 24 | 49 / 37 / 25 | 86 / 80 / 73 | 85 / 77 / 68 |
| 30% faster | 66 / 57 / 45 | 59 / 46 / 34 | 92 / 89 / 82 | 89 / 81 / 73 |

The gap between a fast and a slow crowd (average player, depth 5) falls from 55
points to 38. It is not gone: a clock bonus can only soften the pace assumption,
not remove it. The other sensitivities are about where they were (`--sensitivity`
prints the full table). `test_boss_balance.gd` checks the narrowing directly.

## Consequences

Positive:
- The boss's difficulty rests less on the least certain assumption.
- A slow but knowledgeable player is no longer walled by the clock.
- The mechanism is data: any enemy can use it, and retuning is a JSON edit.

Negative:
- A much bigger boss (321 / 376 / 431 HP against 251 / 291 / 331) and longer
  fights: more rounds, so more chances for a slip, which is the intended shape but
  means the fight runs longer in real time.
- Fast answers hit harder on boss rounds (see 1), which pushes the HP up further.
- Still no real players: pace, the boss's size and the bonus itself are all
  guesses until someone plays it. If real players are fast, the bonus is slack that
  mostly makes the boss bigger.

## Alternatives considered

- **A smaller bonus (+5 s with +25 HP).** Fits the bands, but narrows the pace gap
  only from 55 to 45 points (a 30% slower average player: 20 / 14 / 9%).
- **A larger bonus (+15 s).** Not tuned or measured. +10 s is already a third more
  clock on a 30 s clue, and because extra seconds also raise damage on fast answers
  (see 1) a bigger bonus would need still more boss HP.
- **Change the damage formula so the extra seconds do not raise the speed bonus.**
  Rejected: CLAUDE.md 9.5 keeps the formula off limits without approval, and the
  other timer bonuses behave this way already.
- **Raise the boss clock for everyone with a setting.** Rejected: a global change
  to a single boss's problem; the accessibility extended-timer already does that for
  players who need it.
