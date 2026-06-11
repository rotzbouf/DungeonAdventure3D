extends StaticBody3D

## A world prop that teaches the player a spell when clicked.
## player_input._handle_click detects the `interact` method and routes here
## instead of issuing a move_to. The scroll never disappears (players can
## attempt to learn the same spell multiple times; the server rejects duplicates).

@export var spell_id: StringName = &"fireball"


func interact(player: Node) -> void:
	var spellbook: Node = player.get_node_or_null("SpellbookComponent")
	if spellbook == null:
		return
	spellbook.request_read_scroll.rpc_id(1, spell_id)
