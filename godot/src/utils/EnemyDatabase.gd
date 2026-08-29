#============================================================================
# EnemyDatabase.gd
# Typed wrapper around enemies_master.json (CLAUDE.md 4.3). Also owns the
# depth/grid-size stat scaling from Design Doc 4.4, so combat and grid code
# never re-derive it.
# Dependencies: ConfigLoader, Constants
# Events: none
#============================================================================

class_name EnemyDatabase
extends RefCounted

#----------------------------------------------------------------------------
# PRIVATE VARIABLES
#----------------------------------------------------------------------------
static var _enemies: Dictionary = {}
static var _regular_ids: Array[String] = []
static var _boss_ids: Array[String] = []
static var _initialized: bool = false

#----------------------------------------------------------------------------
# PUBLIC METHODS
#----------------------------------------------------------------------------

## Returns the enemy definition for [param enemy_id], or a safe fallback if
## the id is unknown. Deep copy - safe to mutate.
static func get_enemy(enemy_id: String) -> Dictionary:
	_ensure_loaded()
	if not _enemies.has(enemy_id):
		push_warning("EnemyDatabase: enemy not found: %s" % enemy_id)
		return get_fallback_enemy()
	return _enemies[enemy_id].duplicate(true)

## Ids of all non-boss enemies, in file order.
static func get_regular_ids() -> Array[String]:
	_ensure_loaded()
	return _regular_ids.duplicate()

## Ids of all bosses, in file order.
static func get_boss_ids() -> Array[String]:
	_ensure_loaded()
	return _boss_ids.duplicate()

static func is_boss(enemy_id: String) -> bool:
	_ensure_loaded()
	return _boss_ids.has(enemy_id)

## Builds the runtime combat state for an encounter: the enemy definition
## with `current_hp` / `max_hp` / `damage` resolved for this dungeon depth and
## grid size.
##
## Design Doc 4.4: base HP = 20 + (depth * 5) + (grid_size * 2),
## base damage = 5 + (depth * 2). The per-enemy `scaling` block overrides the
## per-depth rates so individual enemies can scale differently.
static func build_encounter(enemy_id: String, dungeon_depth: int, grid_size: int) -> Dictionary:
	var enemy := get_enemy(enemy_id)
	var config: Dictionary = ConfigLoader.load_json(Constants.GAME_CONFIG_PATH)
	var scaling_cfg: Dictionary = config.get("difficulty_scaling", {})
	var enemy_scaling: Dictionary = enemy.get("scaling", {})

	var hp_per_depth: int = int(enemy_scaling.get("hp_per_depth", scaling_cfg.get("hp_per_depth", 5)))
	var dmg_per_depth: int = int(enemy_scaling.get("damage_per_depth", scaling_cfg.get("damage_per_depth", 2)))
	var hp_per_size: int = int(scaling_cfg.get("hp_per_grid_size", 2))

	var max_hp: int = int(enemy.get("base_hp", 20)) + hp_per_depth * dungeon_depth + hp_per_size * grid_size
	var damage: int = int(enemy.get("base_damage", 5)) + dmg_per_depth * dungeon_depth

	enemy["max_hp"] = max_hp
	enemy["current_hp"] = max_hp
	enemy["damage"] = damage
	enemy["dungeon_depth"] = dungeon_depth
	return enemy

## Whether this enemy's special ability is unlocked at [param dungeon_depth].
## Design Doc 4.4: abilities unlock at depths 3, 6, 10, 15.
static func ability_unlocked(enemy: Dictionary, dungeon_depth: int) -> bool:
	var ability = enemy.get("special_ability", null)
	if ability == null or typeof(ability) != TYPE_DICTIONARY:
		return false
	return dungeon_depth >= int(ability.get("unlock_depth", 999))

static func get_fallback_enemy() -> Dictionary:
	return {
		"id": "enemy_fallback",
		"name": "Wandering Typo",
		"display_name": "Typo",
		"enemy_type": "fallback",
		"tier": 1,
		"base_hp": 20,
		"base_damage": 5,
		"weakness": null,
		"resistance": null,
		"scaling": { "hp_per_depth": 5, "damage_per_depth": 2 },
		"flavor_text": "A small mistake, wandering loose.",
	}

static func reset_cache() -> void:
	_enemies.clear()
	_regular_ids.clear()
	_boss_ids.clear()
	_initialized = false

#----------------------------------------------------------------------------
# PRIVATE METHODS
#----------------------------------------------------------------------------
static func _ensure_loaded() -> void:
	if _initialized:
		return
	_initialized = true

	var data: Dictionary = ConfigLoader.load_json(Constants.ENEMIES_PATH)

	# enemies_master.json keeps regular enemies and bosses in separate arrays
	# (Technical Design Doc 2.3). Bosses are flagged is_boss on the way in so
	# callers only have to check one field.
	for enemy in data.get("enemies", []):
		var copy: Dictionary = enemy.duplicate(true)
		copy["is_boss"] = bool(copy.get("is_boss", false))
		_enemies[String(copy.id)] = copy
		if copy["is_boss"]:
			_boss_ids.append(String(copy.id))
		else:
			_regular_ids.append(String(copy.id))

	for boss in data.get("bosses", []):
		var copy: Dictionary = boss.duplicate(true)
		copy["is_boss"] = true
		_enemies[String(copy.id)] = copy
		_boss_ids.append(String(copy.id))

	if _enemies.is_empty():
		push_error("EnemyDatabase: enemies_master.json is empty or missing")
