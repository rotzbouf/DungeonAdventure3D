extends Node

## SERVER-AUTHORITATIVE equipment slots + per-peer visual attachment. Mirrors
## world.gd's request_create_character pattern (request -> validate -> mutate
## authoritative state -> broadcast) and player_input.gd's "declare the RPC on
## a node that exists at an identical path on every peer" trick. First module
## under entities/player/components/ — stats_/skill_component.gd will follow
## the same shape (request/validate/mutate/broadcast + replicated state).
##
## Visuals are never replicated directly (PackedScene can't cross the wire,
## see equipment_item.gd) — only `equipped_slots` (item ids) replicates, and
## every peer re-resolves item -> visual_scene via GameDatabase locally,
## exactly like model_view.gd re-resolves race -> visual_scene from race_id.

## Server-only feedback for the requesting peer. Mirrors world.gd's
## character_creation_failed signal bridge.
signal equip_rejected(reason: String)

## Client-side: the equipped set changed (equip/unequip). Emitted by the
## presentation RPCs below — NOT by the `equipped_slots` replication setter,
## which can fire before the node is parented (lesson 6). The inventory panel
## connects to this to refresh its equipped section. `slots` is the current
## equipped_slots dict.
signal equipment_changed(slots: Dictionary)

## slot -> equipped item instance (item_instance_system.gd), e.g.
## {&"main_hand": {"iid": ..., "id": &"sword", "rarity": &"common", "affixes": {}}}.
## Replicated via player.gd._setup_replication with REPLICATION_MODE_ON_CHANGE
## (spawn=true) so late joiners reconstruct it with zero history replay — see
## the `set` below for how that reconciles into visuals.
var equipped_slots: Dictionary[StringName, Dictionary] = {}:
	set(value):
		equipped_slots = value
		# A dedicated server has nothing to attach a visual to (headless) and is the
		# only place this dict is ever assigned wholesale by our own code (see
		# request_equip, which mutates in place — `dict[key] = value` does NOT
		# invoke this setter, only whole-property assignment does). On clients,
		# this fires both for the late-joiner spawn snapshot and for live
		# REPLICATION_MODE_ON_CHANGE updates; _attach_visual_for_slot's
		# _attached_items idempotency check makes re-driving every entry here
		# safe even when on_equip_changed below also fires for the same change.
		if NetworkMode.is_dedicated_server():
			return
		for slot in value:
			_attach_visual_for_slot(slot, value[slot])

## slot -> the BoneAttachment3D currently representing it, so re-equipping
## frees the previous visual instead of stacking weapons on the same bone.
var _attachments: Dictionary[StringName, BoneAttachment3D] = {}

## slot -> iid of the instance currently shown, independent of
## `equipped_slots` so _attach_visual_for_slot stays idempotent regardless of
## whether the replicated-property setter or the on_equip_changed RPC observes
## a given change first (both can fire for the same change — see the plan).
var _attached_items: Dictionary[StringName, String] = {}

## NOT cached via @onready: the spawn-snapshot reconciliation in the
## `equipped_slots` setter above can fire on a freshly-instantiated late-
## joiner node *before* @onready vars are populated (confirmed empirically —
## get_parent() returned null there too at first, until the call_deferred
## retry in _attach_visual_for_slot gave the spawn machinery a frame to
## finish parenting). get_parent() is always correct once actually parented,
## and by the time request_equip runs (long after spawn) it certainly is.
func _player() -> CharacterBody3D:
	return get_parent() as CharacterBody3D


## --- Combat-stat aggregation (M15) ---------------------------------------
## Read-only views over `equipped_slots`, resolved through GameDatabase like
## every other id -> resource lookup. Called server-side by the damage paths
## (player_controller.gd basic attacks, enemy/dragon controllers reading the
## victim's armor) — `equipped_slots` is replicated, so these answers are
## consistent on any peer that cares to ask.

## Unarmed fallbacks, used whenever no main_hand weapon is equipped.
const UNARMED_ATTACK_DAMAGE := 3
const UNARMED_ATTACK_INTERVAL := 1.5
const UNARMED_ATTACK_RANGE := 1.6


## The equipped main_hand EquipmentItem, or null when unarmed.
func weapon() -> EquipmentItem:
	var instance: Dictionary = equipped_slots.get(&"main_hand", {})
	if instance.is_empty():
		return null
	return ItemInstanceSystem.base_item(instance)


func weapon_attack_damage() -> int:
	var instance: Dictionary = equipped_slots.get(&"main_hand", {})
	if instance.is_empty():
		return UNARMED_ATTACK_DAMAGE
	return int(ItemInstanceSystem.total_stat(instance, &"attack_damage"))


func weapon_attack_interval() -> float:
	var instance: Dictionary = equipped_slots.get(&"main_hand", {})
	if instance.is_empty():
		return UNARMED_ATTACK_INTERVAL
	return ItemInstanceSystem.total_stat(instance, &"attack_interval")


func weapon_attack_range() -> float:
	var instance: Dictionary = equipped_slots.get(&"main_hand", {})
	if instance.is_empty():
		return UNARMED_ATTACK_RANGE
	return ItemInstanceSystem.total_stat(instance, &"attack_range")


## Flat attack added on top of a skill/spell's authored damage_base.
func total_attack_bonus() -> int:
	var total := 0
	for slot in equipped_slots:
		total += int(ItemInstanceSystem.total_stat(equipped_slots[slot], &"attack_damage"))
	return total


## Flat mitigation applied when the wearer is hit (CombatSystem.compute_hit).
func total_armor() -> int:
	var total := 0
	for slot in equipped_slots:
		total += int(ItemInstanceSystem.total_stat(equipped_slots[slot], &"armor"))
	return total


func total_crit_chance() -> float:
	var total := CombatSystem.BASE_CRIT_CHANCE
	for slot in equipped_slots:
		total += ItemInstanceSystem.total_stat(equipped_slots[slot], &"crit_chance_bonus")
	return total


## Client -> server: "equip this item from my bag" (M15.1). The destination
## slot is the item's own `slot`. Declared on this node so Godot routes the
## call to the same node path on the server — mirrors
## player_input.gd.request_move_to / world.gd.request_create_character.
@rpc("any_peer", "call_local", "reliable")
func request_equip(iid: String) -> void:
	if not NetworkMode.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != _player().owning_peer_id():
		push_warning("equipment_component: rejected equip request from non-owning peer %d" % sender_id)
		return
	var inventory: Node = _player().get_node_or_null("InventoryComponent")
	var index := ItemInstanceSystem.find_index_by_iid(inventory.items, iid) if inventory != null else -1
	if index == -1:
		on_equip_rejected.rpc_id(sender_id, "You don't have that item.")
		return
	var instance: Dictionary = inventory.items[index]
	var item: Resource = ItemInstanceSystem.base_item(instance)
	if not (item is EquipmentItem):
		on_equip_rejected.rpc_id(sender_id, "That item can't be equipped.")
		return
	var slot: StringName = item.slot
	var reason := EquipValidationSystem.can_equip(instance.id, slot)
	if reason != "":
		on_equip_rejected.rpc_id(sender_id, reason)
		return
	# Swap: pull the item out of the bag and into the slot; whatever was in the
	# slot goes back to the bag. Whole-array assignment (not in-place) so the
	# InventoryComponent.items setter fires on a listen host too (lesson 22) —
	# on a dedicated server the setter no-ops but the value still replicates.
	var bag: Array[Dictionary] = inventory.items.duplicate()
	bag.remove_at(index)
	var previous: Dictionary = equipped_slots.get(slot, {})
	if not previous.is_empty():
		bag.append(previous)
	inventory.items = bag
	equipped_slots[slot] = instance
	on_equip_changed.rpc(slot, instance)


## Client -> server: "unequip this slot back into my bag".
@rpc("any_peer", "call_local", "reliable")
func request_unequip(slot: StringName) -> void:
	if not NetworkMode.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != _player().owning_peer_id():
		push_warning("equipment_component: rejected unequip request from non-owning peer %d" % sender_id)
		return
	var instance: Dictionary = equipped_slots.get(slot, {})
	if instance.is_empty():
		return  # nothing equipped there
	var inventory: Node = _player().get_node_or_null("InventoryComponent")
	if inventory != null:
		var bag: Array[Dictionary] = inventory.items.duplicate()
		bag.append(instance)
		inventory.items = bag
	equipped_slots.erase(slot)
	on_unequip.rpc(slot)


## Server -> every peer, call_local (lesson 21): the listen host must run this
## for its OWN player, since its in-place server mutation never fires the
## `equipped_slots` setter and the synchronizer doesn't echo to the authority.
## Headless dedicated server early-outs (no skeleton to attach to). Remote
## clients also get the visual via the replication setter; _attached_items
## keeps the double-drive idempotent.
@rpc("authority", "call_local", "reliable")
func on_equip_changed(slot: StringName, instance: Dictionary) -> void:
	if NetworkMode.is_dedicated_server():
		return
	equipped_slots[slot] = instance
	_attach_visual_for_slot(slot, instance)
	equipment_changed.emit(equipped_slots)


## Server -> every peer, call_local — the detach counterpart of
## on_equip_changed. The replication setter only ever *attaches* present slots
## (it never detaches a removed one), so every peer needs this to drop the
## visual.
@rpc("authority", "call_local", "reliable")
func on_unequip(slot: StringName) -> void:
	if NetworkMode.is_dedicated_server():
		return
	equipped_slots.erase(slot)
	_detach_visual_for_slot(slot)
	equipment_changed.emit(equipped_slots)


@rpc("authority", "call_local", "reliable")
func on_equip_rejected(reason: String) -> void:
	equip_rejected.emit(reason)


## Frees any prior visual for `slot`, then resolves item -> visual_scene and
## race -> attachment bone purely from ids (GameDatabase + race_id) — never
## from anything that crossed the network directly, mirroring how
## model_view.gd re-resolves race_id -> visual_scene locally on every peer.
func _attach_visual_for_slot(slot: StringName, instance: Dictionary) -> void:
	var iid: String = instance.get("iid", "")
	if _attached_items.get(slot) == iid:
		return

	var player := _player()
	var skeleton := _find_skeleton(player) if player != null else null
	if player == null or skeleton == null:
		# Confirmed empirically: the spawn-snapshot setter above can fire on a
		# freshly-instantiated late-joiner node before it's even parented (so
		# get_parent() is briefly null too) and before model_view._ready() has
		# instanced the race visual — both ends of the exact _enter_tree-vs-
		# _ready class of ordering hazard in lessons_multiplayer_replication.
		# Retry once this frame's spawn/_ready chain has finished;
		# _attached_items keeps the retry idempotent either way.
		call_deferred("_attach_visual_for_slot", slot, instance)
		return

	_detach_visual_for_slot(slot)

	var item: EquipmentItem = ItemInstanceSystem.base_item(instance)
	var race: RaceModel = GameDatabase.races.get(player.race_id)
	var bone_name: StringName = race.attachment_points.get(slot, &"") if race != null else &""
	if item == null or item.visual_scene == null or bone_name == &"":
		push_warning("equipment_component: cannot attach %s to slot %s (missing item visual or attachment bone)" % [instance.get("id", &""), slot])
		return

	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	attachment.add_child(item.visual_scene.instantiate())

	_attachments[slot] = attachment
	_attached_items[slot] = iid


## Frees the BoneAttachment3D currently representing `slot` (if any) and clears
## the bookkeeping so a future re-equip of the same item re-attaches. Shared by
## re-equip (inside _attach_visual_for_slot) and unequip (on_unequip).
func _detach_visual_for_slot(slot: StringName) -> void:
	var existing: BoneAttachment3D = _attachments.get(slot)
	if existing != null and is_instance_valid(existing):
		existing.queue_free()
	_attachments.erase(slot)
	_attached_items.erase(slot)


## Client-side basic-attack swing (M15): a quick procedural rotate-and-back
## tween on the main_hand BoneAttachment3D. The player rigs ship no melee
## clip, so this is the whole swing animation — a no-op when unarmed (the
## swing SFX from player.gd.on_attack_performed still plays).
func play_swing_tween() -> void:
	var attachment: BoneAttachment3D = _attachments.get(&"main_hand")
	if attachment == null or not is_instance_valid(attachment):
		return
	var start_rotation := attachment.rotation
	var tween := attachment.create_tween()
	tween.tween_property(attachment, "rotation:x", start_rotation.x - PI / 2.0, 0.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(attachment, "rotation:x", start_rotation.x, 0.15) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _find_skeleton(player: CharacterBody3D) -> Skeleton3D:
	var model := player.get_node_or_null("Model")
	if model == null:
		return null
	return model.find_child("Skeleton3D", true, false) as Skeleton3D
