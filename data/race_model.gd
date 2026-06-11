class_name RaceModel
extends Resource

## Designer-authored race definition, loaded by GameDatabase from
## res://content/races/*.tres. id must be unique and non-empty (see
## GameDatabase._load_category) and is what RPC payloads/spawn data
## reference — the visual_scene itself never crosses the network.

@export var id: StringName = &""
@export var display_name: String = ""
@export var visual_scene: PackedScene

## Maps an equipment slot id (e.g. &"main_hand") to the bone name on this
## race's rig that BoneAttachment3D should target (e.g. &"Weapon_R"). Per-race
## because rigs differ — Elf has Weapon_L/Arrow bones DarkElf lacks.
@export var attachment_points: Dictionary[StringName, StringName] = {}
