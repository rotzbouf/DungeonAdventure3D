extends CanvasLayer

## First UI scene in the project: lets the player pick a race/class/name and
## sends it to the server as an intent (request -> validate -> apply ->
## replicate, same pattern as player_input.gd's request_move_to — except the
## "character" being requested doesn't exist yet, so the request is routed
## through World, the one node that exists at an identical path on every peer
## before any player.tscn is ever spawned).
##
## Pure data entry: no authority decisions are made here. The server is the
## sole judge of whether the request is valid; this screen just reflects the
## outcome it's told about.

@onready var _world: Node = get_node("../World")
@onready var _race_option: OptionButton = $Panel/Margin/Layout/RaceOption
@onready var _class_option: OptionButton = $Panel/Margin/Layout/ClassOption
@onready var _name_edit: LineEdit = $Panel/Margin/Layout/NameEdit
@onready var _confirm_button: Button = $Panel/Margin/Layout/ConfirmButton
@onready var _status_label: Label = $Panel/Margin/Layout/StatusLabel


func _ready() -> void:
	visible = false
	_populate_options(_race_option, GameDatabase.races)
	_populate_options(_class_option, GameDatabase.classes)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_world.character_creation_succeeded.connect(_on_creation_succeeded)
	_world.character_creation_failed.connect(_on_creation_failed)
	NetworkManager.connected_to_server.connect(_on_connected_to_server, CONNECT_ONE_SHOT)
	NetworkManager.connection_failed.connect(_on_connection_unavailable, CONNECT_ONE_SHOT)
	NetworkManager.server_disconnected.connect(_on_connection_unavailable, CONNECT_ONE_SHOT)


func _populate_options(option: OptionButton, definitions: Dictionary) -> void:
	var ids := definitions.keys()
	ids.sort()
	for definition_id in ids:
		var definition: Resource = definitions[definition_id]
		var index := option.item_count
		option.add_item(definition.display_name)
		option.set_item_metadata(index, definition.id)


func _on_connected_to_server() -> void:
	visible = true
	_status_label.text = ""


func _on_connection_unavailable() -> void:
	_status_label.text = "Connection lost — cannot create a character."
	_confirm_button.disabled = true


func _on_confirm_pressed() -> void:
	var character_name := _name_edit.text.strip_edges()
	if character_name.is_empty():
		_status_label.text = "Enter a name first."
		return
	if _race_option.selected < 0 or _class_option.selected < 0:
		_status_label.text = "Choose a race and a class first."
		return
	var race_id: StringName = _race_option.get_item_metadata(_race_option.selected)
	var class_id: StringName = _class_option.get_item_metadata(_class_option.selected)
	_confirm_button.disabled = true
	_status_label.text = "Creating character..."
	_world.request_create_character.rpc_id(1, race_id, class_id, character_name)


func _on_creation_succeeded() -> void:
	visible = false


func _on_creation_failed(reason: String) -> void:
	_status_label.text = reason
	_confirm_button.disabled = false
