# CLAUDE.md
# Wordsmith's Gambit — AI Agent Coding Standards
# Version: 1.0.0 | Date: 2026-07-13
# Purpose: Govern all Claude Code interactions with this codebase
# Rule: Every Claude session MUST read this file before editing code.
# ============================================================

## 1. PROJECT CONTEXT

**Game:** Wordsmith's Gambit — A roguelike puzzle-RPG where dungeons are 
procedural crossword grids. Built in Godot 4.3+ (GDScript) with a Phaser 3 
web demo. Sold direct-to-consumer via our own website.

**Team:** Solo developer + Claude Code as primary coding agent. No other 
programmers. Every line of code is written or reviewed by Claude.

**Economic Constraint:** Claude Max costs $200/month. The game needs to sell 
~14 copies at $15 to break even on tooling alone. Every hour of Claude time 
must produce shippable, debuggable, maintainable code.

**Philosophy:** "Every minute you spend on this document saves ten minutes 
of correcting AI-generated code." — This is the single most important file 
in the repository.

---

## 2. ABSOLUTE RULES (Never Violate)

### 2.1 No Hardcoded Content

**NEVER** embed game content (clues, enemy stats, dialogue, prices) directly 
in GDScript files. All content lives in `data/` as JSON/YAML. Game logic 
reads these files.

```gdscript
# ❌ WRONG — Hardcoded content
func get_clue():
    return "A small domesticated carnivorous mammal"  # NEVER DO THIS

# ✅ CORRECT — Data-driven
func get_clue(clue_id: String) -> Dictionary:
    return ClueDatabase.get_clue(clue_id)
```

**Why:** Claude can reason about JSON. It cannot reason about strings buried 
in code. Data-driven design allows Claude to edit content without touching 
logic, and logic without touching content.

### 2.2 No Godot Editor-Only Dependencies

**NEVER** rely on Godot editor features that cannot be recreated in code:
- No AnimationPlayer node animations (use Tween or code-based animation)
- No TileMap painted in editor (generate procedurally)
- No scene composition that requires manual node arrangement
- No resource preloading that depends on editor import settings

```gdscript
# ❌ WRONG — Editor-dependent
@onready var anim_player = $AnimationPlayer  # Requires editor setup

# ✅ CORRECT — Code-only
var tween: Tween
func animate_damage():
    tween = create_tween()
    tween.tween_property(sprite, "modulate", Color.RED, 0.2)
    tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)
```

**Why:** Claude cannot see or edit the Godot editor. All scene setup must 
be scriptable. If it can't be expressed in code, Claude can't maintain it.

### 2.3 No Binary Asset References in Code

**NEVER** reference `.png`, `.ogg`, or `.ttf` files by hardcoded path strings 
in logic code. All asset references go through a centralized AssetRegistry 
that maps logical names to paths.

```gdscript
# ❌ WRONG — Hardcoded paths
var enemy_sprite = preload("res://assets/images/enemies/anagram.png")
var sfx = preload("res://assets/audio/sfx/hit.ogg")

# ✅ CORRECT — Registry lookup
var enemy_sprite = AssetRegistry.get_texture("enemy_anagram")
var sfx = AssetRegistry.get_sfx("combat_hit")
```

**Why:** Asset paths change. Artists reorganize folders. Claude renaming 
a file in one place but missing 12 references is the #1 source of runtime 
crashes in AI-built projects.

### 2.4 No Global Mutable State (Except Autoloads)

**NEVER** use singletons or static variables for *game state* outside of the
five approved autoloads: `GameState`, `EventBus`, `SaveManager`,
`AudioManager`, `ConfigLoader`. (This corrects a contradiction between this
document and the Technical Design Doc's file structure, which listed five —
resolved 2026-08-29 in favor of the Technical Design Doc; see
`docs/design/technical_design_document.md` section 1.3.)

Static-var *data access* classes (read-mostly caches like `ClueDatabase` in
4.3, or `AssetRegistry` in `src/utils/`) are not "game state" in this rule's
sense and are fine outside the autoload list — the line is: does mutating
it change what the player is currently experiencing? If yes, it's game
state and belongs in one of the five autoloads or gets passed explicitly.

```gdscript
# ❌ WRONG — Hidden global state
static var player_hp = 100  # NEVER DO THIS

# ❌ WRONG — Node path traversal for state
var hp = get_node("/root/Main/Player").hp  # Fragile, untestable

# ✅ CORRECT — Explicit dependency injection
func _ready():
    GameState.player_hp_changed.connect(_on_hp_changed)
```

**Why:** Global state makes testing impossible and creates Heisenbugs that 
Claude cannot reproduce. Every piece of state must have a single owner and 
a clear lifecycle.

### 2.5 No Godot-Specific "Magic"

**NEVER** use Godot features that are poorly documented, have surprising 
behavior, or differ significantly from standard programming patterns:
- No `_get_property_list()` overrides for dynamic properties
- No `setget` (deprecated in Godot 4, use `@property` with explicit getters/setters)
- No `yield` (deprecated, use `await`)
- No `call_deferred` unless absolutely necessary for thread safety
- No `_process` or `_physics_process` for game logic (use timers and state machines)

```gdscript
# ❌ WRONG — Magic property
var hp: int = 100 : set = set_hp  # Confusing, hard to grep

# ✅ CORRECT — Explicit getter/setter
var _hp: int = 100

func get_hp() -> int:
    return _hp

func set_hp(value: int) -> void:
    var old = _hp
    _hp = clamp(value, 0, max_hp)
    if _hp != old:
        EventBus.player_hp_changed.emit(_hp, old)
```

### 2.6 No Nested Callback Hell

**NEVER** chain more than 2 `await` or callback layers. If you need 3+, 
refactor into a state machine or sequential method.

```gdscript
# ❌ WRONG — Callback pyramid
func start_combat():
    await show_clue()
    await wait_for_input()
    await validate_answer()
    await play_animation()
    await apply_damage()
    await check_defeat()
    await end_combat()

# ✅ CORRECT — State machine
enum CombatState { REVEAL, INPUT, VALIDATE, RESOLVE, END }
var state: CombatState = CombatState.REVEAL

func _process_combat():
    match state:
        CombatState.REVEAL:
            _state_reveal()
        CombatState.INPUT:
            _state_input()
        # ... etc
```

**Why:** Claude loses track of nested async flow. State machines are 
explicit, testable, and Claude can reason about them as text.

---

## 3. NAMING CONVENTIONS

### 3.1 Files

| Type | Pattern | Example |
|------|---------|---------|
| GDScript classes | PascalCase, descriptive | `CombatEngine.gd` |
| Scene files | PascalCase, matches script | `CombatScene.tscn` |
| Resource files | snake_case | `game_config.tres` |
| JSON data | snake_case, plural | `clues_master.json` |
| Shaders | snake_case | `grid_effects.gdshader` |
| Test files | `test_` + system name | `test_combat_engine.gd` |
| Tool scripts | `tool_` + purpose | `tool_clue_validator.py` |

### 3.2 GDScript Code

| Element | Convention | Example |
|---------|-----------|---------|
| Classes | PascalCase | `class_name GridGenerator` |
| Constants | UPPER_SNAKE_CASE | `const MAX_GRID_SIZE = 9` |
| Variables | snake_case | `var current_hp: int` |
| Private vars | underscore prefix | `var _internal_counter: int` |
| Functions | snake_case | `func calculate_damage()` |
| Private funcs | underscore prefix | `func _validate_input()` |
| Signals | snake_case, past tense | `signal combat_ended` |
| Enums | PascalCase for type, UPPER for values | `enum CellType { BLACK, LETTER }` |
| Type hints | Always use | `func add(a: int, b: int) -> int:` |

### 3.3 JSON Data Keys

| Element | Convention | Example |
|---------|-----------|---------|
| IDs | snake_case, prefixed | `clue_0001`, `enemy_anagram_01` |
| Categories | snake_case | `"category": "nature"` |
| Booleans | Prefixed with is/has/can | `"is_boss": true` |
| Timestamps | ISO 8601 UTC | `"created_at": "2026-07-13T14:30:00Z"` |

### 3.4 Scene Node Names

| Pattern | Example | Purpose |
|---------|---------|---------|
| PascalCase for containers | `CombatUI`, `GridContainer` | Major UI sections |
| snake_case for leaves | `hp_label`, `submit_button` | Individual elements |
| %UniqueName for script refs | `%HpLabel`, `%SubmitButton` | Access from code |

---

## 4. CODE STRUCTURE PATTERNS

### 4.1 Class Template

Every GDScript class must follow this structure:

```gdscript
#============================================================================
# ClassName.gd
# Brief description of what this class does (1-2 sentences)
# Dependencies: List other classes this depends on
# Events: List signals this class emits
#============================================================================

class_name ClassName
extends Node  # or appropriate base class

#----------------------------------------------------------------------------
# CONSTANTS
#----------------------------------------------------------------------------
const MAX_VALUE: int = 100
const DEFAULT_TIMEOUT: float = 30.0

#----------------------------------------------------------------------------
# SIGNALS
#----------------------------------------------------------------------------
signal state_changed(new_state: int)
signal operation_completed(result: Dictionary)

#----------------------------------------------------------------------------
# EXPORT VARIABLES (if any)
#----------------------------------------------------------------------------
@export var debug_mode: bool = false

#----------------------------------------------------------------------------
# PUBLIC VARIABLES
#----------------------------------------------------------------------------
var is_active: bool = false
var current_state: int = STATE_IDLE

#----------------------------------------------------------------------------
# PRIVATE VARIABLES
#----------------------------------------------------------------------------
var _timer: Timer
var _cached_data: Dictionary = {}

#----------------------------------------------------------------------------
# ONREADY VARIABLES
#----------------------------------------------------------------------------
@onready var _event_bus = EventBus

#----------------------------------------------------------------------------
# BUILT-IN VIRTUAL METHODS
#----------------------------------------------------------------------------
func _ready():
    _initialize()
    _connect_signals()

func _process(delta: float):
    if is_active:
        _update(delta)

func _exit_tree():
    _cleanup()

#----------------------------------------------------------------------------
# PUBLIC METHODS
#----------------------------------------------------------------------------
func start_operation(params: Dictionary) -> bool:
    if is_active:
        push_warning("Operation already in progress")
        return false

    is_active = true
    _setup_operation(params)
    return true

func stop_operation():
    is_active = false
    _cleanup_operation()

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------
func _initialize():
    _timer = Timer.new()
    _timer.one_shot = true
    add_child(_timer)

func _connect_signals():
    _timer.timeout.connect(_on_timer_timeout)
    EventBus.some_event.connect(_on_some_event)

func _update(delta: float):
    # Main logic update
    pass

func _setup_operation(params: Dictionary):
    # Implementation
    pass

func _cleanup_operation():
    # Implementation
    pass

func _cleanup():
    if _timer:
        _timer.queue_free()

#----------------------------------------------------------------------------
# SIGNAL HANDLERS
#----------------------------------------------------------------------------
func _on_timer_timeout():
    operation_completed.emit({"status": "timeout"})
    is_active = false

func _on_some_event(data: Dictionary):
    # Handle external event
    pass
```

### 4.2 State Machine Pattern

For any system with 3+ states, use explicit state machines:

```gdscript
#============================================================================
# CombatStateMachine.gd
# Manages combat encounter flow from clue reveal to resolution
#============================================================================

class_name CombatStateMachine
extends Node

enum State {
    IDLE,
    REVEAL_CLUE,
    AWAIT_INPUT,
    VALIDATE_ANSWER,
    APPLY_DAMAGE,
    ENEMY_ATTACK,
    CHECK_RESOLUTION,
    VICTORY,
    DEFEAT,
    CLEANUP
}

signal state_changed(old_state: State, new_state: State)
signal combat_ended(result: CombatResult)

var current_state: State = State.IDLE
var _state_data: Dictionary = {}  # Context shared across states

func transition_to(new_state: State, context: Dictionary = {}):
    var old_state = current_state

    # Exit current state
    _exit_state(old_state)

    # Update state
    current_state = new_state
    _state_data.merge(context, true)

    # Enter new state
    _enter_state(new_state)

    state_changed.emit(old_state, new_state)

func _enter_state(state: State):
    match state:
        State.REVEAL_CLUE:
            _enter_reveal_clue()
        State.AWAIT_INPUT:
            _enter_await_input()
        State.VALIDATE_ANSWER:
            _enter_validate_answer()
        # ... etc

func _exit_state(state: State):
    match state:
        State.AWAIT_INPUT:
            _exit_await_input()  # Stop timer, lock input
        # ... etc

func _enter_reveal_clue():
    var clue = ClueDatabase.get_clue(_state_data.clue_id)
    EventBus.combat_started.emit(_state_data.enemy_id, _state_data.clue_id)
    # After animation, auto-transition
    await get_tree().create_timer(1.0).timeout
    transition_to(State.AWAIT_INPUT)

func _enter_await_input():
    TimerSystem.start(_state_data.clue_difficulty, _state_data.player_modifiers)
    TimerSystem.timer_expired.connect(_on_timer_expired, CONNECT_ONE_SHOT)

func _on_timer_expired():
    if current_state == State.AWAIT_INPUT:
        transition_to(State.VALIDATE_ANSWER, {"answer": "", "timed_out": true})
```

### 4.3 Data Access Pattern

All database/content access goes through typed wrapper classes:

```gdscript
#============================================================================
# ClueDatabase.gd
# Typed wrapper around clues_master.json
#============================================================================

class_name ClueDatabase
extends RefCounted

const CLUES_PATH = "res://data/clues/clues_master.json"

static var _clues: Dictionary = {}
static var _initialized: bool = false

static func _static_init():
    _load_clues()

static func _load_clues():
    var file = FileAccess.open(CLUES_PATH, FileAccess.READ)
    if file == null:
        push_error("Failed to load clues database")
        return

    var json = JSON.new()
    var err = json.parse(file.get_as_text())
    if err != OK:
        push_error("Failed to parse clues JSON")
        return

    var data = json.data
    for clue in data.clues:
        _clues[clue.id] = clue

    _initialized = true

static func get_clue(clue_id: String) -> Dictionary:
    if not _initialized:
        _load_clues()

    if not _clues.has(clue_id):
        push_warning("Clue not found: " + clue_id)
        return _get_fallback_clue()

    return _clues[clue_id].duplicate(true)  # Deep copy to prevent mutation

static func get_random_clue(length: int, difficulty: int, category: String = "") -> Dictionary:
    var candidates = []

    for clue_id in _clues:
        var clue = _clues[clue_id]
        if clue.answer_length == length and clue.difficulty == difficulty:
            if category.is_empty() or clue.category == category:
                candidates.append(clue)

    if candidates.is_empty():
        return _get_fallback_clue()

    return candidates.pick_random().duplicate(true)

static func _get_fallback_clue() -> Dictionary:
    return {
        "id": "clue_fallback",
        "answer": "CAT",
        "answer_length": 3,
        "clue_text": "A common three-letter animal",
        "difficulty": 1,
        "category": "nature"
    }
```

---

## 5. ERROR HANDLING

### 5.1 Error Severity Levels

| Level | Use When | Action |
|-------|----------|--------|
| `push_error()` | Unrecoverable bug, data corruption | Log, show error screen, offer restart |
| `push_warning()` | Unexpected but recoverable | Log, continue with fallback |
| `print()` | Debug info only | Remove before release |
| Silent fallback | Missing optional content | Use default, log once |

### 5.2 Error Handling Pattern

```gdscript
func load_player_profile() -> Dictionary:
    var path = SaveManager.SAVE_DIR + "profile.json"

    if not FileAccess.file_exists(path):
        push_warning("No save file found, creating new profile")
        return _create_default_profile()

    var file = FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("Cannot open save file: " + path)
        return _create_default_profile()  # Fallback, don't crash

    var json = JSON.new()
    var err = json.parse(file.get_as_text())
    if err != OK:
        push_error("Corrupted save file, using default")
        return _create_default_profile()

    var data = json.data

    # Validate required fields
    if not data.has("player_id") or not data.has("player_level"):
        push_warning("Save file missing required fields, merging with defaults")
        data = _merge_with_defaults(data)

    return data
```

### 5.3 Never Crash the Game

Every system must have a graceful degradation path:
- Missing asset → colored rectangle + error log
- Missing sound → silence + error log
- Corrupted save → new save + error log + notify player
- Network failure → offline mode + queue for retry
- Invalid clue ID → fallback clue (CAT, 3 letters, nature)

---

## 6. TESTING REQUIREMENTS

### 6.1 Every New Feature Needs Tests

Before marking any feature "complete," the following must exist:

1. **Unit tests** for all public methods (Gut framework)
2. **Integration test** demonstrating the feature works end-to-end
3. **Bot simulation** running 100+ randomized scenarios
4. **Performance benchmark** if the feature runs every frame or every combat

### 6.2 Test-Driven Development for Claude

When Claude implements a new feature, follow this order:

```
1. Write test file with failing tests
2. Run tests → confirm they fail
3. Implement feature
4. Run tests → confirm they pass
5. Run bot simulation → confirm no edge case crashes
6. Commit
```

### 6.3 Test File Template

```gdscript
# tests/unit/test_[system_name].gd
class_name Test[SystemName]
extends GutTest

var [system_instance]: [SystemClassName]

func before_each():
    [system_instance] = [SystemClassName].new()
    # Setup test fixtures

func after_each():
    [system_instance].free()

func test_[scenario]_[expected_result]():
    # Arrange
    var input = _create_test_fixture()

    # Act
    var result = [system_instance].[method](input)

    # Assert
    assert_eq(result, expected_value, "Descriptive failure message")
    assert_true(condition, "Another assertion")

func test_[edge_case]():
    # Test boundary conditions
    pass

# Helper methods
func _create_test_fixture() -> Dictionary:
    return {
        # Minimal valid data for testing
    }
```

---

## 7. PERFORMANCE GUIDELINES

### 7.1 GDScript Performance Rules

| Rule | Rationale |
|------|-----------|
| Cache node references in `@onready` | `get_node()` is expensive, don't call in `_process` |
| Use `Dictionary` for lookups, not `Array.find()` | O(1) vs O(n) |
| Pre-allocate arrays with size hint | `var arr: Array = []` → `arr.resize(expected_size)` |
| Avoid string concatenation in loops | Use `StringBuilder` pattern or array join |
| Use `call_deferred` only for thread safety | Not for "fixing" race conditions you don't understand |
| Pool objects that are created/destroyed frequently | Reuse combat UI elements, don't recreate |
| Use `await` sparingly | Each `await` creates a coroutine; 100+ = memory pressure |
| Prefer `match` over `if/elif` chains | Cleaner, slightly faster for enums |
| Use `const` for values that never change | Compile-time optimization |

### 7.2 Memory Management

```gdscript
# ❌ WRONG — Memory leak
tween = create_tween()
tween.tween_callback(func(): print("done"))
# tween never freed if scene changes

# ✅ CORRECT — Proper cleanup
var _active_tweens: Array[Tween] = []

func animate():
    var tween = create_tween()
    _active_tweens.append(tween)
    tween.finished.connect(func(): _active_tweens.erase(tween))
    tween.tween_property(...)

func _exit_tree():
    for tween in _active_tweens:
        if is_instance_valid(tween):
            tween.kill()
    _active_tweens.clear()
```

---

## 8. DOCUMENTATION STANDARDS

### 8.1 Code Comments

```gdscript
# Single-line comment for simple explanations
var hp: int = 100  # Current health points, 0 = defeat

# Multi-line comment for complex logic.
# Explain WHY, not WHAT. The code tells you what.
func complex_algorithm():
    # We use backtracking here because constraint propagation
    # alone fails on 15% of 9x9 grids (measured in benchmarks).
    pass
```

### 8.2 Function Documentation

Every public function must have a docstring:

```gdscript
## Calculates damage dealt in a combat encounter.
##
## [param answer] The player's submitted answer
## [param clue] The clue data dictionary
## [param enemy] The enemy data dictionary
## [param player_state] Current player state dictionary
## [param attempt_number] Which attempt this is (1 = first)
## [param time_remaining] Seconds left on timer
## [return] Dictionary with damage_dealt, damage_taken, is_correct, etc.
## [note] Damage formula: base * difficulty * first_attempt * time * category * tome * weakness
func calculate_damage(
    answer: String,
    clue: Dictionary,
    enemy: Dictionary,
    player_state: Dictionary,
    attempt_number: int,
    time_remaining: float
) -> Dictionary:
```

### 8.3 Architecture Decision Records (ADRs)

For every significant technical decision, create a file in `docs/adr/`:

```
docs/adr/001-why-godot-over-unity.md
docs/adr/002-json-over-sqlite-for-saves.md
docs/adr/003-procedural-vs-handcrafted-grids.md
```

Template:
```markdown
# ADR-XXX: [Title]

## Status
Accepted | Proposed | Rejected

## Context
What problem are we solving?

## Decision
What did we decide?

## Consequences
Positive: ...
Negative: ...

## Alternatives Considered
- Option A: ... (rejected because ...)
- Option B: ... (rejected because ...)
```

---

## 9. CLAUDE-SPECIFIC INSTRUCTIONS

### 9.1 Before Starting Any Task

1. Read this file (CLAUDE.md) — you are doing this now. Good.
2. Read the relevant Design Doc section (`docs/design/`)
3. Read the relevant Technical Spec section
4. Check if tests exist for the system you are modifying
5. Run existing tests to establish baseline

### 9.2 When Implementing a New Feature

1. **Start with the data structure** — Define the JSON schema first
2. **Write the test** — Create failing test before implementation
3. **Implement the logic** — Follow class template and state machine patterns
4. **Wire up the events** — Connect to EventBus, never direct node references
5. **Add error handling** — Every external input validated, every failure graceful
6. **Run tests** — All must pass
7. **Run bot simulation** — 100+ random scenarios, zero crashes
8. **Update documentation** — Docstrings, ADR if architectural

### 9.3 When Fixing a Bug

1. **Write a test that reproduces the bug** — This test must fail before fix
2. **Fix the bug** — Minimal change, don't refactor unrelated code
3. **Run the test** — Must pass
4. **Run all tests** — No regressions
5. **Run bot simulation** — 1000 scenarios, zero crashes
6. **Document the fix** — Comment explaining the edge case

### 9.4 When Refactoring

1. **Ensure test coverage >80%** for the system being refactored
2. **Refactor in small steps** — One method at a time, commit between steps
3. **Never change behavior and structure in the same commit**
4. **Run tests after every commit**
5. **Performance benchmark before/after** — Must not regress

### 9.5 Forbidden Refactors

**NEVER** do these without explicit human approval:
- Change save file format version
- Rename EventBus signals (breaks all subscribers)
- Remove fallback/default behavior
- Change grid generation algorithm (affects all existing seeds)
- Modify damage formula constants
- Remove or rename JSON data keys

### 9.6 Code Review Checklist (Self-Review Before Commit)

- [ ] No hardcoded content
- [ ] No editor-only dependencies
- [ ] No hardcoded asset paths
- [ ] No new global mutable state
- [ ] No Godot magic features
- [ ] No nested callback hell (>2 layers)
- [ ] All public methods have docstrings
- [ ] All functions have type hints
- [ ] Error handling for all external inputs
- [ ] Graceful degradation for all failure modes
- [ ] Tests written and passing
- [ ] Bot simulation passing (100+ runs, 0 crashes)
- [ ] Performance benchmark run (no regressions)
- [ ] No `print()` statements left in code
- [ ] ADR created if architectural decision

---

## 10. PRIOR ART & REFERENCES

### 10.1 Games to Study

| Game | What to Learn | File to Review |
|------|--------------|----------------|
| Slay the Spire | Roguelike progression, card combat balance | `docs/reference/sts_combat.md` |
| Into the Breach | Perfect information, puzzle combat design | `docs/reference/itb_design.md` |
| Baba Is You | Word-as-mechanic design philosophy | `docs/reference/baba_is_you.md` |
| Wordle | Daily habit formation, social sharing | `docs/reference/wordle_growth.md` |
| Crosswords (NYT) | Clue quality, difficulty curve | `docs/reference/nyt_crossword.md` |

### 10.2 Code Patterns to Follow

| Pattern | Source | Location in Our Code |
|---------|--------|----------------------|
| Event Bus | Godot best practices | `src/autoload/EventBus.gd` |
| State Machine | Game Programming Patterns | `src/core/combat/CombatStateMachine.gd` |
| Object Pool | GDQuest tutorials | `src/utils/ObjectPool.gd` |
| Save System | HeartBeast RPG tutorial | `src/autoload/SaveManager.gd` |
| Grid Generation | Constraint satisfaction | `src/core/grid/GridGenerator.gd` |

### 10.3 Anti-Patterns to Avoid

| Anti-Pattern | Why It is Bad | Our Alternative |
|-------------|-------------|-----------------|
| Godot's built-in `_input()` for UI | Unreliable, hard to test | Custom InputManager with EventBus |
| Scene inheritance for variations | Fragile, hard to refactor | Data-driven scene composition |
| `preload()` in tool scripts | Crashes editor | `load()` with null checks |
| Circular dependencies between scenes | Runtime crashes | EventBus decoupling |
| `_ready()` doing heavy initialization | Freezes frame | Deferred initialization with loading screen |

---

## 11. COMMIT MESSAGE CONVENTIONS

Follow conventional commits:

```
[type]([scope]): [description]

[body]

[footer]
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `test`: Adding or updating tests
- `docs`: Documentation only
- `refactor`: Code change that neither fixes a bug nor adds a feature
- `perf`: Performance improvement
- `data`: Content data changes (clues, enemies, etc.)
- `chore`: Build process, dependencies, tooling

Examples:
```
feat(combat): add chain combo system with 8 effect tiers

Implements the full chain detection and activation system.
- ChainDetector identifies valid words in solved grid
- ChainEffects applies bonuses based on word length
- 8 tiers from +20% damage to row/column clear

Closes #42
```

```
fix(grid): prevent unsolvable grids by validating path before accepting

GridGenerator now runs BFS pathfinding after word placement.
If no path from entrance to exit exists, it retries with
a different template instead of returning an invalid grid.

Fixes #57
```

---

## 12. COMMUNICATION PROTOCOL

### 12.1 When Claude Is Uncertain

If you (Claude) encounter any of these situations, **STOP and ask the human**:

1. The design doc and technical spec contradict each other
2. A requested change would violate an Absolute Rule
3. You are unsure if a Godot feature works the way you think it does
4. The change affects save file format or EventBus signals
5. You are about to delete or significantly refactor >200 lines of code
6. A test is failing and you cannot determine why after 3 attempts
7. The request seems to introduce a security vulnerability
8. You are asked to implement something not in the design doc

### 12.2 When Providing Code

Always include:
1. The full file path
2. A brief explanation of what the code does and why
3. Any assumptions made
4. How to test it
5. What files it depends on

### 12.3 When Suggesting Architecture Changes

Always provide:
1. The problem with current architecture
2. The proposed solution
3. Migration path (how to get from A to B)
4. Risk assessment (what could break)
5. Performance impact
6. Human approval required before implementation

---

## 13. APPENDIX: COMMON CLAUDE MISTAKES TO AVOID

### 13.1 GDScript Specific

| Mistake | Why It Happens | Prevention |
|---------|---------------|------------|
| Forgetting `self.` for signal connections | Python habit | Always use `self.signal.connect()` |
| Using `==` for float comparison | General programming | Use `is_equal_approx()` for floats |
| Not freeing Tween/Timer objects | Assumes GC handles it | Track in array, free in `_exit_tree()` |
| `preload()` with variable paths | Thinks it is like Python import | Only `preload()` with string literals |
| Modifying arrays while iterating | Common bug | Iterate over copy: `for item in arr.duplicate()` |
| Confusing `Dictionary.keys()` return type | GDScript quirk | Always cast: `var keys: Array = dict.keys()` |

### 13.2 Game Development Specific

| Mistake | Why It Happens | Prevention |
|---------|---------------|------------|
| Frame-dependent logic | Forgetting delta | Always multiply by `delta` in `_process` |
| Hardcoded screen coordinates | Assuming 1920x1080 | Use `get_viewport().size` and anchors |
| Not handling window resize | Desktop focus | Connect `size_changed` signal |
| Blocking the main thread | Synchronous file I/O | Use `FileAccess` async or `Thread` |
| Saving during gameplay | Not using auto-save timer | Save only on state changes or timer, not every frame |

### 13.3 AI-Generated Code Specific

| Mistake | Why It Happens | Prevention |
|---------|---------------|------------|
| Hallucinated Godot APIs | Training data cutoff | Always verify API in Godot docs before using |
| Over-engineering simple features | Trying to be thorough | Follow YAGNI — if design doc does not ask for it, do not build it |
| Inconsistent naming within a file | Context window limits | Reference the Naming Conventions section |
| Missing null checks | Assuming happy path | Every external input gets validated |
| Copy-paste errors across similar systems | Pattern matching | Review diffs carefully, especially copied blocks |
| Forgetting to emit signals | Focused on logic | Check EventBus section for required signals |

---

## 14. DOCUMENT HISTORY

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1.0 | 2026-07-01 | Tech Lead | Initial draft, Absolute Rules defined |
| 0.2.0 | 2026-07-05 | Tech Lead | Added State Machine pattern, Error Handling |
| 0.3.0 | 2026-07-08 | Tech Lead | Added Testing Requirements, Performance Guidelines |
| 0.4.0 | 2026-07-10 | Tech Lead | Added Claude-Specific Instructions section |
| 1.0.0 | 2026-07-13 | Tech Lead | Finalized for development kickoff |
| 1.0.1 | 2026-08-29 | Claude (per human decision) | Fixed 2.4: this doc said 3 autoloads, Technical Design Doc's file structure said 5 — resolved in favor of the 5-autoload list (adds AudioManager, ConfigLoader) |

---

**Document Owner:** Technical Director  
**Review Cycle:** Updated whenever Claude makes a repeated mistake  
**Distribution:** Every Claude Code session must read this file before editing  
**Last Updated:** 2026-07-13

> "The code is the easy part. The constraints are what make it good."
