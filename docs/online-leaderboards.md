# Online leaderboards and accounts: design plan

Status: **proposed**, nothing here is built. Written for the **browser build**,
which is the real game and the only one that gets accounts and boards. (The
Godot build is the separate itch.io release; it has no accounts, no Daily and no
leaderboards, and is out of scope here.) Decisions already made by the project
owner are listed in "Decided" near the end; the few readings of them worth a
glance are in "Interpretations" after it.

## 1. What we are building

Two kinds of player, each with their own boards:

| | Guest | Registered |
|---|---|---|
| Sign-up | none | email |
| Plays the Daily | yes | yes |
| Appears on a board | a **guest** board | a **registered** board |
| History | this device only, plus the guest board | follows the account across devices |

Rules **(decided)**:

1. **Daily board**: every player's score for one UTC day, highest first. Only the
   first finished run of a day counts, as today (replays are practice).
2. **Weekly board**: a week runs **Sunday to Saturday, UTC**. A player's weekly
   score is the **sum of all their daily scores in that week** (up to seven, one
   per day). A day not played adds nothing, so showing up every day is what
   wins the week.
3. **Hardcore is separate**: its own daily and weekly boards, ranked on the
   hardcore final score (already x1.5). Normal and hardcore scores never mix.
   **This needs a mode that does not exist yet.** Today the Daily Challenge is
   always a standard run and hardcore applies only to free play, whose dungeons
   are random and so cannot be replayed or compared. A hardcore board therefore
   requires a **Daily Hardcore**: a daily with its **own** seeded dungeon and
   hero (its own seed, separate from the normal Daily's), played under the
   hardcore rules. It is built first (section 9, step 1), and the hardcore
   boards stay hidden until it ships.
4. **Guests are separate**: guest boards and registered boards are different
   lists. A guest who registers **starts accumulating on the registered boards
   from the moment they register, not before**. Earlier guest runs stay on the
   guest boards and never count towards a registered weekly total.

5. **Who is shown (decided)**: every player who posts any score is **counted**
   and ranked, but a board **acknowledges only its top 20**: those 20 are listed
   with their names. Everyone else still sees their own rank and score (for
   example "You are #57 this week") without being listed. The **top 3 are
   highlighted** on a board. There are **no prizes**. The **#1 on a weekly
   board is that week's champion**, a title shown on the board and kept in a
   record of past champions.

Everything is a board of (mode, kind, daily or weekly): 2 modes x 2 kinds x
2 spans = 8 boards, all read from one table of runs. Each week therefore crowns
up to four champions (normal and hardcore, guest and registered).

## 2. How it is saved today, and why that is not enough

The result of each day is kept in the player's own browser (`localStorage`,
`src/daily.js`): score, retreats, hints used, hero. It is not tied to a person,
does not follow them to another device, and nothing checks it. For a leaderboard
the client cannot be trusted with the score, so the server must work it out.

## 3. Recommendation

| Piece | Choice | Why |
|---|---|---|
| Site | stays a static site on Vercel | no change |
| API | **Vercel Functions** (Node) in an `api/` folder | same host, no new vendor, and Node can run our own game code |
| Database and auth | **Supabase** (Postgres + email sign-in) | one service gives a real SQL database (the boards are SQL queries), email magic-link sign-up with verification, and anonymous users for guests; generous free tier |
| Score checking | **replay the run on the server** with the same `src/` code | see section 5 |

Why not the alternatives: rolling our own auth on a bare database means
building sign-up, email verification, sessions and password-reset by hand, which
is where the security mistakes come from; a document database (Firebase) makes
"total per week" and rankings awkward; Godot or a separate game server
would mean rewriting the game rules a second time. The JS rules are pure
modules (`DungeonRun`, `BattleSession`, the seeded generators) and the daily
dungeon is already deterministic across engines, so running them on the server
is the cheapest way to get a score nobody can fake.

## 4. Identity: guests and registered players

- Every browser gets a Supabase **anonymous user** on first visit (a real auth
  user flagged `is_anonymous`). No form, no email. That user id is the guest.
- Registering is Supabase's "link an email to an anonymous user": the user
  enters an email, gets a magic link, clicks it. The **same user id** continues,
  now with `is_anonymous = false`. Magic link means no passwords to store or
  reset.
- Each run is stamped `board = 'guest'` or `'registered'` from **when it was
  finished, not when it reaches the server**. The client records `finished_at`
  with the run; the server sets `board = 'registered'` only if the user has a
  `registered_at` and `finished_at >= registered_at`, otherwise `'guest'`.
  So a guest who finishes a run offline, registers, and only then reconnects has
  that run posted to the **guest** board, as the rule requires. That one column
  implements "start accumulating when you register": earlier runs keep `guest`
  forever, later ones are `registered`. Nothing is migrated or recomputed.
  The server never accepts a `finished_at` in the future or outside the run's
  day. A client that lies about it can only move one of its own runs from the
  registered board to the guest board, which is not worth faking.
- Display name: guests are shown as `Guest-XXXX` (from the id) unless they pick
  a name; registered players choose one (**free text**, 3 to 20 letters, digits,
  spaces, `_-`, checked against a block list; a report button for the rest, and
  an administrator can remove a name). The email is never shown to anyone.
- Signing in on a new device with the same email gives the registered history.
  A guest on a new device is a new guest (their old guest runs stay with the old
  device's guest id), which is the cost of "no registration".

## 5. Making scores trustworthy: replay on the server

The client sends not just a score but the **event log** of the run, and the
server recomputes the score from scratch.

**What a run is made of** (all of it already deterministic):

- the dungeon, the hero and every dice roll come from the day and the mode
  (`dailySeed(key)` for the normal Daily, a separate seed for Daily Hardcore),
- the player's decisions: typed answers (`attemptSolve`), bought hints
  (`buyHint`), and for each battle the tiles chosen to cast (`BattleSession`),
  with the battle's randomness fixed per corridor and attempt (`battleRng`).

**The log** is an ordered list, a few KB per run:

```
{ v: RULESET, day: "2026-10-21", mode: "normal" | "hardcore", hero: "...",
  events: [
    { t: "answer", i: 4, text: "GOBLIN" },
    { t: "hint",   i: 4, level: 1, pay: "score" },
    { t: "cast",   tiles: [3, 0, 5] },        // positions in the rack, in pick order
    { t: "timeout" },                          // hardcore only
    { t: "fight",  i: 4 }                      // re-enter a corridor after a retreat
  ] }
```

**The server** (a Vercel Function) then:

1. checks the player is signed in (guest or registered), the mode and hero are
   valid, the ruleset version is one it knows (an out-of-date cached game gets
   "reload to update"), and that the run is **inside its submission window**:
   a day's result is accepted until **48 hours after that UTC day ends**, and
   the finished-at time falls inside that day. After the window a late result is
   refused with a clear message, so a closed daily or weekly board never changes
   under people's feet (a week is final 48 hours after its Saturday ends),
2. rebuilds `new DungeonRun(LEVEL_ONE, hero, { seed, hardcore })` (the seed and
   hero come from the day and the mode, never from the client) and applies
   each event through the real methods; any impossible event (a corridor not
   reachable yet, a tile not in the rack, a cast after the fight ended) rejects
   the whole run,
3. takes the **recomputed** `finalScore()` as the score. The client's claimed
   score is only compared to catch bugs, never stored as truth,
4. inserts the run, once per (user, mode, board, day): the first finished run of
   the day counts and any later one is refused, which also enforces the
   existing rule.

Cost is small: a replay is a few milliseconds of CPU, and payloads are capped
(for example 64 KB).

**What replay cannot prove, said plainly.**

- **The hardcore clock.** The 15 seconds per word is measured in the player's
  browser (and pauses when a dialog opens or the tab is hidden), so the server
  cannot see it. We log client timestamps and reject impossible pacing (for
  example casts closer together than a human can type, or a run shorter than
  its number of actions allows), but a determined cheater can fake plausible
  timings. Hardcore boards are therefore "checked, not proven". A stronger
  option, later: the server hands out a signed start time when each battle
  opens, at the cost of a round trip per battle.
- **Players who know the answers.** Everyone plays the same dungeon, so answers
  can be shared. That is the nature of a daily puzzle (as with Wordle), not
  something replay can solve. The first-run-only rule limits the damage.
- **A bot that plays well.** A program that solves clues and casts best words is
  indistinguishable from a good player. Mitigations are rate limits and the
  option to remove a score by hand.

**Versioning.** Any change to the generator, the word list, the dictionary or
the balance changes what a log produces. The log carries `RULESET`, a version
constant bumped on any such change, and the server keeps the ruleset it was
deployed with. After a deploy, a player on a stale cached page is asked to
reload. We never replay an old log under new rules.

## 6. Data model (Postgres)

```sql
profiles (
  user_id      uuid primary key references auth.users,
  display_name text,                       -- null for an unnamed guest
  registered_at timestamptz,               -- set when the email is linked
  created_at   timestamptz default now()
);

runs (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references profiles,
  board        text not null check (board in ('guest','registered')),
  mode         text not null check (mode in ('normal','hardcore')),
  day          date not null,                         -- the UTC day it was played for
  week_start   date not null,                         -- that day's Sunday, see below
  hero         text not null,
  score        int  not null,                         -- recomputed by the server; hardcore includes x1.5
  retreats     int  not null,
  hints_used   int  not null,
  ruleset      text not null,
  log          jsonb not null,                        -- the event log, kept so a run can be re-verified
  finished_at  timestamptz not null,                  -- when the run ended, client-reported, validated
  submitted_at timestamptz not null default now(),
  unique (user_id, board, mode, day)                  -- first finished run of a day counts
);
create index runs_daily  on runs (board, mode, day,        score desc, submitted_at);
create index runs_weekly on runs (board, mode, week_start, user_id);
```

`week_start` is the Sunday on or before `day`: `day - extract(dow from day)::int`
(Postgres `dow` is 0 for Sunday). It is stored, not derived at read time, so a
query can use the index.

**Daily board**: `select ... from runs where board = $1 and mode = $2 and day = $3
order by score desc, submitted_at limit 20`. Ties go to whoever finished first.
The same query with `count(*)` and a rank window gives every other player their
own rank, so players outside the top 20 are counted without being listed.

**Weekly board**: a view that adds up each user's days in the week:

```sql
create view weekly_scores as
select user_id, board, mode, week_start,
       sum(score)         as total,        -- all days played that week (at most 7)
       count(*)           as days_counted,
       max(submitted_at)  as reached_at    -- when the latest counted run was posted
from runs
group by user_id, board, mode, week_start;
```

Ranked by `total desc, reached_at asc` (a tie goes to whoever reached that total
first). A week's board is live until it is final, which is **48 hours after
that Saturday ends in UTC** (the same window as late submissions, so it can no
longer change).

**Weekly champions.** Once a week is final, its #1 on each board (guest or
registered, normal or hardcore) becomes that week's champion. A daily job
(a Vercel cron) writes the champion rows for any final week that has none yet,
so a champion is recorded once and never changes afterwards:

```sql
weekly_champions (
  week_start date not null,
  board      text not null,
  mode       text not null,
  user_id    uuid not null references profiles,
  display_name text not null,        -- copied, so a later rename or deletion does not rewrite history
  total      int  not null,
  primary key (week_start, board, mode)
);
```

If a champion later deletes their account the row stays but the name is
replaced by "Deleted player".

**Security.** Row-level security on: nobody can insert, update or delete `runs`
from the browser; only the server function (service role) can insert, after
verifying. A user may **read** their own rows and nothing else. In particular
there is **no per-run delete**: if a player could delete their first result they
could submit another for the same day and re-roll the score, which would defeat
the first-run rule. The only removal is deleting the **whole account** (which
cascades to its runs and display name), after which that identity no longer
exists. Boards are read through the function or through views that expose only
`display_name, score, day` (never email or user id).

**Limit, stated plainly.** "First finished run counts" is per identity. A guest
who clears their browser data becomes a new guest, and anyone can register a
second email, so a determined person can re-roll under a new identity. Replay
verification stops fake scores; it does not stop this. The mitigations are that
registering needs a working email, and that a re-roll can only improve one day's
score, which is a small share of a seven-day total.

## 7. API

All under `api/` on the same origin.

| Call | Does |
|---|---|
| `POST /api/runs` | the section 5 verification, then insert; returns the verified score, the day rank and the weekly total so far |
| `GET /api/board?mode=&board=&span=daily\|weekly&key=` | the top 20, plus the caller's own row and rank wherever they are, cached for about 30 s |
| `GET /api/champions?mode=&board=` | past weekly champions, newest first |
| `POST /api/profile` | set the display name (validated, rate limited) |
| (Supabase client) | anonymous sign-in, email magic link, sign-out |

Rate limits: one verified submission per (user, mode, board, day) by the unique
constraint, plus a per-IP limit on `POST /api/runs`, `/api/profile` and sign-ups.

## 8. Changes to the game

1. **Event recorder** (`src/runlog.js`): `main.js` appends an event on every
   answer, hint, cast, timeout and re-entered fight. No gameplay change.
2. **Replay module** (`src/replay.js`): applies a log to a `DungeonRun` and
   returns the score. Shared by the server and by tests, with no DOM and no
   network, so it is built and tested first.
3. **Client** (`src/net.js` and UI): a Leaderboard dialog with
   Daily/Weekly, Normal/Hardcore and Guest/Registered switches (defaulting to
   the board you belong to) listing the top 20 with the top 3 highlighted and a
   "Your rank" row when you are outside the list, a champion banner for the last
   finished week, a Sign in / Register dialog (email), a display-name field, and
   "Your rank today" on the Daily result card.
4. **Offline and failure**: the local daily result keeps working exactly as
   today, so the game never needs the network to play. A failed submission is
   queued in `localStorage` with its `finished_at`, retried at the next visit,
   and the player is told the true deadline: "Saved here. It will post when you
   are back online, within 2 days of the end of the day you played." A queued
   result that misses the window is dropped with a message saying so; it is
   kept on the device for their own record.
5. **Streaks** stay local at first. Syncing them for registered accounts is a
   later step; the table already has what it needs.

## 9. Delivery in five independent pull requests

1. **Daily Hardcore mode.** A Hardcore switch on the Daily tab that plays
   its own daily dungeon and hero (seeded from the date with a hardcore salt, so
   it is a different puzzle from the normal Daily) under the hardcore rules
   (permadeath, the 15 second word clock, the wrong-answer cost, x1.5 final
   score), with its own once-a-day result and streak kept apart from the normal
   Daily. This is gameplay, not leaderboard work, and the hardcore boards below
   depend on it.
2. **Event log and replay, no network.** `runlog.js`, `replay.js`, `RULESET`.
   Tests: the autoplay bot plays many whole runs (normal and hardcore, several
   heroes), each log is replayed and must give exactly the live score;
   tampered logs (edited answer, impossible tile, extra cast, wrong day or
   hero) must be rejected. Shippable alone and invisible to players.
3. **Backend and guest boards.** Supabase project and migrations (tables, view,
   RLS), `POST /api/runs`, `GET /api/board`, anonymous sign-in, the Leaderboard
   dialog for guests (daily and weekly, both modes, top 20 with the top 3
   highlighted, and the caller's own rank), and the weekly champions job. SQL
   tests for the weekly view (a full seven days, fewer than seven, ties, week
   boundaries on a Sunday, hardcore kept apart) and for the champions job (the
   #1 of a final week is recorded once and never changes; a week not yet final
   has none).
4. **Email sign-up and registered boards.** Magic-link registration that keeps
   the user id, `board` set from `finished_at` against `registered_at`, display names, the registered
   boards, and sign-in on a new device. Tests: guest runs before registration
   never reach a registered total; runs after do; a guest then registered on
   the same day can have one run on each board; a guest run finished offline
   before registering and submitted after it lands on the guest board.
5. **Hardening and moderation.** Pacing checks for hardcore, rate limits,
   report and remove tooling (an administrator can remove a score; players
   cannot), data export and whole-account deletion, a short privacy notice.

Each can be reviewed and shipped on its own, and the game works at every step.

## 10. Privacy and operations

- Stored per player: an optional display name, an email only for registered
  players, and their runs. No tracking, no ads, nothing sold.
- Registered players can delete their account, and with it every run, from a
  setting (step 5). They cannot delete single runs (see section 6). Guests have no email to delete; their rows can be removed on request.
- Email is handled by Supabase's sign-in; we never see or store a password.
- Backups: the managed daily backup on the paid tier; the free tier is enough
  for launch but has no point-in-time restore, so the plan assumes upgrading when
  the board matters.
- Costs: free tiers cover early use. The things that grow are database rows (a
  run is about 5 KB with its log) and function calls.

## 11. Decided

1. **The real game is the browser build.** Accounts and boards are for it. The
   Godot build is the itch.io release and is separate: no accounts, no Daily, no
   leaderboards. (So the server-side replay in section 5 covers everything that
   gets a board.)
2. **Hardcore is on its own**: its own boards (section 1) and its own daily
   dungeon (Daily Hardcore, section 9 step 1), not the normal Daily under
   different rules.
3. **Display names are free text with a block list** (and report and remove
   tools); there are no generated names.
4. **Every scorer is counted, the top 20 are listed.** Anyone who posts a score
   is ranked and sees their own rank; a board lists only its top 20 by name. The
   **top 3 are highlighted**, there are **no prizes**, and **#1 on a weekly board
   is that week's champion** (final 48 hours after Saturday ends).
5. Weekly score is the **sum of all of a player's daily scores in a
   Sunday-to-Saturday UTC week** (seven days captured; a missed day adds
   nothing); guests are separate; a guest who registers
   starts counting on registered boards from registration; sign-up is by email.

## 12. Interpretations worth a glance

Nothing is blocking. Three readings of the decisions that are easy to change:

- **"Acknowledged" means listed.** A player outside the top 20 is counted and is
  told their own rank privately, but is not named on the board.
- **Highlighting the top 3** applies to the daily boards as well as the weekly
  ones; only the weekly #1 gets the champion title.
- **Champions are crowned per board**, so a week has up to four (normal and
  hardcore, guest and registered), not one overall.
