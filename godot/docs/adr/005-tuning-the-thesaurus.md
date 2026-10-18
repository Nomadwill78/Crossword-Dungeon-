# ADR-005: Tuning The Thesaurus against a simulated person

## Status
Accepted. The tuning is only as good as the model of a player behind it, and
that model is assumptions, not playtest data. Everything needed to redo it with
real data is a JSON edit (see "Retuning").

## Context

ADR-004 shipped The Thesaurus untuned: "the playtest bot wins ~90% of fights".
That number says nothing about people. The bot (`tests/bots/random_bot.gd`)
answers every boss round with no clock, so it always earns the full speed bonus,
never times out, never finds the opposite-of phase harder than a plain clue, and
types perfectly. A real player does none of that. So the first job was to find a
yardstick, the second to tune against it.

No real playtest data exists yet. The yardstick is therefore a simulation of
people, with every assumption written down where it can be changed.

## Decision

### 1. Measure with a simulated person (`tests/bots/BossBalance.gd`)

Every simulated fight runs through the real `BossEncounter`,
`CombatStateMachine` and `CombatEngine`, so the damage formula, the boss's HP and
strikes, the phases and the player's Lexicon loadout are the game's own. What is
simulated is the person, per attempt:

- **How long they take**, against the clue's real clock (`SimTimer`, a test-only
  stand-in for `TimerSystem`). A slow answer earns less speed bonus; running out
  of clock is a miss.
- **Whether they know the answer.** Harder in the opposite-of phase; a second
  look helps, and the phase-1 reworded clue helps more.
- **Typos**, and in the archaic phase whether they type the archaic spelling
  (full damage) or the modern one (accepted at half).

The assumptions (`model`), the kinds of player (`archetypes`: novice, average,
strong, expert, each a `recall` and a `speed`), what they bring (`loadouts`: bare,
and "geared", a Lv 30 player with the Vitality, Ward and Might tomes built through
the real `LexiconEffects`) and the targets are all in `tests/bots/boss_balance.json`.

`godot --headless --path . tests/bots/BossBalanceRunner.tscn` prints the table;
adding `-- --sensitivity` shows how it moves when each assumption changes.

### 2. Targets (a design choice, not a measurement)

The boss is meant for the geared player. Intent: the first boss (depth 5) is a
coin-flip for an average player and a fair test for a strong one; deeper bosses
are harder, but gently, so every fifth floor stays a fight you can win rather than
a wall. Win-rate bands for the geared loadout:

| Depth | Novice | Average | Strong | Expert |
|---|---|---|---|---|
| 5 | 3-20% | 38-55% | 78-92% | 92-100% |
| 10 | 2-15% | 26-42% | 68-84% | 90-100% |
| 15 | 1-12% | 20-34% | 58-78% | 85-98% |

`tests/unit/test_boss_balance.gd` fails if the boss drifts out of them, at the
smallest and the largest supported grid (see section 4). Two edges (depth-10
average, depth-15 strong) were widened by 2 points, from 28% and 76%, once grid
size was included: both depend on the same HP scale, the room between them is
narrow, and the real uncertainty (section 5) is far larger than 2 points.

### 3. What was wrong

| Geared win rate | Depth 5 | Depth 10 | Depth 15 |
|---|---|---|---|
| Average, before | 42% | 15% | 4% |
| Average, after | 44% | 32% | 24% |
| Strong, before | 85% | 61% | 30% |
| Strong, after | 85% | 80% | 73% |
| Expert, before | 97% | 87% | 67% |
| Expert, after | 97% | 96% | 94% |

(5x5 grid.) Depth 5 was already in its bands. Depths 10 and 15 were walls: 7 of
the 12 cells were out of range. The cause is that difficulty came from two places at once,
more HP and a harder strike (+3 per depth), and the strike hits a cliff. A geared
player arrives with about 100 HP and a strike costs `floor(damage x 0.85)`: at 33
or less it takes four misses to die, at 34 to 49 only three, at 50 and up two. The old +3 per depth
crossed that line between depth 5 and depth 10, so a deeper boss was not "a bit
harder" but "one fewer mistake allowed".

### 4. The change (`enemies_master.json`, boss_thesaurus)

| | Before | After |
|---|---|---|
| `base_hp` | 200 | 201 |
| `scaling.hp_per_depth` | 10 | 8 |
| `base_damage` | 20 | 30 |
| `scaling.damage_per_depth` | 3 | 0 |

So the boss has 251 HP at depth 5 (was 260), 291 at depth 10 (was 310) and 331 at
depth 15 (was 360) on a 5x5 grid, and strikes for a flat 30 (was 35, 50, 65). Depth now makes
the fight longer (more rounds, more chances to slip) instead of making each slip
costlier, which keeps difficulty off the cliff. Values from 30 to 39 behave the
same for the geared player (the 15% reduction floors them to the same strike); 30
is the bottom of that range. A grid search over HP and damage picked the setting
with the largest worst-case margin to the band edges.

**Grid size** (found in review). A Lv 30 player can pick a 5x5, 7x7 or 9x9
dungeon, and the live fight passes that size to the boss, which gains 2 HP per grid
cell of size (so +4 on 7x7, +8 on 9x9). The first version of this tuning simulated
5x5 only; at 9x9 the average player's depth-10 win rate sat on the very edge of its
band. The simulation now takes a `grid_size` (`--grid=9` on the runner), the tuning
was re-centred (`base_hp` 205 to 201) so it holds at every size, and the tests
check the geared bands at the smallest and the largest supported size
(`grid.supported_sizes` in `game_config.json`): average players win 44 / 32 / 24%
on 5x5 and 40 / 29 / 22% on 9x9 at depths 5 / 10 / 15. A boss that passed the old
5x5-only test but fails at 9x9 (for instance 216 base HP) now fails the suite.

### 5. How much to trust it (`--sensitivity`)

Geared win rates, depth 5 / 10 / 15, after the change:

| Assumption changed | Average | Strong |
|---|---|---|
| as configured (5x5) | 44 / 32 / 24 | 86 / 80 / 73 |
| arrive at full HP | 59 / 46 / 40 | 94 / 90 / 86 |
| arrive at 60% HP | 28 / 18 / 12 | 71 / 64 / 54 |
| opposite-of phase is easy | 52 / 42 / 33 | 91 / 89 / 84 |
| opposite-of phase is hard | 33 / 20 / 16 | 74 / 67 / 55 |
| nobody knows the archaic spelling | 39 / 27 / 20 | 84 / 78 / 70 |
| everyone knows it | 49 / 37 / 30 | 87 / 83 / 77 |
| twice the typos | 40 / 28 / 21 | 81 / 74 / 66 |
| no typos | 49 / 37 / 29 | 90 / 86 / 80 |
| everyone 30% slower | 11 / 7 / 3 | 61 / 52 / 43 |
| everyone 30% faster | 66 / 57 / 45 | 92 / 89 / 82 |
| 7x7 grid (boss +4 HP) | 41 / 30 / 23 | 86 / 80 / 73 |
| 9x9 grid (boss +8 HP) | 40 / 29 / 22 | 85 / 79 / 72 |

- **The shape is robust.** Under every variant the win rate falls gently with
  depth and better players win more. `test_boss_balance.gd` checks a few of these.
- **The level is not.** It moves a lot with how fast people really answer
  (30% slower turns the average player's 44% into 11%) and with the HP they arrive
  with. Those are the two numbers to find out first in real play.

### 6. Two incidental fixes

- `TestRunner.gd` printed "ALL SUITES PASSED" (exit 0) when a suite's script failed
  to compile: building the suite list aborted, came back empty, and the loop ran
  zero times. It now fails with exit 1 when the list is empty.
- Existing tests that pinned the old numbers ("200 + 10 per depth", "three misses at
  35 each kill a 100 HP player") now derive their expectations from the boss's data,
  so a retune does not break them. The balance suite is where the tuning is pinned.

## Retuning

1. Put real figures in `tests/bots/boss_balance.json`: archetype `recall` and
   `speed`, `arrival_hp`, the model's phase multipliers, and the target bands.
2. `godot --headless --path . tests/bots/BossBalanceRunner.tscn -- --fights=1000`
3. Edit the four numbers above in `enemies_master.json` until the table is inside
   the bands; `test_boss_balance.gd` then agrees.

## Consequences

Positive:
- The boss has a measurable target, a reproducible report and a regression guard.
- The depth-10 and depth-15 walls are gone; the first boss is unchanged in spirit
  (a touch easier: 251 HP and 30 a strike instead of 260 and 35).
- Retuning from real data is data, not code.

Negative:
- The targets and the person model are my assumptions. If real players are slower
  than modelled, the boss is harder than the table says (and the other way round).
- Flat strike damage means depth never makes a single mistake costlier.
- The model has no learning: a player who has fought the boss before does better.

## Alternatives considered

- **Tune to the playtest bot.** Rejected: untimed, near-perfect, no phase effects.
  It still runs as a soft-lock check.
- **Keep the +3 strike per depth and trim HP instead.** Rejected: any slope in the
  strike lands deep fights on the three-miss cliff (a depth-15 average player wins
  16-19%, below the band) wherever the HP is set.
- **Strikes as a share of max HP.** Rejected: a new combat rule, and CLAUDE.md 9.5
  keeps the damage formula off limits without approval.
- **A boss-specific clock bonus.** Not done, but the obvious next lever: answer
  speed is the biggest unknown, and a few extra seconds on boss rounds would raise
  win rates a lot without touching HP or damage.
