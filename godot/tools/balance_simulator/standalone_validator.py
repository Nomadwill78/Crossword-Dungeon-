#!/usr/bin/env python3
"""
standalone_validator.py
Validates Wordsmith's Gambit grid generation without a Godot runtime, using
gridgen_reference.py (a hand-kept Python port of GridGenerator.gd's fill
algorithm) run against the real project data files.

Usage: python3 standalone_validator.py [trials_per_preset]
"""

import random
import sys
from collections import deque

from gridgen_reference import (
    load_clues, load_presets, load_enemies, generate_grid,
)


def get_cell(cells, x, y):
    for cell in cells:
        if cell["x"] == x and cell["y"] == y:
            return cell
    return {}


def find_path(cells, size, start, end):
    """BFS pathfinding through non-black cells."""
    queue = deque([start])
    visited = {start}
    directions = [(1, 0), (-1, 0), (0, 1), (0, -1)]

    while queue:
        cx, cy = queue.popleft()
        if (cx, cy) == end:
            return True
        for dx, dy in directions:
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < size and 0 <= ny < size and (nx, ny) not in visited:
                cell = get_cell(cells, nx, ny)
                if cell.get("type") != "black":
                    visited.add((nx, ny))
                    queue.append((nx, ny))
    return False


def validate_grid(grid_state):
    """Returns a list of error messages. Empty list = valid."""
    errors = []
    size = grid_state.get("size", 0)
    cells = grid_state.get("cells", [])

    if len(cells) != size * size:
        errors.append(f"Cell count mismatch: {len(cells)} != {size * size}")

    entrance = grid_state.get("entrance")
    exit_pos = grid_state.get("exit")
    if not entrance:
        errors.append("No entrance found")
    if not exit_pos:
        errors.append("No exit found")

    if entrance and exit_pos:
        start = (entrance["x"], entrance["y"])
        end = (exit_pos["x"], exit_pos["y"])
        if start == end:
            errors.append("Entrance and exit are the same cell")
        if not find_path(cells, size, start, end):
            errors.append("No path from entrance to exit")

    for cell in cells:
        if cell.get("type") == "letter" and not cell.get("solved", False):
            if not cell.get("enemy_id"):
                errors.append(f"Unsolved letter at ({cell['x']},{cell['y']}) has no enemy")
            if not cell.get("clue_id"):
                errors.append(f"Unsolved letter at ({cell['x']},{cell['y']}) has no clue")

    for word in grid_state.get("words_horizontal", []) + grid_state.get("words_vertical", []):
        if word.get("length", 0) < 3:
            errors.append(f"Word slot {word.get('id')} has length < 3")

    return errors


def run_validation(trials_per_preset=30):
    presets = load_presets()
    clues = load_clues()
    enemies = load_enemies()

    print(f"Running {trials_per_preset} grid generations per preset...\n")

    total_passed = 0
    total_failed = 0
    total_generation_failures = 0

    for template in presets["templates"]:
        rng = random.Random(hash(template["id"]) & 0xFFFFFFFF)
        size = template["size"]
        target = template["target_slots"]
        passed = 0
        failed = 0
        slot_counts = []

        for _ in range(trials_per_preset):
            grid_state = generate_grid(size, target, clues, enemies, rng)
            if grid_state is None:
                total_generation_failures += 1
                failed += 1
                continue
            errors = validate_grid(grid_state)
            if errors:
                failed += 1
                print(f"  {template['id']}: FAILED")
                for err in errors:
                    print(f"    - {err}")
            else:
                passed += 1
                slot_counts.append(len(grid_state["words_horizontal"]) + len(grid_state["words_vertical"]))

        total_passed += passed
        total_failed += failed
        avg_slots = sum(slot_counts) / len(slot_counts) if slot_counts else 0
        status = "OK" if failed == 0 else "FAIL"
        print(f"{template['id']:15s} size={size} target={target:2d}  "
              f"passed={passed}/{trials_per_preset}  avg_words={avg_slots:.1f}  [{status}]")

    print(f"\n{'=' * 50}")
    print(f"Total passed: {total_passed}")
    print(f"Total failed: {total_failed}")
    print(f"Generation returned None: {total_generation_failures}")
    rate = total_passed / (total_passed + total_failed) * 100 if (total_passed + total_failed) else 0
    print(f"Success rate: {rate:.1f}%")

    return total_failed == 0


if __name__ == "__main__":
    trials = int(sys.argv[1]) if len(sys.argv) > 1 else 30
    success = run_validation(trials)
    sys.exit(0 if success else 1)
