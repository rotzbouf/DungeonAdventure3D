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
## character_creation_failed signal bridge — no UI consumes this yet, the
## verification harness triggers and observes it directly.
signal equip_rejected(reason: String)

## slot -> equipped item id, e.g. {&"main_hand": &"sword"}. Replicated via
## player.gd._setup_replication with REPLICATION_MODE_ON_CHANGE (spawn=true)
## so late joiners reconstruct it with zero history replay — see the `set`
## below for how that reconciles into visuals.
var equipped_slots: Dictionary[StringName, StringName] = {}:
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

## slot -> item id currently shown, independent of `equipped_slots` so
## _attach_visual_for_slot stays idempotent regardless of whether the
## replicated-property setter or the on_equip_changed RPC observes a given
## change first (both can fire for the same change — see the plan).
var _attached_items: Dictionary[StringName, StringName] = {}

## NOT cached via @onready: the spawn-snapshot reconciliation in the
## `equipped_slots` setter above can fire on a freshly-instantiated late-
## joiner node *before* @onready vars are populated (confirmed empirically —
## get_parent() returned null there too at first, until the call_deferred
## retry in _attach_visual_for_slot gave the spawn machinery a frame to
## finish parenting). get_parent() is always correct once actually parented,
## and by the time request_equip runs (long after spawn) it certainly is.
func _player() -> CharacterBody3D:
	return get_parent() as CharacterBody3D


## Client -> server: "I'd like to equip this item into this slot." Declared on
## this node so Godot routes the call to the same node path on the server —
## mirrors player_input.gd.request_move_to / world.gd.request_create_character.
@rpc("any_peer", "call_local", "reliable")
func request_equip(slot: StringName, item_id: StringName) -> void:
	if not NetworkMode.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != _player().owning_peer_id():
		push_warning("equipment_component: rejected equip request from non-owning peer %d" % sender_id)
		return
	var reason := EquipValidationSystem.can_equip(item_id, slot)
	if reason != "":
		push_warning("equipment_component: rejected equip request from peer %d: %s" % [sender_id, reason])
		on_equip_rejected.rpc_id(sender_id, reason)
		return
	# Authoritative mutation: in place, not a whole-dict assignment — the
	# server is the source of truth and has no visuals to drive off its own
	# setter (see the `set` above). MultiplayerSynchronizer carries the
	# resulting value to every peer, including late joiners.
	equipped_slots[slot] = item_id
	on_equip_changed.rpc(slot, item_id)


## Server -> every peer (broadcast, deliberately NO call_local: the
## broadcaster is the headless server, which has nothing to attach a visual
## to — the equipping client is just an ordinary recipient like everyone
## else). Each receiver mirrors the authoritative dict and (re)attaches.
@rpc("authority", "call_remote", "reliable")
func on_equip_changed(slot: StringName, item_id: StringName) -> void:
	equipped_slots[slot] = item_id
	_attach_visual_for_slot(slot, item_id)


@rpc("authority", "call_local", "reliable")
func on_equip_rejected(reason: String) -> void:
	equip_rejected.emit(reason)


## Frees any prior visual for `slot`, then resolves item -> visual_scene and
## race -> attachment bone purely from ids (GameDatabase + race_id) — never
## from anything that crossed the network directly, mirroring how
## model_view.gd re-resolves race_id -> visual_scene locally on every peer.
func _attach_visual_for_slot(slot: StringName, item_id: StringName) -> void:
	if _attached_items.get(slot) == item_id:
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
		call_deferred("_attach_visual_for_slot", slot, item_id)
		return

	var existing: BoneAttachment3D = _attachments.get(slot)
	if existing != null:
		existing.queue_free()
		_attachments.erase(slot)
		_attached_items.erase(slot)

	var item: EquipmentItem = GameDatabase.items.get(item_id)
	var race: RaceModel = GameDatabase.races.get(player.race_id)
	var bone_name: StringName = race.attachment_points.get(slot, &"") if race != null else &""
	if item == null or item.visual_scene == null or bone_name == &"":
		push_warning("equipment_component: cannot attach %s to slot %s (missing item visual or attachment bone)" % [item_id, slot])
		return

	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	attachment.add_child(item.visual_scene.instantiate())

	_attachments[slot] = attachment
	_attached_items[slot] = item_id


func _find_skeleton(player: CharacterBody3D) -> Skeleton3D:
	var model := player.get_node_or_null("Model")
	if model == null:
		return null
	return model.find_child("Skeleton3D", true, false) as Skeleton3D
