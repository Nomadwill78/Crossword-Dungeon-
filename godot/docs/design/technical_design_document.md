# TECHNICAL DESIGN DOCUMENT
# Wordsmith's Gambit — Systems Architecture & Implementation Spec
# Version: 1.0.0 | Date: 2026-07-13
# Engine: Godot 4.3+ (GDScript) | Web Demo: Phaser 3
# ============================================================

## 1. ARCHITECTURE OVERVIEW

### 1.1 Design Philosophy

- **Data-driven:** All game content (clues, enemies, upgrades) lives in JSON/YAML.
  Game logic reads these files; no hardcoded content. This allows Claude Code to
  reason about the entire game state as text.
- **State-serialized:** The entire game state (dungeon, player, meta-progression)
  can be dumped to a single JSON string and restored perfectly. Enables save/load,
  debug replay, and automated testing.
- **Event-driven:** Core systems communicate via an event bus. Decouples systems
  and makes testing individual components trivial.
- **Headless-friendly:** All game logic runs without rendering. Enables automated
  playtesting bots, balance simulation, and server-side daily challenge validation.

### 1.2 System Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        GAME LAYER                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   Dungeon   │  │   Combat    │  │      Meta-Progression   │  │
│  │   System    │  │   System    │  │      (The Lexicon)      │  │
│  └──────┬──────┘  └──────┬──────┘  └───────────┬─────────────┘  │
│         │                │                      │                │
│  ┌──────▼────────────────▼──────────────────────▼─────────────┐  │
│  │                    EVENT BUS (Signal-based)                 │  │
│  └──────┬────────────────┬──────────────────────┬─────────────┘  │
│         │                │                      │                │
│  ┌──────▼──────┐  ┌──────▼──────┐  ┌───────────▼────────────┐  │
│  │  Save/Load  │  │   Audio     │  │      Analytics         │  │
│  │   System    │  │   Manager   │  │      (Optional)        │  │
│  └─────────────┘  └─────────────┘  └────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────────┐
│                      DATA LAYER                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   Clue      │  │   Enemy     │  │      Player Profile     │  │
│  │  Database   │  │  Database   │  │      (Save File)        │  │
│  │  (JSON)     │  │  (JSON)     │  │      (JSON)             │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   Grid      │  │   Vocab     │  │      Daily Challenge    │  │
│  │  Generator  │  │   Trees     │  │      Seeds (JSON)       │  │
│  │  (Procedural)│  │  (JSON)     │  │                         │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────────┐
│                    PLATFORM LAYER                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   Godot     │  │   Phaser 3  │  │      Web API            │  │
│  │  (Desktop)  │  │  (Web Demo) │  │  (Daily Challenges)     │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 1.3 File Structure

```
wordsmiths_gambit/
├── assets/
│   ├── audio/
│   │   ├── sfx/              # 25 sound effects (.ogg)
│   │   └── music/            # 12 music tracks (.ogg)
│   ├── fonts/
│   │   ├── OpenDyslexic/     # Accessibility font
│   │   └── primary.ttf       # Main game font
│   ├── images/
│   │   ├── enemies/          # 15 enemy portraits (.png)
│   │   ├── ui/               # 30 UI elements (.png/.svg)
│   │   └── themes/           # 8 grid themes (JSON + textures)
│   └── shaders/
│       └── grid_effects.gdshader
├── data/
│   ├── clues/
│   │   ├── clues_master.json     # 10,000+ clues
│   │   ├── clues_categories.json # Category mappings
│   │   └── clues_difficulty.json # Difficulty index
│   ├── enemies/
│   │   ├── enemies_master.json   # Enemy definitions
│   │   └── enemy_abilities.json  # Special ability data
│   ├── vocabulary/
│   │   ├── trees.json            # Vocabulary tree definitions
│   │   ├── tomes.json            # Equippable item definitions
│   │   └── cosmetics.json        # Unlockable visual themes
│   └── config/
│       ├── game_config.json      # Global balance constants
│       ├── grid_presets.json     # Grid size templates
│       └── daily_seeds.json      # Pre-generated daily challenge seeds
├── src/
│   ├── autoload/
│   │   ├── EventBus.gd           # Global signal/event system
│   │   ├── GameState.gd          # Persistent game state manager
│   │   ├── SaveManager.gd        # Save/load orchestration
│   │   ├── AudioManager.gd       # Music/SFX controller
│   │   └── ConfigLoader.gd       # JSON data loader
│   ├── core/
│   │   ├── grid/
│   │   │   ├── GridGenerator.gd  # Procedural crossword generation
│   │   │   ├── GridCell.gd       # Individual cell logic
│   │   │   ├── GridNavigator.gd  # Player movement & pathfinding
│   │   │   └── GridRenderer.gd   # Visual grid rendering
│   │   ├── combat/
│   │   │   ├── CombatEngine.gd   # Turn resolution & damage calc
│   │   │   ├── ClueResolver.gd   # Answer validation & scoring
│   │   │   ├── TimerSystem.gd    # Combat countdown logic
│   │   │   └── EnemyAI.gd        # Enemy behavior & attack selection
│   │   ├── combo/
│   │   │   ├── ChainDetector.gd  # Word chain identification
│   │   │   ├── ChainValidator.gd # Dictionary validation
│   │   │   └── ChainEffects.gd   # Bonus application
│   │   └── progression/
│   │       ├── InkDropManager.gd # Currency tracking
│   │       ├── VocabularyTree.gd # Skill tree logic
│   │       ├── TomeManager.gd    # Equip/unequip system
│   │       └── AchievementTracker.gd
│   ├── scenes/
│   │   ├── main_menu/
│   │   ├── dungeon/
│   │   ├── combat/
│   │   ├── lexicon_hub/
│   │   └── settings/
│   ├── ui/
│   │   ├── components/           # Reusable UI widgets
│   │   ├── themes/               # Godot theme resources
│   │   └── accessibility/        # Screen reader, colorblind modes
│   └── utils/
│       ├── Constants.gd          # Game-wide constants
│       ├── Helpers.gd            # String/math utilities
│       ├── Validators.gd         # Input validation
│       └── Logger.gd             # Structured logging
├── tests/
│   ├── unit/                     # Individual system tests
│   ├── integration/              # Multi-system tests
│   ├── bots/                     # Automated playtest bots
│   └── benchmarks/               # Performance tests
├── docs/
│   ├── api/                      # Auto-generated API docs
│   └── design/                   # Design documents
├── export/
│   ├── web/                      # Phaser 3 web demo build
│   ├── windows/                  # Windows executable
│   ├── macos/                    # macOS app bundle
│   └── linux/                    # Linux executable
├── tools/
│   ├── clue_generator/           # Python script for clue batch generation
│   ├── balance_simulator/        # Python script for economy simulation
│   └── daily_seed_generator/     # Python script for daily challenge seeds
├── project.godot
├── export_presets.cfg
└── README.md
```

---

## 2. DATA STRUCTURES

### 2.1 Core Game State (Serialized)

The entire game state is a single JSON object. This is the "source of truth" 
that gets saved to disk, sent to the server for daily challenges, and used 
by automated testing bots.

```json
{
  "version": "1.0.0",
  "timestamp": "2026-07-13T14:30:00Z",
  "player_profile": {
    "player_id": "uuid-v4-string",
    "display_name": "PlayerOne",
    "created_at": "2026-07-01T10:00:00Z",
    "total_playtime_seconds": 7200,
    "total_runs": 45,
    "total_letters_solved": 1240,
    "longest_chain": 8,
    "highest_score": 15420,
    "player_level": 12,
    "ink_drops": 3400,
    "current_streak_days": 5,
    "longest_streak_days": 12
  },
  "lexicon": {
    "vocabulary_trees": {
      "science": {
        "nodes_unlocked": ["sci_01", "sci_02", "sci_03"],
        "nodes_purchased": ["sci_01", "sci_02"],
        "total_invested": 800
      },
      "history": {
        "nodes_unlocked": ["hist_01"],
        "nodes_purchased": ["hist_01"],
        "total_invested": 200
      },
      "arts": {
        "nodes_unlocked": [],
        "nodes_purchased": [],
        "total_invested": 0
      },
      "nature": {
        "nodes_unlocked": ["nat_01", "nat_02"],
        "nodes_purchased": ["nat_01"],
        "total_invested": 300
      }
    },
    "equipped_tomes": ["tome_healing_01", "tome_damage_01", null],
    "unlocked_tomes": ["tome_healing_01", "tome_damage_01", "tome_timer_01"],
    "unlocked_themes": ["default", "parchment", "midnight"],
    "active_theme": "parchment",
    "achievements": {
      "first_run": true,
      "first_chain": true,
      "speed_demon": false,
      "vocabulary_master": false,
      "grandmaster": false
    }
  },
  "current_run": {
    "run_id": "uuid-v4-string",
    "started_at": "2026-07-13T14:00:00Z",
    "difficulty": "standard",
    "grid_size": 7,
    "dungeon_depth": 3,
    "player_state": {
      "current_hp": 65,
      "max_hp": 100,
      "position": {"x": 3, "y": 4},
      "active_chains": [
        {
          "word": "PLANET",
          "cells": [{"x": 2, "y": 4}, {"x": 3, "y": 4}, {"x": 4, "y": 4}, {"x": 5, "y": 4}, {"x": 6, "y": 4}, {"x": 7, "y": 4}],
          "effect": "reveal_letter",
          "turns_remaining": 2
        }
      ],
      "inventory": {
        "health_potions": 2,
        "dictionary_fragments": 1,
        "special_items": []
      },
      "combo_streak": 3,
      "total_ink_drops_this_run": 340
    },
    "grid_state": {
      "size": 7,
      "cells": [
        {
          "x": 0, "y": 0,
          "type": "entrance",
          "letter": null,
          "solved": true,
          "enemy_id": null,
          "bonus": null
        },
        {
          "x": 1, "y": 0,
          "type": "letter",
          "letter": "C",
          "solved": true,
          "enemy_id": null,
          "bonus": null
        },
        {
          "x": 2, "y": 0,
          "type": "letter",
          "letter": null,
          "solved": false,
          "enemy_id": "enemy_anagram_03",
          "bonus": null,
          "clue_id": "clue_0847"
        },
        {
          "x": 0, "y": 1,
          "type": "black",
          "letter": null,
          "solved": false,
          "enemy_id": null,
          "bonus": null
        }
      ],
      "words_horizontal": [
        {"start": {"x": 0, "y": 0}, "end": {"x": 6, "y": 0}, "length": 7, "solved": false}
      ],
      "words_vertical": [
        {"start": {"x": 0, "y": 0}, "end": {"x": 0, "y": 6}, "length": 7, "solved": false}
      ]
    },
    "combat_log": [
      {
        "timestamp": "2026-07-13T14:05:00Z",
        "enemy_id": "enemy_palindrome_01",
        "clue_id": "clue_0234",
        "answer": "LEVEL",
        "damage_dealt": 25,
        "damage_taken": 10,
        "time_remaining": 12,
        "attempts": 1,
        "chain_activated": false
      }
    ],
    "boss_encountered": false,
    "boss_defeated": false,
    "run_status": "in_progress"
  },
  "settings": {
    "audio": {
      "master_volume": 0.8,
      "music_volume": 0.6,
      "sfx_volume": 0.9
    },
    "display": {
      "fullscreen": false,
      "resolution": "1920x1080",
      "grid_theme": "parchment",
      "colorblind_mode": "none",
      "dyslexia_font": false,
      "text_size": "medium"
    },
    "gameplay": {
      "difficulty": "standard",
      "timer_visible": true,
      "hint_enabled": true,
      "auto_save": true,
      "auto_save_interval_seconds": 60
    },
    "accessibility": {
      "screen_reader": false,
      "high_contrast": false,
      "reduced_motion": false,
      "extended_timer": false
    }
  },
  "daily_challenges": {
    "last_completed_date": "2026-07-12",
    "completion_history": [
      {"date": "2026-07-10", "score": 12400, "rank": 45, "time_seconds": 420},
      {"date": "2026-07-11", "score": 13800, "rank": 23, "time_seconds": 380},
      {"date": "2026-07-12", "score": 11200, "rank": 67, "time_seconds": 510}
    ]
  },
  "statistics": {
    "runs_by_difficulty": {
      "casual": 12,
      "standard": 28,
      "hardcore": 5
    },
    "letters_solved_by_category": {
      "nature": 340,
      "science": 280,
      "history": 210,
      "arts": 150,
      "geography": 180,
      "mythology": 80
    },
    "chains_by_length": {
      "3": 45,
      "4": 32,
      "5": 18,
      "6": 8,
      "7": 3,
      "8": 1
    },
    "enemies_defeated": {
      "enemy_anagram": 23,
      "enemy_palindrome": 15,
      "enemy_homophone": 12,
      "enemy_acronym": 8,
      "enemy_portmanteau": 5
    },
    "fastest_run_seconds": 180,
    "average_run_seconds": 420,
    "total_deaths": 18
  }
}
```

### 2.2 Clue Data Structure

```json
{
  "clues": [
    {
      "id": "clue_0001",
      "answer": "CAT",
      "answer_length": 3,
      "clue_text": "A small domesticated carnivorous mammal",
      "alternate_clues": [
        "Feline pet that purrs",
        "Animal that says 'meow'"
      ],
      "category": "nature",
      "subcategory": "animals",
      "difficulty": 1,
      "difficulty_score": 0.85,
      "frequency_rank": 150,
      "tags": ["animals", "pets", "common", "three_letter"],
      "etymology_hint": "From Old English 'catt', related to Latin 'cattus'",
      "frequency_cap_per_player": 5,
      "frequency_cap_global": 1000,
      "last_used_global": "2026-07-12T08:00:00Z",
      "times_used_global": 450,
      "is_procedural": false,
      "procedural_template": null,
      "created_at": "2026-01-15T00:00:00Z",
      "verified": true,
      "contributor": "core_team"
    }
  ],
  "procedural_templates": [
    {
      "template_id": "temp_nature_animal_01",
      "category": "nature",
      "subcategory": "animals",
      "template_text": "A {adjective} {animal} found in {location}",
      "variables": {
        "adjective": ["small", "large", "colorful", "nocturnal"],
        "animal": ["mammal", "bird", "reptile", "insect"],
        "location": ["Africa", "the ocean", "tropical forests", "arctic regions"]
      },
      "difficulty_range": [2, 4],
      "answer_source": "animal_database"
    }
  ]
}
```

### 2.3 Enemy Data Structure

```json
{
  "enemies": [
    {
      "id": "enemy_anagram_01",
      "name": "The Anagram",
      "display_name": "Anagram",
      "description": "A shapeshifting creature that scrambles the letters of solved words.",
      "enemy_type": "anagram",
      "tier": 1,
      "base_hp": 25,
      "base_damage": 8,
      "attack_pattern": "scramble",
      "special_ability": {
        "name": "Letter Swap",
        "description": "Swaps 2 random solved letters on the grid",
        "trigger_condition": "player_takes_damage",
        "cooldown_turns": 3,
        "effect": {
          "type": "grid_manipulation",
          "swap_count": 2,
          "target": "solved_letters"
        }
      },
      "weakness": {
        "type": "word_property",
        "property": "double_letter",
        "description": "Words with double letters deal +50% damage",
        "bonus_multiplier": 1.5
      },
      "resistance": {
        "type": "word_property",
        "property": "single_letter",
        "description": "Single-letter words deal -25% damage",
        "penalty_multiplier": 0.75
      },
      "visual": {
        "portrait": "enemy_anagram.png",
        "animation_idle": "anim_anagram_idle",
        "animation_attack": "anim_anagram_attack",
        "animation_defeat": "anim_anagram_defeat",
        "color_theme": "#8B4513"
      },
      "audio": {
        "spawn_sfx": "sfx_anagram_spawn.ogg",
        "attack_sfx": "sfx_anagram_attack.ogg",
        "defeat_sfx": "sfx_anagram_defeat.ogg"
      },
      "scaling": {
        "hp_per_depth": 5,
        "damage_per_depth": 2,
        "ability_unlock_depth": 3
      },
      "flavor_text": "It speaks in tongues — all of them at once, and none of them correctly."
    }
  ],
  "bosses": [
    {
      "id": "boss_thesaurus",
      "name": "The Thesaurus",
      "display_name": "The Thesaurus",
      "description": "The guardian of all words. It knows every synonym, antonym, and obscure variant.",
      "is_boss": true,
      "base_hp": 200,
      "base_damage": 20,
      "phases": [
        {
          "phase": 1,
          "hp_threshold": 1.0,
          "ability": "synonym_swap",
          "description": "Changes the clue to a synonym mid-fight"
        },
        {
          "phase": 2,
          "hp_threshold": 0.5,
          "ability": "antonym_inversion",
          "description": "Reverses the meaning of the clue"
        },
        {
          "phase": 3,
          "hp_threshold": 0.25,
          "ability": "obscure_variant",
          "description": "Demands archaic or rare spellings"
        }
      ],
      "weakness": {
        "type": "exact_match",
        "description": "Only exact-match answers deal full damage; synonyms deal 50%",
        "bonus_multiplier": 1.0,
        "penalty_multiplier": 0.5
      }
    }
  ]
}
```

### 2.4 Vocabulary Tree Data Structure

```json
{
  "vocabulary_trees": {
    "science": {
      "tree_id": "science",
      "tree_name": "Science",
      "tree_description": "Unlock the power of scientific knowledge.",
      "tree_icon": "icon_science.png",
      "tree_color": "#4A90D9",
      "nodes": [
        {
          "node_id": "sci_01",
          "name": "Curiosity",
          "description": "+10% damage for science-related answers",
          "cost": 200,
          "prerequisites": [],
          "effects": [
            {
              "type": "damage_multiplier",
              "category": "science",
              "value": 1.1,
              "scope": "combat"
            }
          ],
          "max_rank": 1,
          "icon": "node_curiosity.png"
        },
        {
          "node_id": "sci_02",
          "name": "Hypothesis",
          "description": "+5 seconds on science clue timers",
          "cost": 300,
          "prerequisites": ["sci_01"],
          "effects": [
            {
              "type": "timer_bonus",
              "category": "science",
              "value": 5,
              "scope": "combat"
            }
          ],
          "max_rank": 1,
          "icon": "node_hypothesis.png"
        },
        {
          "node_id": "sci_03",
          "name": "Breakthrough",
          "description": "Science chains grant +1 Ink Drop per letter",
          "cost": 500,
          "prerequisites": ["sci_02"],
          "effects": [
            {
              "type": "chain_bonus",
              "category": "science",
              "value": 1,
              "scope": "combo"
            }
          ],
          "max_rank": 1,
          "icon": "node_breakthrough.png"
        }
      ]
    }
  }
}
```

### 2.5 Tome Data Structure

```json
{
  "tomes": [
    {
      "tome_id": "tome_healing_01",
      "name": "Tome of Restoration",
      "description": "Heal 5% max HP after each solved letter.",
      "rarity": "common",
      "slot": "passive",
      "effects": [
        {
          "type": "post_combat_heal",
          "trigger": "letter_solved",
          "value": 0.05,
          "value_type": "percentage_max_hp"
        }
      ],
      "unlock_condition": {
        "type": "player_level",
        "value": 3
      },
      "cost": 300,
      "icon": "tome_healing_01.png"
    },
    {
      "tome_id": "tome_damage_01",
      "name": "Tome of Precision",
      "description": "+15% damage on first attempt answers.",
      "rarity": "uncommon",
      "slot": "passive",
      "effects": [
        {
          "type": "first_attempt_bonus",
          "trigger": "combat_first_attempt",
          "value": 1.15,
          "value_type": "damage_multiplier"
        }
      ],
      "unlock_condition": {
        "type": "achievement",
        "value": "first_chain"
      },
      "cost": 500,
      "icon": "tome_damage_01.png"
    }
  ]
}
```

---

## 3. SYSTEMS SPECIFICATIONS

### 3.1 Grid Generation System

**Responsibility:** Create procedural crossword grids of varying sizes with 
valid word intersections, balanced difficulty, and strategic pathing.

**Algorithm:** Modified backtracking with constraint propagation.

```gdscript
# GridGenerator.gd — Core Algorithm
class_name GridGenerator

const GRID_TEMPLATES = {
    5: preload("res://data/config/grid_5x5_templates.json"),
    7: preload("res://data/config/grid_7x7_templates.json"),
    9: preload("res://data/config/grid_9x9_templates.json")
}

# Grid cell types
enum CellType { BLACK, LETTER, ENTRANCE, EXIT, BONUS }

# Generates a complete grid for a new dungeon run
func generate_grid(size: int, depth: int, player_level: int) -> Dictionary:
    var grid = {
        "size": size,
        "cells": [],
        "words_horizontal": [],
        "words_vertical": [],
        "difficulty_rating": 0.0
    }

    # Step 1: Select base template (pre-designed black cell patterns)
    var template = _select_template(size, depth)

    # Step 2: Place entrance (top-left) and exit (bottom-right)
    template = _place_entrance_exit(template, size)

    # Step 3: Identify word slots (contiguous letter sequences)
    var word_slots = _identify_word_slots(template, size)

    # Step 4: Fill slots with answers from clue database
    var filled_grid = _fill_word_slots(word_slots, depth, player_level)

    # Step 5: Assign enemies to unsolved letters
    filled_grid = _assign_enemies(filled_grid, depth)

    # Step 6: Place bonus cells (10% of solved cells)
    filled_grid = _place_bonuses(filled_grid)

    # Step 7: Validate solvability (path from entrance to exit exists)
    if not _validate_solvability(filled_grid):
        # Retry with different template
        return generate_grid(size, depth, player_level)

    # Step 8: Calculate difficulty rating
    grid.difficulty_rating = _calculate_difficulty(filled_grid)

    return filled_grid

# Select appropriate template based on depth and player level
func _select_template(size: int, depth: int) -> Array:
    var templates = GRID_TEMPLATES[size]
    var valid_templates = []

    for template in templates:
        var min_depth = template.get("min_depth", 1)
        var max_depth = template.get("max_depth", 999)
        if depth >= min_depth and depth <= max_depth:
            valid_templates.append(template)

    # Weight toward templates the player hasn't seen recently
    return _weighted_random_choice(valid_templates, "recency_penalty")

# Fill word slots with answers that intersect correctly
func _fill_word_slots(slots: Array, depth: int, player_level: int) -> Dictionary:
    var filled = {}
    var clue_pool = _get_clue_pool(depth, player_level)

    # Sort slots by constraint tightness (most constrained first)
    slots.sort_custom(_constraint_tightness_sort)

    for slot in slots:
        var length = slot.length
        var intersecting_letters = _get_intersecting_letters(slot, filled)

        # Find clues where answer matches length AND intersecting letters
        var candidates = clue_pool.filter(func(clue):
            return clue.answer_length == length and                    _matches_intersections(clue.answer, intersecting_letters)
        )

        # Weight by difficulty appropriateness and recency
        candidates = _weight_candidates(candidates, depth, player_level)

        if candidates.is_empty():
            # Backtrack: remove last filled slot and retry
            return _backtrack_and_retry(slots, filled, slot)

        var selected = candidates.pick_random()
        filled[slot.id] = selected
        _mark_clue_used(selected.id)

    return filled

# Validate that a path exists from entrance to exit
func _validate_solvability(grid: Dictionary) -> bool:
    var start = _find_cell(grid, "entrance")
    var end = _find_cell(grid, "exit")

    # BFS pathfinding — player can move through empty or solved cells
    var queue = [start]
    var visited = {str(start): true}

    while not queue.is_empty():
        var current = queue.pop_front()
        if current == end:
            return true

        for neighbor in _get_neighbors(current, grid):
            var key = str(neighbor)
            if not visited.has(key) and _is_traversable(neighbor, grid):
                visited[key] = true
                queue.append(neighbor)

    return false
```

**Performance Requirements:**
- Grid generation: <100ms for 5×5, <500ms for 9×9
- Backtrack limit: Max 10 retries before falling back to simpler template
- Memory: Grid state <50KB per dungeon

### 3.2 Combat System

**Responsibility:** Handle all combat encounters: clue presentation, answer 
validation, damage calculation, timer management, and enemy AI.

**State Machine:**

```
[ENCOUNTER_START] → [CLUE_REVEAL] → [PLAYER_INPUT] → [VALIDATION]
     ↑                    ↓              ↓                ↓
     └────────────────────┴──────────────┴──[ENEMY_ATTACK]←┘
                                          ↓
                                   [RESOLUTION]
                                          ↓
                    ┌─────────────────────┼─────────────────────┐
                    ↓                     ↓                     ↓
              [PLAYER_VICTORY]      [PLAYER_DEFEAT]       [PLAYER_RETREAT]
                    ↓                     ↓                     ↓
              [LETTER_SOLVED]      [RUN_ENDS]            [GRID_EXIT]
```

**Damage Formula:**

```gdscript
# CombatEngine.gd — Damage Calculation
func calculate_damage(
    answer: String,
    clue: Dictionary,
    enemy: Dictionary,
    player_state: Dictionary,
    attempt_number: int,
    time_remaining: float
) -> Dictionary:

    var result = {
        "damage_dealt": 0,
        "damage_taken": 0,
        "is_correct": false,
        "is_first_attempt": attempt_number == 1,
        "chain_triggered": false,
        "bonus_effects": []
    }

    # Base damage per letter
    var base_damage_per_letter = _get_base_damage(answer.length())
    var total_base_damage = base_damage_per_letter * answer.length()

    # Multipliers
    var multipliers = 1.0

    # Difficulty bonus (harder words = more damage)
    multipliers *= (1.0 + (clue.difficulty * 0.1))

    # First attempt bonus
    if attempt_number == 1:
        multipliers *= 1.25

    # Time bonus (faster = more damage, capped at 2x)
    var time_ratio = time_remaining / _get_base_timer(clue.difficulty)
    multipliers *= clamp(1.0 + (time_ratio * 0.5), 1.0, 2.0)

    # Vocabulary tree bonuses
    multipliers *= _get_category_multiplier(clue.category, player_state)

    # Tome bonuses
    multipliers *= _get_tome_multiplier("combat", player_state)

    # Enemy weakness/resistance
    if _matches_weakness(answer, enemy):
        multipliers *= enemy.weakness.bonus_multiplier
    elif _matches_resistance(answer, enemy):
        multipliers *= enemy.resistance.penalty_multiplier

    # Calculate final damage
    result.damage_dealt = floor(total_base_damage * multipliers)

    # Enemy counter-attack (if not defeated)
    if result.damage_dealt < enemy.current_hp:
        result.damage_taken = _calculate_enemy_damage(enemy, player_state, attempt_number)

    result.is_correct = true

    # Check for chain trigger
    result.chain_triggered = _check_chain_trigger(answer, player_state)

    return result

func _get_base_damage(word_length: int) -> int:
    match word_length:
        1: return 10
        2: return 8
        3: return 6
        4: return 5
        5: return 4
        6: return 3
        7: return 3
        8: return 3
        _: return 2  # 9+ letters
```

**Timer System:**

```gdscript
# TimerSystem.gd
class_name CombatTimer

signal timer_expired
signal timer_warning  # At 50%, 25%, 10% remaining
signal timer_paused
signal timer_resumed

var max_time: float = 30.0
var current_time: float = 30.0
var is_running: bool = false
var is_paused: bool = false

func start(clue_difficulty: int, player_modifiers: Dictionary):
    max_time = _calculate_max_time(clue_difficulty, player_modifiers)
    current_time = max_time
    is_running = true
    is_paused = false

func _calculate_max_time(difficulty: int, modifiers: Dictionary) -> float:
    var base = 30.0
    match difficulty:
        1: base = 45.0
        2: base = 40.0
        3: base = 30.0
        4: base = 25.0
        5: base = 20.0

    # Apply modifiers
    base += modifiers.get("timer_bonus", 0)
    base *= modifiers.get("timer_multiplier", 1.0)

    # Accessibility
    if ConfigLoader.get_setting("accessibility.extended_timer"):
        base *= 1.5

    return base

func _process(delta: float):
    if not is_running or is_paused:
        return

    current_time -= delta

    # Emit warnings at thresholds
    var ratio = current_time / max_time
    if ratio <= 0.5 and ratio > 0.49:
        timer_warning.emit(0.5)
    elif ratio <= 0.25 and ratio > 0.24:
        timer_warning.emit(0.25)
    elif ratio <= 0.10 and ratio > 0.09:
        timer_warning.emit(0.10)

    if current_time <= 0:
        current_time = 0
        is_running = false
        timer_expired.emit()
```

### 3.3 Chain Detection System

**Responsibility:** Identify when solved letters form valid words, validate 
against dictionary, and apply appropriate bonuses.

```gdscript
# ChainDetector.gd
class_name ChainDetector

const DICTIONARY_PATH = "res://data/dictionaries/"

var dictionary: Dictionary = {}  # word -> {length, frequency}
var trie_root: Dictionary = {}   # Prefix tree for fast lookup

func _init():
    _load_dictionary()
    _build_trie()

func detect_chains(grid_state: Dictionary) -> Array:
    var chains = []
    var size = grid_state.size
    var cells = grid_state.cells

    # Check horizontal words
    for y in range(size):
        var current_word = ""
        var current_cells = []
        for x in range(size):
            var cell = _get_cell(cells, x, y)
            if cell.type == "letter" and cell.solved:
                current_word += cell.letter
                current_cells.append({"x": x, "y": y})
            else:
                # Word break — check if valid
                if current_word.length() >= 3 and _is_valid_word(current_word):
                    chains.append({
                        "word": current_word,
                        "cells": current_cells.duplicate(),
                        "direction": "horizontal",
                        "length": current_word.length()
                    })
                current_word = ""
                current_cells.clear()
        # Check end of row
        if current_word.length() >= 3 and _is_valid_word(current_word):
            chains.append({
                "word": current_word,
                "cells": current_cells.duplicate(),
                "direction": "horizontal",
                "length": current_word.length()
            })

    # Check vertical words (same logic, swap x/y)
    for x in range(size):
        var current_word = ""
        var current_cells = []
        for y in range(size):
            var cell = _get_cell(cells, x, y)
            if cell.type == "letter" and cell.solved:
                current_word += cell.letter
                current_cells.append({"x": x, "y": y})
            else:
                if current_word.length() >= 3 and _is_valid_word(current_word):
                    chains.append({
                        "word": current_word,
                        "cells": current_cells.duplicate(),
                        "direction": "vertical",
                        "length": current_word.length()
                    })
                current_word = ""
                current_cells.clear()
        if current_word.length() >= 3 and _is_valid_word(current_word):
            chains.append({
                "word": current_word,
                "cells": current_cells.duplicate(),
                "direction": "vertical",
                "length": current_word.length()
            })

    return chains

func _is_valid_word(word: String) -> bool:
    word = word.to_upper()
    return dictionary.has(word)

func _build_trie():
    for word in dictionary.keys():
        var node = trie_root
        for char in word:
            if not node.has(char):
                node[char] = {}
            node = node[char]
        node["_end"] = true

# Fast prefix check for autocomplete/hints
func is_valid_prefix(prefix: String) -> bool:
    var node = trie_root
    for char in prefix.to_upper():
        if not node.has(char):
            return false
        node = node[char]
    return true
```

**Dictionary Requirements:**
- 100,000+ English words (Scrabble dictionary + common proper nouns)
- Load time: <500ms at game start
- Memory: ~20MB
- Update mechanism: Monthly patches with community submissions

### 3.4 Save/Load System

**Responsibility:** Persist entire game state to disk, handle versioning, 
cloud sync (optional), and corruption recovery.

```gdscript
# SaveManager.gd — Autoload singleton
class_name SaveManager

const SAVE_DIR = "user://saves/"
const SAVE_EXTENSION = ".wsg"
const CURRENT_VERSION = "1.0.0"
const MAX_BACKUPS = 5

signal save_completed(success: bool, path: String)
signal load_completed(success: bool, state: Dictionary)
signal auto_save_triggered

var current_save_path: String = ""
var is_saving: bool = false

func _init():
    DirAccess.make_dir_recursive_absolute(SAVE_DIR)

# Main save function — serializes entire GameState
func save_game(slot_name: String = "auto") -> bool:
    if is_saving:
        push_warning("Save already in progress")
        return false

    is_saving = true

    var save_data = {
        "version": CURRENT_VERSION,
        "timestamp": Time.get_datetime_string_from_system(true),
        "game_state": GameState.serialize()
    }

    var path = SAVE_DIR + slot_name + SAVE_EXTENSION
    var json_string = JSON.stringify(save_data, "	", false)

    # Write to temp file first (atomic save)
    var temp_path = path + ".tmp"
    var file = FileAccess.open(temp_path, FileAccess.WRITE)
    if file == null:
        is_saving = false
        save_completed.emit(false, path)
        return false

    file.store_string(json_string)
    file.close()

    # Atomic rename
    var err = DirAccess.rename_absolute(temp_path, path)
    if err != OK:
        is_saving = false
        save_completed.emit(false, path)
        return false

    # Create backup rotation
    _rotate_backups(slot_name)

    current_save_path = path
    is_saving = false
    save_completed.emit(true, path)
    return true

func load_game(slot_name: String = "auto") -> Dictionary:
    var path = SAVE_DIR + slot_name + SAVE_EXTENSION

    if not FileAccess.file_exists(path):
        # Try to recover from backup
        path = _get_latest_backup(slot_name)
        if path.is_empty():
            load_completed.emit(false, {})
            return {}

    var file = FileAccess.open(path, FileAccess.READ)
    if file == null:
        load_completed.emit(false, {})
        return {}

    var json_string = file.get_as_text()
    file.close()

    var json = JSON.new()
    var err = json.parse(json_string)
    if err != OK:
        load_completed.emit(false, {})
        return {}

    var save_data = json.data

    # Version migration
    if save_data.version != CURRENT_VERSION:
        save_data = _migrate_save(save_data)

    GameState.deserialize(save_data.game_state)
    current_save_path = path

    load_completed.emit(true, save_data.game_state)
    return save_data.game_state

# Auto-save every 60 seconds during active runs
func _on_auto_save_timer_timeout():
    if GameState.current_run and GameState.current_run.run_status == "in_progress":
        auto_save_triggered.emit()
        save_game("auto")

# Version migration handler
func _migrate_save(save_data: Dictionary) -> Dictionary:
    var from_version = save_data.version

    # Migration: 0.9.x -> 1.0.0
    if from_version.begins_with("0.9"):
        # Add new fields with defaults
        if not save_data.game_state.has("daily_challenges"):
            save_data.game_state.daily_challenges = {
                "last_completed_date": "",
                "completion_history": []
            }

    save_data.version = CURRENT_VERSION
    return save_data
```

**Save File Specs:**
- Format: JSON (human-readable, debuggable)
- Size: <1MB per save
- Location: Platform-appropriate user directory
- Auto-save: Every 60 seconds during runs, on every hub interaction
- Backups: Keep 5 rotating backups per slot
- Cloud sync: Optional — hash-based conflict resolution

### 3.5 Event Bus System

**Responsibility:** Decouple all game systems via type-safe signals.

```gdscript
# EventBus.gd — Autoload singleton
class_name EventBus

# === COMBAT EVENTS ===
signal combat_started(enemy_id: String, clue_id: String)
signal combat_ended(result: Dictionary)  # {victory, damage_dealt, damage_taken, time_used}
signal letter_solved(cell_position: Vector2, letter: String, ink_drops: int)
signal answer_submitted(answer: String, is_correct: bool, attempt_number: int)
signal timer_expired
signal enemy_defeated(enemy_id: String, rewards: Dictionary)
signal player_damaged(amount: int, source: String)
signal player_healed(amount: int, source: String)

# === GRID EVENTS ===
signal grid_generated(grid_state: Dictionary)
signal cell_revealed(position: Vector2, cell_type: String)
signal player_moved(from: Vector2, to: Vector2)
signal chain_detected(chain: Dictionary)
signal chain_activated(chain: Dictionary, effect: Dictionary)
signal grid_completed(score: int, time_seconds: float)

# === PROGRESSION EVENTS ===
signal ink_drops_earned(amount: int, source: String)
signal ink_drops_spent(amount: int, item: String)
signal level_up(new_level: int, rewards: Dictionary)
signal achievement_unlocked(achievement_id: String)
signal vocabulary_node_purchased(tree_id: String, node_id: String)
signal tome_equipped(tome_id: String, slot: int)
signal tome_unequipped(tome_id: String, slot: int)

# === META EVENTS ===
signal run_started(run_id: String, difficulty: String, grid_size: int)
signal run_ended(run_id: String, result: Dictionary)
signal daily_challenge_completed(date: String, score: int, rank: int)
signal settings_changed(category: String, key: String, value: Variant)

# === SYSTEM EVENTS ===
signal game_saved(slot: String, success: bool)
signal game_loaded(slot: String, success: bool)
signal error_occurred(error_code: String, message: String, context: Dictionary)
signal analytics_event(event_name: String, parameters: Dictionary)
```

---

## 4. API CONTRACTS

### 4.1 Daily Challenge Server API

**Base URL:** `https://api.wordsmithsgambit.com/v1`

**Authentication:** HMAC-SHA256 of player_id + timestamp, signed with purchase key.

```
GET /daily-challenge/today
Response:
{
  "date": "2026-07-13",
  "seed": "a1b2c3d4e5f6...",
  "grid_size": 7,
  "difficulty": "standard",
  "clue_set_hash": "sha256:abc123...",
  "expires_at": "2026-07-14T00:00:00Z"
}

POST /daily-challenge/submit
Body:
{
  "player_id": "uuid",
  "date": "2026-07-13",
  "score": 15420,
  "time_seconds": 380,
  "run_state_hash": "sha256:def456...",
  "signature": "hmac-sha256:..."
}
Response:
{
  "accepted": true,
  "rank": 23,
  "total_participants": 1247,
  "percentile": 98.2,
  "rewards": {
    "ink_drops": 500,
    "cosmetic": "daily_winner_badge"
  }
}

GET /daily-challenge/leaderboard?date=2026-07-13&limit=100
Response:
{
  "date": "2026-07-13",
  "entries": [
    {
      "rank": 1,
      "player_name": "WordMaster99",
      "score": 28400,
      "time_seconds": 245,
      "is_player": false
    },
    {
      "rank": 23,
      "player_name": "PlayerOne",
      "score": 15420,
      "time_seconds": 380,
      "is_player": true
    }
  ]
}
```

### 4.2 Purchase Validation API

```
POST /purchase/validate
Body:
{
  "purchase_key": "WSG-XXXX-XXXX-XXXX",
  "player_id": "uuid",
  "platform": "windows"
}
Response:
{
  "valid": true,
  "edition": "supporter",
  "purchase_date": "2026-07-10",
  "annual_pass_active": true,
  "annual_pass_expires": "2027-07-10"
}
```

---

## 5. TESTING STRATEGY

### 5.1 Unit Tests

```gdscript
# tests/unit/test_combat_engine.gd
class_name TestCombatEngine
extends GutTest

var combat_engine: CombatEngine

func before_each():
    combat_engine = CombatEngine.new()

func test_basic_damage_calculation():
    var result = combat_engine.calculate_damage(
        "CAT",  # 3-letter word
        {"difficulty": 1, "category": "nature"},
        {"base_hp": 25, "base_damage": 8},
        {},  # No modifiers
        1,   # First attempt
        30.0 # Full time
    )

    # 3-letter: 6 damage per letter = 18 base
    # Difficulty 1: +10% = 19.8
    # First attempt: +25% = 24.75
    # Full time: +50% = 37.125
    assert_eq(result.damage_dealt, 37)
    assert_true(result.is_correct)

func test_enemy_weakness_applied():
    var result = combat_engine.calculate_damage(
        "BALLOON",  # Has double letters
        {"difficulty": 2, "category": "nature"},
        {
            "base_hp": 50,
            "weakness": {"type": "word_property", "property": "double_letter", "bonus_multiplier": 1.5}
        },
        {},
        1,
        20.0
    )

    # Should apply 1.5x weakness multiplier
    assert_gt(result.damage_dealt, 50)  # Significantly boosted

func test_timer_expiry_damage():
    var result = combat_engine.calculate_damage(
        "CAT",
        {"difficulty": 1, "category": "nature"},
        {"base_hp": 25, "base_damage": 8},
        {},
        2,   # Second attempt
        0.0  # Timer expired
    )

    # No time bonus, not first attempt
    assert_lt(result.damage_dealt, 25)
    assert_gt(result.damage_taken, 0)  # Enemy counter-attacks
```

### 5.2 Integration Tests

```gdscript
# tests/integration/test_full_run.gd
class_name TestFullRun
extends GutTest

func test_complete_run_standard_mode():
    # Generate a 5×5 grid
    var grid = GridGenerator.generate_grid(5, 1, 1)
    assert_not_null(grid)
    assert_eq(grid.size, 5)

    # Simulate solving all letters
    var player_state = _create_test_player()
    var solved_count = 0

    for cell in grid.cells:
        if cell.type == "letter" and not cell.solved:
            var combat_result = CombatEngine.simulate_combat(
                cell.clue_id, player_state
            )
            assert_true(combat_result.is_correct)
            solved_count += 1

    # Verify grid completion
    assert_gt(solved_count, 0)
    assert_true(_validate_all_letters_solved(grid))

    # Verify run completion rewards
    var rewards = ProgressionManager.calculate_run_rewards(grid, player_state)
    assert_gt(rewards.ink_drops, 0)
    assert_gt(rewards.experience, 0)
```

### 5.3 Automated Playtest Bots

```gdscript
# tests/bots/random_bot.gd
class_name RandomBot
extends RefCounted

# Simulates a player who guesses randomly
func run_simulation(grid: Dictionary, max_attempts: int = 1000) -> Dictionary:
    var stats = {
        "letters_solved": 0,
        "letters_failed": 0,
        "total_damage_taken": 0,
        "run_completed": false,
        "turns_taken": 0
    }

    var player_state = _create_bot_player()
    var attempts = 0

    while attempts < max_attempts:
        attempts += 1

        # Find nearest unsolved letter
        var target = _find_nearest_unsolved(grid, player_state.position)
        if target == null:
            stats.run_completed = true
            break

        # Move to target
        _move_to_target(grid, player_state, target)
        stats.turns_taken += 1

        # Attempt combat with random guess
        var clue = ClueDatabase.get_clue(target.clue_id)
        var guess = _generate_random_guess(clue.answer_length)

        var result = CombatEngine.calculate_damage(
            guess, clue, target.enemy, player_state, 1, 30.0
        )

        if result.is_correct:
            stats.letters_solved += 1
            _solve_letter(grid, target)
        else:
            stats.letters_failed += 1
            stats.total_damage_taken += result.damage_taken
            player_state.current_hp -= result.damage_taken

            if player_state.current_hp <= 0:
                break  # Run ended

    return stats

# Usage: Run 10,000 simulations to find balance issues
func run_balance_simulation():
    var total_stats = {
        "runs_completed": 0,
        "avg_letters_solved": 0.0,
        "avg_damage_taken": 0.0,
        "win_rate": 0.0
    }

    for i in range(10000):
        var grid = GridGenerator.generate_grid(7, 3, 10)
        var bot = RandomBot.new()
        var result = bot.run_simulation(grid)

        if result.run_completed:
            total_stats.runs_completed += 1
        total_stats.avg_letters_solved += result.letters_solved
        total_stats.avg_damage_taken += result.total_damage_taken

    total_stats.avg_letters_solved /= 10000.0
    total_stats.avg_damage_taken /= 10000.0
    total_stats.win_rate = total_stats.runs_completed / 10000.0

    # Assert balance targets
    assert_between(total_stats.win_rate, 0.3, 0.7, "Win rate should be 30-70% for random play")
```

### 5.4 Performance Benchmarks

```gdscript
# tests/benchmarks/test_performance.gd
class_name TestPerformance
extends GutTest

func test_grid_generation_performance():
    var start_time = Time.get_ticks_msec()

    for i in range(100):
        var grid = GridGenerator.generate_grid(7, 5, 20)
        assert_not_null(grid)

    var elapsed = Time.get_ticks_msec() - start_time
    var avg_time = elapsed / 100.0

    assert_lt(avg_time, 500, "7×7 grid generation should average <500ms")

func test_chain_detection_performance():
    var grid = _create_fully_solved_grid(9)

    var start_time = Time.get_ticks_msec()

    for i in range(1000):
        var chains = ChainDetector.detect_chains(grid)
        assert_gt(chains.size(), 0)

    var elapsed = Time.get_ticks_msec() - start_time
    var avg_time = elapsed / 1000.0

    assert_lt(avg_time, 5, "Chain detection should average <5ms on 9×9 grid")
```

---

## 6. SECURITY CONSIDERATIONS

### 6.1 Save File Integrity

- **Checksum:** Every save file includes SHA-256 hash of game_state JSON
- **Tamper detection:** Load function verifies hash; mismatch = reject or warn
- **No competitive integrity needed:** Single-player game; cheating only harms the cheater
- **Daily challenges:** Server-side validation of run_state_hash prevents fake scores

### 6.2 Purchase Key Validation

- Keys are UUIDv4 format: `WSG-XXXX-XXXX-XXXX` (16 bytes, base32 encoded)
- Validation: Online check on first launch, then cached locally for 7 days
- Offline grace period: 7 days without validation before features lock
- Key revocation: Server-side blacklist for chargebacks/fraud

### 6.3 API Security

- All API requests use HTTPS only
- Rate limiting: 100 requests/minute per player_id
- HMAC signatures prevent replay attacks
- No PII stored server-side (only player_id, display_name, scores)

---

## 7. DEPLOYMENT & BUILD PIPELINE

### 7.1 CI/CD Configuration

```yaml
# .github/workflows/build.yml
name: Build & Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        platform: [windows, macos, linux, web]

    steps:
      - uses: actions/checkout@v4

      - name: Setup Godot
        uses: chickensoft-games/setup-godot@v1
        with:
          version: 4.3.0

      - name: Run Tests
        run: |
          godot --headless --script tests/runner.gd

      - name: Build ${{ matrix.platform }}
        run: |
          mkdir -p build/${{ matrix.platform }}
          godot --headless --export-release "${{ matrix.platform }}" build/${{ matrix.platform }}/

      - name: Upload Artifact
        uses: actions/upload-artifact@v4
        with:
          name: wordsmiths-gambit-${{ matrix.platform }}
          path: build/${{ matrix.platform }}/

  release:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: Download Artifacts
        uses: actions/download-artifact@v4

      - name: Create Release
        uses: softprops/action-gh-release@v1
        with:
          files: wordsmiths-gambit-*/**

      - name: Deploy to Itch.io
        uses: josephbmanley/butler-publish-itchio-action@master
        with:
          butler-api-key: ${{ secrets.BUTLER_API_KEY }}
          itch-game: wordsmiths-gambit
          itch-user: your-studio
          files: build/
```

### 7.2 Versioning Strategy

- **Semantic Versioning:** MAJOR.MINOR.PATCH
- **Major:** Breaking save format changes, new platforms
- **Minor:** New features, content packs, balance changes
- **Patch:** Bug fixes, performance improvements
- **Save migration:** Every minor version includes automatic migration path

---

## 8. PERFORMANCE BUDGETS

| Metric | Target | Max | Measurement |
|--------|--------|-----|-------------|
| Grid generation (5×5) | <50ms | <100ms | Average of 100 runs |
| Grid generation (7×7) | <200ms | <500ms | Average of 100 runs |
| Grid generation (9×9) | <500ms | <1000ms | Average of 100 runs |
| Chain detection | <2ms | <5ms | 9×9 fully solved grid |
| Combat initialization | <100ms | <200ms | From cell click to clue display |
| Save operation | <50ms | <100ms | Full state serialization + disk write |
| Load operation | <100ms | <200ms | Disk read + deserialization |
| Memory (desktop) | <200MB | <300MB | Peak during gameplay |
| Memory (web demo) | <100MB | <150MB | Peak during gameplay |
| Frame time | <16.6ms | <33.3ms | 60 FPS target, 30 FPS minimum |
| Initial load (web) | <3s | <5s | First paint to interactive |
| Build size (desktop) | <100MB | <150MB | Compressed installer |
| Build size (web) | <50MB | <75MB | Initial bundle |

---

## 9. DOCUMENT HISTORY

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1.0 | 2026-07-01 | Tech Lead | Initial draft |
| 0.2.0 | 2026-07-05 | Tech Lead | Added chain detection algorithm, save system |
| 0.3.0 | 2026-07-08 | Tech Lead | Added API contracts, testing strategy |
| 1.0.0 | 2026-07-13 | Tech Lead | Finalized for development kickoff |

---
Document Owner: Technical Director
Review Cycle: Weekly during active development
Distribution: Programming team, QA, DevOps
