## Autoload singleton. Centralized asset loading with an in-memory cache so
## the same texture/scene/font isn't loaded from disk more than once.
extends Node

var _textures: Dictionary = {}
var _scenes: Dictionary = {}
var _fonts: Dictionary = {}

func get_texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	if not ResourceLoader.exists(path):
		push_warning("AssetRegistry: missing texture %s" % path)
		return null
	var tex: Texture2D = load(path)
	_textures[path] = tex
	return tex

func get_scene(path: String) -> PackedScene:
	if _scenes.has(path):
		return _scenes[path]
	if not ResourceLoader.exists(path):
		push_warning("AssetRegistry: missing scene %s" % path)
		return null
	var scene: PackedScene = load(path)
	_scenes[path] = scene
	return scene

func get_font(path: String) -> Font:
	if _fonts.has(path):
		return _fonts[path]
	if not ResourceLoader.exists(path):
		push_warning("AssetRegistry: missing font %s" % path)
		return null
	var font: Font = load(path)
	_fonts[path] = font
	return font

func instantiate_scene(path: String) -> Node:
	var scene := get_scene(path)
	if scene == null:
		return null
	return scene.instantiate()

func clear_cache() -> void:
	_textures.clear()
	_scenes.clear()
	_fonts.clear()
