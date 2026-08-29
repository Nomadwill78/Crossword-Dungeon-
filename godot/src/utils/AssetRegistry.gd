#============================================================================
# AssetRegistry.gd
# Centralized, cached asset loading. Not an autoload — a static-var data
# access class (see CLAUDE.md 4.3's ClueDatabase pattern), same rationale:
# a shared process-wide cache without adding another autoload singleton.
# Dependencies: none
# Events: none
#============================================================================

class_name AssetRegistry
extends RefCounted

#----------------------------------------------------------------------------
# PRIVATE VARIABLES (static — see file header)
#----------------------------------------------------------------------------
static var _textures: Dictionary = {}
static var _scenes: Dictionary = {}
static var _fonts: Dictionary = {}

#----------------------------------------------------------------------------
# PUBLIC METHODS
#----------------------------------------------------------------------------

## Returns the cached texture at [param path], loading it once on first
## access. Returns null and logs a warning if the resource is missing
## (CLAUDE.md 5.3: missing asset never crashes the game).
static func get_texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	if not ResourceLoader.exists(path):
		push_warning("AssetRegistry: missing texture %s" % path)
		return null
	var tex: Texture2D = load(path)
	_textures[path] = tex
	return tex

## Returns the cached scene at [param path], loading it once on first access.
static func get_scene(path: String) -> PackedScene:
	if _scenes.has(path):
		return _scenes[path]
	if not ResourceLoader.exists(path):
		push_warning("AssetRegistry: missing scene %s" % path)
		return null
	var scene: PackedScene = load(path)
	_scenes[path] = scene
	return scene

## Returns the cached font at [param path], loading it once on first access.
static func get_font(path: String) -> Font:
	if _fonts.has(path):
		return _fonts[path]
	if not ResourceLoader.exists(path):
		push_warning("AssetRegistry: missing font %s" % path)
		return null
	var font: Font = load(path)
	_fonts[path] = font
	return font

## Convenience: load (if needed) and instantiate the scene at [param path].
## Returns null if the scene is missing.
static func instantiate_scene(path: String) -> Node:
	var scene := get_scene(path)
	if scene == null:
		return null
	return scene.instantiate()

## Drops all cached resources. Intended for tests/tools, not normal play.
static func clear_cache() -> void:
	_textures.clear()
	_scenes.clear()
	_fonts.clear()
