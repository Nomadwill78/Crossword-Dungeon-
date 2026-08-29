# DESIGN DOCUMENT
# Wordsmith's Gambit — Premium Puzzle-RPG Hybrid
# Version: 1.0.0 | Date: 2026-07-13
# Target Platform: Windows, macOS, Linux (Godot 4.x), Web Demo (Phaser 3)
# Monetization: Direct website sale, single purchase + annual pass
# ============================================================

## 1. ELEVATOR PITCH

A roguelike puzzle-RPG where every dungeon is a procedural crossword grid. 
Solve letters to unlock rooms, fight word-themed monsters, and chain vocabulary 
combos into devastating special attacks. Premium, DRM-free, single-purchase with 
optional annual pass for daily challenges and competitive leaderboards.

## 2. CORE VALUE PROPOSITION

**The Hook:** Every crossword clue is a combat encounter. The answer length 
determines enemy difficulty. The answer itself is your weapon.

**The Loop:**
1. Enter dungeon → receive procedural crossword grid (5×5 to 9×9)
2. Select an unsolved letter → combat encounter triggers
3. Solve the clue → letter fills in, damage dealt to enemy
4. Chain solved letters into words → unlock combo attacks
5. Fill the grid → boss encounter, then meta-progression rewards
6. Die or retreat → keep meta-unlocks, start new run

## 3. TARGET AUDIENCE

- Primary: Puzzle game fans (Crossword, Wordle, Scrabble players), ages 25-45
- Secondary: Roguelike enthusiasts seeking lighter, brainier runs
- Tertiary: Language learners and trivia buffs
- Estimated TAM: 50M+ crossword players globally
- Price sensitivity: Medium ($15-30 acceptable for premium puzzle experiences)

## 4. CORE MECHANICS

### 4.1 The Crossword-Dungeon Grid

- Grid size scales with player level: 5×5 (tutorial) → 7×7 (standard) → 9×9 (endgame)
- Each cell is either:
  - **Black cell** (wall/impassable)
  - **Empty letter cell** (unsolved — combat encounter)
  - **Solved letter cell** (safe zone, can traverse freely)
  - **Bonus cell** (gold, health potion, or rare item — appears post-solve)
- Player starts at grid entrance (top-left), must reach exit (bottom-right)
- Movement: 4-directional, one cell per move, only on solved or empty cells

### 4.2 Combat System: "The Word Duel"

When player steps on an unsolved letter cell:

**Phase 1: The Clue Reveal**
- Enemy appears with a crossword clue (e.g., "A large feline predator, 3 letters")
- Timer begins (30s base, scales with difficulty)
- Player can see: clue text, answer length, enemy HP, enemy attack pattern

**Phase 2: Answer Input**
- Player types answer (e.g., "CAT")
- Each correct letter deals damage:
  - 1-letter word: 10 damage per letter
  - 2-letter word: 8 damage per letter
  - 3-letter word: 6 damage per letter
  - 4-letter word: 5 damage per letter
  - 5-letter word: 4 damage per letter
  - 6+ letter word: 3 damage per letter + bonus effect
- Wrong answer: enemy attacks, player takes damage, can retry (max 3 attempts)
- Timeout: enemy attacks automatically

**Phase 3: Resolution**
- If enemy HP ≤ 0: letter solves, cell becomes safe, rewards granted
- If player HP ≤ 0: run ends, meta-progression calculated, return to hub
- Letter solved: permanently filled in grid for this run

### 4.3 Combo System: "Vocabulary Chains"

- When 2+ solved letters form a valid word (horizontal or vertical), player 
  can activate a "Vocabulary Chain" on their turn
- Chain power = word length × average letter rarity (A=1, Z=26)
- Chain effects:
  - 3-letter: +20% damage next 3 encounters
  - 4-letter: Heal 15% max HP
  - 5-letter: Reveal one random unsolved letter on grid
  - 6-letter: Skip one encounter (auto-solve)
  - 7-letter: Double rewards next encounter
  - 8+ letter: Ultimate — clear entire row/column of unsolved letters
- Chains can be stacked but not overlapping (one active chain at a time)
- Strategic depth: solve letters in order to form high-value chains, or 
  rush to exit with minimal encounters?

### 4.4 Enemy Design

Enemy types themed around word/language concepts:

| Enemy | Theme | Attack Pattern | Weakness |
|-------|-------|---------------|----------|
| Anagram | Scrambles letters | Swaps 2 random solved letters | Words with double letters |
| Palindrome | Mirror words | Reverses player input | Palindromic answers (radar, level) |
| Homophone | Sound-alikes | Clues with homophones | Context clues |
| Acronym | Abbreviations | Shortens timer by 50% | Full-word answers |
| Portmanteau | Blended words | Merges 2 clues into 1 | Compound answers |
| Boss: The Thesaurus | Synonym master | Changes clue mid-fight | Exact-match answers only |

Enemy scaling:
- Base HP = 20 + (dungeon depth × 5) + (grid size × 2)
- Base damage = 5 + (dungeon depth × 2)
- Special abilities unlock at dungeon depths 3, 6, 10, 15

### 4.5 Meta-Progression: "The Lexicon"

Between runs, players access The Lexicon (persistent hub):

**Unlockable Systems:**
- **Vocabulary Trees** — Skill trees themed by word category:
  - Science Tree: +damage for science-related answers
  - History Tree: +timer for history clues
  - Arts Tree: +chain duration for art-related words
  - Nature Tree: +healing from nature words
- **Dictionary Upgrades** — Expand clue database (start with 1,000, unlock to 10,000+)
- **Tome Slots** — Equip up to 3 passive bonuses before a run
- **Trophy Room** — Achievement gallery showing rare words found, chains completed

**Currency: "Ink Drops"**
- Earned by: solving letters, completing chains, finishing dungeons, daily login
- Spent on: vocabulary trees, cosmetic grid themes, dictionary expansions
- No microtransactions — Ink Drops are purely gameplay-earned

### 4.6 Difficulty & Accessibility

- **Casual Mode:** Unlimited retries per clue, 60s timer, 50% more HP
- **Standard Mode:** 3 retries per clue, 30s timer, normal scaling
- **Hardcore Mode:** 1 retry per clue, 15s timer, permadeath (no meta-progression kept)
- **Daily Challenge:** Fixed seed for all players, leaderboard by time + score
- **Colorblind support:** Pattern-based letter differentiation, not just color
- **Dyslexia-friendly:** OpenDyslexic font option, slower timer option

## 5. PROGRESSION SYSTEMS

### 5.1 Run Progression (Within a Dungeon)

- Player starts each run with: 100 HP, basic dictionary, no active chains
- Each solved letter: +5 HP (capped at max), +10 Ink Drops
- Each chain activated: +20 Ink Drops, +1 chain streak counter
- Every 3rd chain: random bonus (potion, tome, or dictionary fragment)
- Grid completion: boss fight, then exit to hub with all Ink Drops

### 5.2 Meta Progression (The Lexicon)

- **Player Level:** 1-50, earned by total Ink Drops collected
- **Level Unlocks:**
  - Lv 5: Unlock 7×7 grids
  - Lv 10: Unlock chain stacking (2 active chains)
  - Lv 15: Unlock Hardcore mode
  - Lv 20: Unlock 9×9 grids
  - Lv 25: Unlock custom grid themes
  - Lv 30: Unlock "The Thesaurus" boss fight
  - Lv 40: Unlock daily challenge participation
  - Lv 50: Unlock "Grandmaster" title + exclusive cosmetics

### 5.3 Content Milestones

| Milestone | Content Added | Estimated Hours |
|-----------|--------------|-----------------|
| Launch | 1,000 clues, 5 enemy types, 3 grid sizes, 20 vocabulary nodes | 15-20 |
| Month 1 | +500 clues, 2 new enemy types, seasonal theme | 20-25 |
| Month 3 | +1,000 clues, 9×9 grid, boss rush mode | 30-40 |
| Month 6 | +2,000 clues, multiplayer daily races, community clue submissions | 40-50 |
| Year 1 | 10,000+ clues, 15 enemy types, 5 grid sizes, full mod support | 100+ |

## 6. MONETIZATION

### 6.1 Pricing Tiers

| Tier | Price | Contents |
|------|-------|----------|
| **Base Game** | $14.99 | Full game, all modes, no DRM, lifetime updates |
| **Supporter Edition** | $29.99 | Base game + Digital Art Book (50+ pages) + Original Soundtrack (12 tracks) + Name in Credits + Exclusive "Founder" grid theme |
| **Annual Pass** | $9.99/year | Daily challenge server access, seasonal word packs (4/year), competitive leaderboards, exclusive cosmetics, priority support |

### 6.2 Direct-Sale Advantages

- **Margin:** ~95% vs. Steam's 70% (after payment processing)
- **Customer ownership:** Email list for sequel marketing, DLC announcements
- **No platform risk:** Cannot be delisted, buried by algorithm, or forced into sales
- **Bundle flexibility:** Can participate in Humble/Itch bundles while maintaining direct store

### 6.3 Anti-Piracy Strategy

- No DRM (builds trust, reduces refund requests)
- Online features (daily challenges, leaderboards) require valid purchase key
- Community and update cadence incentivize legitimate ownership
- "Pirate Edition" easter egg: if cracked copy detected, all clues become lorem ipsum

## 7. CONTENT PIPELINE

### 7.1 Clue Database Structure

```json
{
  "id": "clue_0001",
  "answer": "CAT",
  "length": 3,
  "clue_text": "A small domesticated carnivorous mammal",
  "category": "nature",
  "difficulty": 1,
  "tags": ["animals", "pets", "common"],
  "frequency_cap": 5,
  "last_used": null
}
```

- Categories: nature, science, history, arts, geography, mythology, pop_culture, literature
- Difficulty 1-5: based on word frequency in common usage (Google Ngram data)
- Frequency cap: max times a clue appears per player per week (prevents repetition)
- Procedural generation: combine clue templates with answer database for near-infinite variety

### 7.2 Asset Requirements

| Asset Type | Count | Style | Source |
|------------|-------|-------|--------|
| Grid cell sprites | 10 | Minimalist, high-contrast | Procedural (code-generated) |
| Enemy portraits | 15 | Stylized ink/typography | Commissioned artist ($2-3k) |
| UI elements | 30 | Clean, readable | In-house (Claude + designer) |
| Sound effects | 25 | Subtle, satisfying | SFX pack + custom |
| Music tracks | 12 | Ambient, focus-friendly | Commissioned composer ($3-5k) |
| Grid themes | 8 | Seasonal/cosmetic | In-house |

**Total art budget: ~$8,000** (one-time, covers launch + 6 months)

## 8. TECHNICAL REQUIREMENTS

### 8.1 Performance Targets

- **Desktop:** 60 FPS on Intel i3 / 8GB RAM / integrated graphics
- **Web Demo:** 30 FPS on Chrome/Firefox/Safari, <50MB initial load
- **Mobile (future):** 30 FPS on mid-range Android/iOS (Phase 2)
- **Save file size:** <1MB per player (text-serialized state)
- **Load time:** <3 seconds from title screen to gameplay

### 8.2 Platform Support

| Platform | Launch | Phase 2 | Phase 3 |
|----------|--------|---------|---------|
| Windows | ✓ | ✓ | ✓ |
| macOS | ✓ | ✓ | ✓ |
| Linux | ✓ | ✓ | ✓ |
| Web (demo) | ✓ | ✓ | ✓ |
| Steam | ✗ | ✓ | ✓ |
| iOS/Android | ✗ | ✗ | ✓ |

## 9. SUCCESS METRICS

### 9.1 Launch Targets (Month 1)

- 1,000 direct sales at $14.99 = $14,990 gross revenue
- 15% Supporter Edition uptake = $4,500 additional
- 10% Annual Pass conversion = $1,500 recurring
- **Total Month 1: ~$21,000** (covers art budget + 3 months operating costs)

### 9.1 Year 1 Targets

- 5,000 total sales
- 25% Annual Pass retention
- $75,000 gross revenue
- 85%+ positive reviews
- <5% refund rate

### 9.2 Key Performance Indicators

| KPI | Target | Measurement |
|-----|--------|-------------|
| Day 1 retention | 60% | % of buyers who play within 24h |
| Day 7 retention | 35% | % who play again within 7 days |
| Avg session length | 25 min | Per-session play time |
| Avg run completion | 45% | % of runs that reach exit |
| Chain activation rate | 30% | % of possible chains activated |
| Daily challenge participation | 20% | % of active players doing daily |
| Refund rate | <5% | Platform refund requests |
| Support ticket volume | <2% | Tickets per 100 sales |

## 10. RISK ANALYSIS

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| AI-generated code has bugs | High | Medium | Extensive automated testing, QA bots, beta period |
| Clue database feels repetitive | Medium | High | 10,000+ seed clues, procedural templates, community submissions |
| Puzzle audience won't pay $15 | Medium | High | Free web demo, transparent pricing, Supporter Edition for whales |
| Competing word games (Wordle clones) | High | Low | Premium positioning, depth of systems, no ads/microtransactions |
| Claude Code subscription costs | High | Medium | Optimize prompts, reuse code patterns, limit scope |
| Payment processor issues | Low | High | Backup processor (Paddle if LemonSqueezy fails) |
| Negative reviews at launch | Medium | High | 2-week closed beta with 100 players, iterate before public launch |

## 11. POST-LAUNCH ROADMAP

### Month 1-2: Stability
- Bug fixes, performance optimization
- First community clue submission batch
- Balance tuning based on analytics

### Month 3-4: Expansion
- 9×9 grid size
- 2 new enemy types
- First seasonal word pack (Spring)

### Month 5-6: Community
- User-generated clue system
- Weekly community challenges
- Mod support (custom grid themes, clue packs)

### Month 7-12: Growth
- Steam launch (if direct sales justify it)
- Mobile port consideration
- Sequel/DLC planning based on data

---

## APPENDIX A: GLOSSARY

- **Chain:** Two or more solved letters forming a valid word, activated for bonus effects
- **Clue:** The crossword-style hint presented during combat
- **Dungeon:** A single crossword grid + associated encounters
- **Ink Drops:** Meta-progression currency earned through gameplay
- **Lexicon:** The persistent hub between runs where upgrades are purchased
- **Run:** A single playthrough from grid entry to exit or death
- **Tome:** Equipable passive bonus item
- **Vocabulary Tree:** Skill tree themed by word category

## APPENDIX B: REFERENCE GAMES

- *Slay the Spire* — roguelike deckbuilding progression
- *Crosswords* (NYT) — clue quality and difficulty curve
- *Baba Is You* — word-as-mechanic design philosophy
- *Wordle* — daily habit formation, social sharing
- *Into the Breach* — perfect information, puzzle-like combat

## APPENDIX C: BRAND GUIDELINES

- **Tone:** Intellectual but approachable, witty but not condescending
- **Visual:** Ink and parchment aesthetic, high contrast, typography-focused
- **Audio:** Quiet, ambient, focus-enhancing (no distracting music during combat)
- **Writing:** Clever clues that teach something (etymology, trivia, word origins)
- **Community:** Encourage sharing of impressive chains, rare words found, speedrun times

---
Document Owner: Game Director
Review Cycle: Bi-weekly during development, monthly post-launch
Distribution: Full team, investors, marketing
