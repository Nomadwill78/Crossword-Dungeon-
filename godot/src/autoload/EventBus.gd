## Autoload singleton. Global signal bus so gameplay systems can communicate
## without holding direct references to each other.
extends Node

# --- Run lifecycle ---
signal run_started(run_id: String, difficulty: String, grid_size: int)
signal run_ended(run_id: String, result: Dictionary)
signal run_paused
signal run_resumed

# --- Grid / navigation ---
signal grid_generated(grid_state: Dictionary)
signal grid_completed(score: int, time_seconds: float)
signal player_moved(from_pos: Vector2i, to_pos: Vector2i)
signal player_blocked(attempted_pos: Vector2i)
signal letter_solved(pos: Vector2i, letter: String, ink_drops: int)
signal word_solved(slot_id: String, word: String, ink_drops: int)
signal bonus_claimed(pos: Vector2i, bonus: Dictionary)

# --- Combat ---
signal combat_started(enemy_id: String, clue_id: String)
signal combat_ended(result: Dictionary)
signal combat_damage_dealt(amount: int, source: String)
signal combat_damage_taken(amount: int, source: String)
signal chain_formed(chain_length: int, bonus_multiplier: float)
signal boss_encountered(enemy_id: String)
signal boss_defeated(enemy_id: String)

# --- Player / progression ---
signal player_hp_changed(current_hp: int, max_hp: int)
signal player_defeated
signal ink_drops_changed(total: int, delta: int)
signal dictionary_fragment_gained(total: int)
signal vocabulary_word_unlocked(word: String)
signal item_collected(item_id: String)
signal level_up(new_level: int)

# --- Meta / system ---
signal save_completed(slot: String)
signal load_completed(slot: String)
signal settings_changed(settings: Dictionary)
signal error_occurred(context: String, message: String)
