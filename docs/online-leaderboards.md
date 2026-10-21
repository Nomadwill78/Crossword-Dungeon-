# Online leaderboards and accounts: design plan

Status: **proposed**, nothing here is built. Written for the browser build, the
only build with a Daily Challenge. Decisions already made by the project owner
are marked **(decided)**; anything still open is in "Open questions" at the end.

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
   score is the **sum of their five best daily scores** in that week. Fewer than
   five days played just means fewer scores in the sum.
3. **Hardcore is separate**: its own daily and weekly boards, ranked on the
   hardcore final score (already x1.5). Normal and hardcore scores never mix.
4. **Guests are separate**: guest boards and registered boards are different
   lists. A guest who registers **starts accumulating on the registered boards
   from the moment they register, not before**. Earlier guest runs stay on the
   guest boards and never count towards a registered weekly total.

Everything is a board of (mode, kind, daily or weekly): 2 modes x 2 kinds x
2 spans = 8 boards, all read from one table of runs.

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
"best five days per week" and rankings awkward; Godot or a separate game server
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
- Each run is stamped `board = 'guest'` or `'registered'` **at submit time**,
  from the user's state then. That one column implements the rule "start
  accumulating when you register": earlier runs keep `guest` forever, later ones
  are `registered`. Nothing is migrated or recomputed.
- Display name: guests are shown as `Guest-XXXX` (from the id) unless they pick
  a name; registered players choose one (3 to 20 letters, digits, spaces, `_-`;
  checked against a block list; a report button for the rest). The email is
  never shown to anyone.
- Signing in on a new device with the same email gives the registered history.
  A guest on a new device is a new guest (their old guest runs stay with the old
  device's guest id), which is the cost of "no registration".

## 5. Making scores trustworthy: replay on the server

The client sends not just a score but the **event log** of the run, and the
server recomputes the score from scratch.

**What a run is made of** (all of it already deterministic):

- the dungeon, the hero and every dice roll come from the day (`dailySeed(key)`),
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

1. checks the player is signed in (guest or registered), the day is today or
   yesterday in UTC, the mode and hero are valid, and the ruleset version is one
   it knows (an out-of-date cached game gets "reload to update"),
2. rebuilds `new DungeonRun(LEVEL_ONE, hero, { seed, hardcore })` and applies
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
order by score desc, submitted_at limit 100`. Ties go to whoever finished first.

**Weekly board**: a view over each user's five best days:

```sql
create view weekly_scores as
select user_id, board, mode, week_start,
       sum(score)         as total,        -- best five days
       count(*)           as days_counted,
       max(submitted_at)  as reached_at    -- when the counted total was complete
from (
  select *, row_number() over (
    partition by user_id, board, mode, week_start
    order by score desc, submitted_at) as rn
  from runs
) ranked
where rn <= 5
group by user_id, board, mode, week_start;
```

Ranked by `total desc, reached_at asc`. A week's board is final after Saturday
UTC ends; the current week is live.

**Security.** Row-level security on: nobody can insert into `runs` from the
browser, only the server function (service role) can, after verifying. Boards are
read through the function or through views that expose only
`display_name, score, day` (never email or user id). A user may read and delete
their own rows.

## 7. API

All under `api/` on the same origin.

| Call | Does |
|---|---|
| `POST /api/runs` | the section 5 verification, then insert; returns the verified score, the day rank and the weekly total so far |
| `GET /api/board?mode=&board=&span=daily\|weekly&key=` | top 100 plus the caller's own row and rank, cached for about 30 s |
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
   the board you belong to), a Sign in / Register dialog (email), a display-name
   field, and "Your rank today" on the Daily result card.
4. **Offline and failure**: the local daily result keeps working exactly as
   today, so the game never needs the network to play. A failed submission is
   queued in `localStorage` and retried at the next visit; the player is told
   once ("Saved here; will post when you are online").
5. **Streaks** stay local at first. Syncing them for registered accounts is a
   later step; the table already has what it needs.

## 9. Delivery in four independent pull requests

1. **Event log and replay, no network.** `runlog.js`, `replay.js`, `RULESET`.
   Tests: the autoplay bot plays many whole runs (normal and hardcore, several
   heroes), each log is replayed and must give exactly the live score;
   tampered logs (edited answer, impossible tile, extra cast, wrong day or
   hero) must be rejected. Shippable alone and invisible to players.
2. **Backend and guest boards.** Supabase project and migrations (tables, view,
   RLS), `POST /api/runs`, `GET /api/board`, anonymous sign-in, the Leaderboard
   dialog for guests (daily and weekly, both modes). SQL tests for the weekly
   view (best five of seven, fewer than five, ties, week boundaries on a
   Sunday, hardcore kept apart).
3. **Email sign-up and registered boards.** Magic-link registration that keeps
   the user id, `board` stamped at submit time, display names, the registered
   boards, and sign-in on a new device. Tests: guest runs before registration
   never reach a registered total; runs after do; a guest then registered on
   the same day can have one run on each board.
4. **Hardening and moderation.** Pacing checks for hardcore, rate limits,
   report and remove tooling, data export and account deletion, a short privacy
   notice.

Each can be reviewed and shipped on its own, and the game works at every step.

## 10. Privacy and operations

- Stored per player: an optional display name, an email only for registered
  players, and their runs. No tracking, no ads, nothing sold.
- Registered players can delete their account and every run from a setting
  (phase 4). Guests have no email to delete; their rows can be removed on request.
- Email is handled by Supabase's sign-in; we never see or store a password.
- Backups: the managed daily backup on the paid tier; the free tier is enough
  for launch but has no point-in-time restore, so the plan assumes upgrading when
  the board matters.
- Costs: free tiers cover early use. The things that grow are database rows (a
  run is about 5 KB with its log) and function calls.

## 11. Open questions

1. **Which build is "the real one"?** This plan covers the **browser build**,
   because that is where the Daily Challenge, the seeded dungeons and the
   replayable rules live. The **Godot build** has no Daily and no seeded runs,
   and its rules are in GDScript, so it cannot reuse server-side replay. If the
   paid, registered game is the Godot build, its accounts could share this
   service, but its scores would need a different checking approach (or a port of
   the seeded daily to Godot first). Which build do registered players use?
2. **"Best cumulative score, Sunday to Saturday".** I read this as the weekly
   score being the sum of the five best daily scores in that Sunday-to-Saturday
   week, as agreed. If you meant all seven days summed, the view changes from
   `rn <= 5` to no limit.
3. **Display names**: free text with a block list as above, or choose from a
   generated list (for example "Gentle Quill 482") with no moderation at all?
4. **Minimum for the weekly board**: should a player with only one or two days
   appear, or only after, say, three? As written they appear.
5. **Weekly prizes or titles?** Not in this plan; if yes, "final after Saturday"
   and tie-breaks above would need to be formalised.
