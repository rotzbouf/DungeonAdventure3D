extends Node

## Loads every designer-authored Resource (.tres) under res://content/** into
## id-keyed dictionaries, identically on server and client. This is the
## linchpin that keeps "new content = drop in a .tres file, zero code" true:
## every system below (server-authoritative or client-side preview) reads
## definitions through this single, byte-identical lookup table.

var races: Dictionary = {}
var classes: Dictionary = {}
var skills: Dictionary = {}
var spells: Dictionary = {}
var items: Dictionary = {}
var level_curves: Dictionary = {}
var enemies: Dictionary = {}

const CATEGORY_DIRS := {
	"races": "res://content/races",
	"classes": "res://content/classes",
	"skills": "res://content/skills",
	"spells": "res://content/spells",
	"items": "res://content/items",
	"level_curves": "res://content/level_curves",
	"enemies": "res://content/enemies",
}


func _ready() -> void:
	reload()


func reload() -> void:
	races = _load_category("races")
	classes = _load_category("classes")
	skills = _load_category("skills")
	spells = _load_category("spells")
	items = _load_category("items")
	level_curves = _load_category("level_curves")
	enemies = _load_category("enemies")
	var total := races.size() + classes.size() + skills.size() + spells.size() + items.size() + level_curves.size() + enemies.size()
	print("GameDatabase: loaded %d content resources" % total)


func _load_category(category: String) -> Dictionary:
	var result: Dictionary = {}
	var dir_path: String = CATEGORY_DIRS[category]
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var resource: Resource = load(dir_path.path_join(file_name))
			if resource != null and "id" in resource and resource.id != &"":
				result[resource.id] = resource
			else:
				push_warning("GameDatabase: %s in %s has no usable 'id' property, skipping" % [file_name, category])
		file_name = dir.get_next()
	dir.list_dir_end()
	return result
