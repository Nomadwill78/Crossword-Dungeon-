#!/usr/bin/env python3
"""
gridgen_reference.py
A Python port of src/core/grid/GridGenerator.gd's fill algorithm, kept in
sync by hand. It exists so grid generation can be validated in CI without a
Godot binary (see standalone_validator.py). If you change the placement
logic in GridGenerator.gd, mirror the change here too.
"""

import json
import random
from collections import deque
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parents[2] / "data"


def load_clues():
    with open(DATA_DIR / "clues" / "clues_master.json") as f:
        return json.load(f)["clues"]


def load_presets():
    with open(DATA_DIR / "config" / "grid_presets.json") as f:
        return json.load(f)


def load_enemies():
    with open(DATA_DIR / "enemies" / "enemies_master.json") as f:
        return json.load(f)["enemies"]


def load_game_config():
    with open(DATA_DIR / "config" / "game_config.json") as f:
        return json.load(f)


def _can_place(cells, word, x, y, direction, size):
    intersections = 0
    for i, ch in enumerate(word):
        cx = x + i if direction == "across" else x
        cy = y if direction == "across" else y + i
        if not (0 <= cx < size and 0 <= cy < size):
            return -1
        existing = cells.get((cx, cy))
        if existing:
            if existing["letter"] != ch:
                return -1
            if direction == "across" and existing["across"] != "":
                return -1
            if direction == "down" and existing["down"] != "":
                return -1
            intersections += 1
        else:
            if direction == "across":
                if (cx, cy - 1) in cells or (cx, cy + 1) in cells:
                    return -1
            else:
                if (cx - 1, cy) in cells or (cx + 1, cy) in cells:
                    return -1
    before = (x - 1, y) if direction == "across" else (x, y - 1)
    after = (x + len(word), y) if direction == "across" else (x, y + len(word))
    if before in cells or after in cells:
        return -1
    return intersections


def _find_candidates(cells, word, size):
    out = []
    for (cx, cy), cell in list(cells.items()):
        for i, ch in enumerate(word):
            if ch != cell["letter"]:
                continue
            if cell["across"] == "":
                x, y = cx - i, cy
                score = _can_place(cells, word, x, y, "across", size)
                if score > 0:
                    out.append((score, x, y, "across"))
            if cell["down"] == "":
                x, y = cx, cy - i
                score = _can_place(cells, word, x, y, "down", size)
                if score > 0:
                    out.append((score, x, y, "down"))
    out.sort(key=lambda t: -t[0])
    return out


def _place(cells, placements, clue, x, y, direction):
    word = clue["answer"]
    for i, ch in enumerate(word):
        cx = x + i if direction == "across" else x
        cy = y if direction == "across" else y + i
        existing = cells.get((cx, cy), {"letter": ch, "across": "", "down": ""})
        existing["letter"] = ch
        existing[direction] = clue["id"]
        cells[(cx, cy)] = existing
    placements.append({"clue": clue, "x": x, "y": y, "dir": direction})


def _generate_once(size, target_slots, all_clues, rng):
    pool = [c for c in all_clues if c["length"] <= size]
    rng.shuffle(pool)

    cells = {}
    placements = []
    used_ids = set()

    seed = None
    for c in sorted(pool, key=lambda c: -c["length"]):
        if c["length"] <= size:
            seed = c
            break
    if seed is None:
        return cells, placements

    sx = (size - seed["length"]) // 2
    sy = size // 2
    _place(cells, placements, seed, sx, sy, "across")
    used_ids.add(seed["id"])

    pending = [c for c in pool if c["id"] not in used_ids]

    def try_all(candidates):
        retry = []
        placed_any = False
        for clue in candidates:
            if len(placements) >= target_slots:
                return retry, placed_any
            if clue["id"] in used_ids:
                continue
            cands = _find_candidates(cells, clue["answer"], size)
            if cands:
                _, x, y, d = cands[0]
                _place(cells, placements, clue, x, y, d)
                used_ids.add(clue["id"])
                placed_any = True
            else:
                retry.append(clue)
        return retry, placed_any

    while pending and len(placements) < target_slots:
        pending, placed_any = try_all(pending)
        if not placed_any:
            break

    return cells, placements


def _bfs_farthest(cells, start):
    visited = {start: 0}
    q = deque([start])
    farthest = start
    while q:
        cur = q.popleft()
        for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nxt = (cur[0] + d[0], cur[1] + d[1])
            if nxt in cells and nxt not in visited:
                visited[nxt] = visited[cur] + 1
                q.append(nxt)
                if visited[nxt] > visited[farthest]:
                    farthest = nxt
    return farthest


def generate_grid(size, target_slots, all_clues, all_enemies, rng, max_regenerate=6, min_acceptable=None):
    """Returns a grid_state dict shaped like GridGenerator.gd's output."""
    min_acceptable = min_acceptable or max(4, target_slots // 2)

    best_cells, best_placements = {}, []
    for _ in range(max_regenerate):
        cells, placements = _generate_once(size, target_slots, all_clues, rng)
        if len(placements) > len(best_placements):
            best_cells, best_placements = cells, placements
        if len(placements) >= min_acceptable:
            break

    if not best_placements:
        return None

    entrance = (best_placements[0]["x"], best_placements[0]["y"])
    exit_pos = _bfs_farthest(best_cells, entrance)

    # The word containing the exit is the grid's final word. Recorded for the
    # (not yet built) end-of-grid boss fight; no boss is placed on the grid.
    # See the matching note in GridGenerator.gd.
    final_word_clue_ids = set()
    for p in best_placements:
        word = p["clue"]["answer"]
        for i in range(len(word)):
            cx = p["x"] + i if p["dir"] == "across" else p["x"]
            cy = p["y"] if p["dir"] == "across" else p["y"] + i
            if (cx, cy) == exit_pos:
                final_word_clue_ids.add(p["clue"]["id"])

    regular_enemies = [e for e in all_enemies if not e.get("is_boss")]

    cell_primary_clue = {}
    words_across, words_down = [], []
    for p in best_placements:
        word = p["clue"]["answer"]
        for i in range(len(word)):
            cx = p["x"] + i if p["dir"] == "across" else p["x"]
            cy = p["y"] if p["dir"] == "across" else p["y"] + i
            if p["dir"] == "across" or (cx, cy) not in cell_primary_clue:
                cell_primary_clue[(cx, cy)] = p["clue"]["id"]
        entry = {
            "id": p["clue"]["id"], "answer": word, "length": len(word),
            "clue_id": p["clue"]["id"], "start_x": p["x"], "start_y": p["y"],
            "direction": p["dir"],
        }
        (words_across if p["dir"] == "across" else words_down).append(entry)

    out_cells = []
    enemy_counter = 0
    for y in range(size):
        for x in range(size):
            key = (x, y)
            if key not in best_cells:
                out_cells.append({"x": x, "y": y, "type": "black", "letter": "", "solved": False,
                                   "enemy_id": "", "clue_id": "", "bonus": None, "bonus_claimed": False})
                continue
            letter = best_cells[key]["letter"]
            if key == entrance:
                out_cells.append({"x": x, "y": y, "type": "entrance", "letter": letter, "solved": True,
                                   "enemy_id": "", "clue_id": "", "bonus": None, "bonus_claimed": False})
                continue
            if key == exit_pos:
                out_cells.append({"x": x, "y": y, "type": "exit", "letter": letter, "solved": False,
                                   "enemy_id": "", "clue_id": "", "bonus": None, "bonus_claimed": False})
                continue
            clue_id = cell_primary_clue.get(key, "")
            if regular_enemies:
                enemy_id = regular_enemies[enemy_counter % len(regular_enemies)]["id"]
                enemy_counter += 1
            else:
                enemy_id = ""
            out_cells.append({"x": x, "y": y, "type": "letter", "letter": letter, "solved": False,
                               "enemy_id": enemy_id, "clue_id": clue_id, "bonus": None, "bonus_claimed": False})

    return {
        "size": size,
        "cells": out_cells,
        "words_horizontal": words_across,
        "words_vertical": words_down,
        "entrance": {"x": entrance[0], "y": entrance[1]},
        "exit": {"x": exit_pos[0], "y": exit_pos[1]},
    }
