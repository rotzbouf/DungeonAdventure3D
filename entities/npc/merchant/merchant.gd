extends StaticBody3D

## Static merchant NPC. Opening the shop UI is pure client-local presentation
## (no networking) -- mirrors player_input.gd's interact() -> raycast pattern,
## but unlike chest.gd/spell_scroll.gd there's no server-side state to touch
## here, only the local HUD's ShopPanel.

@export var shop_id: StringName = &""


func interact(player: Node) -> void:
	var hud := get_tree().root.find_child("HUD", true, false)
	if hud != null:
		hud.open_shop(shop_id, player)
