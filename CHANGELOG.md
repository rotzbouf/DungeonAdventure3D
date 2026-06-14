# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project uses [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`).

## [Unreleased]

## [0.18.0] - 2026-06-14

M16 "Loot & Progression": replaces the bare `StringName item_id` that has
flowed through inventory/equipment/loot/storage/shop since M6 with a real
**item instance** (unique id, base item, rolled rarity, affixes), then builds
the loot and character-progression features on top of it — weighted loot
tables with rarity tiers, random affixes on rare/uncommon gear, a rarity glow
on drops, a real level-2 talent choice for every class, and an inventory
details panel with stat breakdowns and gear comparisons.

### Added
- Item instances everywhere. New `systems/item_instance_system.gd`
  (`ItemInstanceSystem`) is the central module: `create()` builds
  `{"iid", "id", "rarity", "affixes"}`, plus `base_item`, `display_name`
  (rarity-prefixed, affix-suffixed, e.g. "Rare Sword of Power of Haste"),
  `total_stat` (base stat + matching affix magnitudes), `signature` (for
  inventory stacking), `sell_value` (`base.value * {common:1, uncommon:1.5,
  rare:2.5}[rarity] / 2`), and `find_index_by_iid`.
  `InventoryComponent.items`, `EquipmentComponent.equipped_slots`,
  `StorageChest`'s stored items, loot drops, and shop buy/sell all carry
  instance `Dictionary`s now (`Array[Dictionary]` /
  `Dictionary[StringName, Dictionary]` replicate over
  `SceneReplicationConfig` and `MultiplayerSpawner` spawn-data unchanged).
- Loot tables and rarity rolls. New `data/loot_table.gd` (`LootTable`:
  item weights, rarity weights, rolls, drop chance) and
  `systems/loot_roll_system.gd` (`LootRollSystem.roll`), wired through
  `world.gd.roll_loot` (server-only, uses the existing `_combat_rng`).
  Three tables in `content/loot_tables/` (`weak_enemy`, `tough_enemy`,
  `boss`) replace the old single hardcoded `loot_item_id` on
  goblin/skeleton/zombie/dragon — kills now drop 0-3 items with
  common/uncommon/rare odds skewed by enemy toughness.
- Affixes. New `data/affix_definition.gd` (`AffixDefinition`) and four
  `content/affixes/*.tres` (`of_power`, `of_brutality`, `of_precision`,
  `of_haste`), each a ranged bonus to one of `attack_damage`/`armor`/
  `crit_chance_bonus`/`attack_interval`. `LootRollSystem` rolls 0/1/2
  distinct-stat affixes for common/uncommon/rare equipment drops.
  `GameDatabase` gains `affixes` and `loot_tables` categories.
- Rarity glow on loot drops. New `entities/vfx/loot_glow.tscn` /
  `loot_glow.gd` — a pulsing colored light + sparkle particles, tinted by
  `Rarity.COLORS` and hidden for common drops, attached to every
  `loot_drop.gd` instance.
- Level-2 talent choices for every class. New
  `SkillUnlockSystem.choices_at(class_def, level)` offers a 2-option pick at
  level 2 (warrior: `shield_bash`/`cleave`, rogue: `evasion`/`poison_blade`,
  mage: `arcane_bolt`/`frost_nova` — mage previously got nothing at level 2).
  Four new skills in `content/skills/` reuse the existing `Skill` schema and
  `stun`/`poison` status effects, no new combat mechanics.
  `LevelComponent` gains server-only `_pending_choices`, a targeted
  `on_level_up_choice` RPC, and `request_choose_skill` to resolve a pick into
  `SkillComponent.known_skill_ids`. New `ui/hud/level_up/level_up_overlay.tscn`
  /`.gd` shows the choice modally and is wired up in `hud.gd`.
- Inventory details panel. Single-clicking any row in
  `inventory_panel.gd` now shows a rarity-colored name, non-zero base stats,
  one line per affix bonus, sell value, and — for equipment with something
  already worn in the same slot — a `+`/`-` colored stat-delta comparison
  against the equipped item.

### Fixed
- `Rarity.color_for` is duck-typed on `item.get("rarity")`; call sites in
  `inventory_panel.gd` and `shop_panel.gd` were passing the base item
  Resource (its *authored default* rarity, e.g. always `common` for a sword)
  instead of the rolled instance Dictionary, so rare/uncommon drops never
  rendered in their rarity color. Fixed by passing the instance directly.

### Verified
- Listen host (`./run.sh --host`): seeded a bag with a common potion, a rare
  sword rolled with `of_power`/`of_haste` affixes, and an equipped common
  axe (temp hook, removed). Inventory panel shows the rare sword's full name
  in rare-blue in both the bag list and the details panel; details panel
  shows base stats, both affix bonus lines, `Value: 62 gold` (matching the
  2.5x rare sell multiplier), and a correct stat-delta comparison against
  the equipped axe (attack damage down, crit chance and attack speed up).
- Headless dedicated boot (`--server`) clean: `GameDatabase: loaded 36
  content resources`, zero errors/warnings.

## [0.17.1] - 2026-06-13

Completes M15: makes equipped gear reachable. M15 gave weapons combat stats and
a basic attack that reads the equipped weapon, but there was no in-game way to
*equip* anything — `request_equip` had no UI caller and the inventory's
double-click only handled consumables, so a bought weapon sat in the bag and
the player fought permanently unarmed (fallback stats).

### Added
- Equip / unequip from the inventory panel (`ui/hud/inventory/inventory_panel.gd`).
  The panel now lists equipped items first (marked `[E]`, double-click to
  unequip back to the bag), then bag items; double-clicking a bag row equips it
  (equipment) or uses it (consumable) per the item's type. Rarity-colored
  throughout.
- `EquipmentComponent.request_equip(item_id)` is now inventory-aware: it pulls
  the item from the bag into its slot and returns any previous occupant to the
  bag (a swap), instead of equipping a phantom item that stays in the bag. New
  `request_unequip(slot)` returns an equipped item to the bag. New
  `equipment_changed` signal drives the panel's equipped section.

### Fixed
- The listen-host `on_equip_changed` gap (the known dead-code gap noted in the
  v0.16.0 audit, now actually reachable): it was a `call_remote` broadcast, so a
  listen host never ran it for its own player and the host's equipped weapon
  never visually attached. Made `on_equip_changed`/`on_unequip` `call_local`
  with an `is_dedicated_server()` guard (headless has no skeleton to attach to);
  remote clients still get the visual via the replication setter, kept
  idempotent by `_attached_items`. The replication setter only ever *attaches*
  present slots, so unequip's visual detach also rides these RPCs.
- Inventory mutations in the equip/unequip paths use whole-array assignment
  (not in-place), so the `InventoryComponent.items` setter — and thus
  `inventory_changed` — fires on a listen host too, keeping the host's own
  panel in sync.

### Verified
- Listen host (`./run.sh --host`): with a seeded bag (temp hook, removed),
  double-click equips an Elven Sword — it moves to the `[E]` section, leaves the
  bag, and the blade attaches to the `Weapon_R` bone (confirmed via a temp debug
  print: `ATTACHED elven_sword to slot main_hand on bone Weapon_R`, no warning /
  retry). Double-click unequips it back to the bag and detaches the visual
  (`DETACHED slot main_hand`); re-equipping reattaches (proving the detach
  cleared `_attached_items`). Equipping the Axe swaps the Sword back to the bag.
  Headless dedicated boot clean after the temp scaffolding was removed.

## [0.17.0] - 2026-06-13

M15 "Combat & Game Feel": turns the 10-line damage stub into a real combat
system (armor/crit/variance, weapon stats, a click-to-attack basic attack,
and status effects), adds the game-feel layer that was missing (floating
damage numbers for players too, weapon-swing animation, camera shake), and
gives the dungeon an actual atmosphere (a `WorldEnvironment` with fog/glow,
flickering torch lights, per-area lighting presets).

### Added
- Real damage resolution. `systems/combat_system.gd`'s `compute_damage`
  passthrough is replaced by `compute_hit(base, attack_bonus, armor,
  crit_chance, rng) -> {amount, is_crit}`: ±15% variance, a 2x crit roll
  (5% base + gear/enemy bonuses), and flat armor mitigation clamped so a
  connecting hit always lands ≥1. All rolls are server-side; clients only
  ever see the broadcast result.
- Equipment combat stats. `data/equipment_item.gd` gains `attack_damage`,
  `attack_interval`, `attack_range`, `armor`, `crit_chance_bonus`, and a
  `rarity` tier (all inert defaults so old `.tres` load unchanged).
  `equipment_component.gd` exposes server-side aggregation helpers
  (`weapon_*`, `total_attack_bonus/armor/crit_chance`) read from the
  already-replicated `equipped_slots`. Weapons are now differentiated:
  dagger fast/low/high-crit, axe slow/heavy, swords balanced, bow long-range.
- Basic attack. Clicking an enemy (`player_input.gd` ->
  `request_attack_target` RPC, enemy addressed by node name) makes the
  server-authoritative `player_controller.gd` pursue and auto-attack on the
  equipped weapon's interval — a miniature of the enemy AGGRO->ATTACK loop;
  clicking the ground disengages. Each swing plays a procedural weapon
  tween on the `main_hand` bone (`equipment_component.play_swing_tween`) plus
  the existing `sword_swing` SFX, broadcast via `player.on_attack_performed`.
- Status effects. New shared `entities/components/status_effect_component.gd`
  (on players, enemies, and the dragon) implements `poison`, `burn`, `slow`,
  and `stun`, server-authoritative with DoT routed through the normal damage
  path (so ticks broadcast their own numbers and keep kill-XP attribution).
  Active effect ids replicate (`active_effects`, ON_CHANGE + spawn) for the
  HUD. Enemies inflict them via new `EnemyDefinition` fields and `shield_bash`
  now stuns; movement/attacks honor `slow`/`stun`.
- Enemy combat variety, content-only (no new models): goblins attack fast
  and crit, skeletons have armor, zombies inflict poison, the dragon's breath
  applies burn.
- Floating damage numbers and hit feedback for everyone. The enemy-only
  damage label / hit flash are extracted into reusable
  `entities/vfx/damage_number.gd` and `entities/vfx/hit_flash.gd`, now driven
  for players too (`player.on_player_hit` broadcast). Numbers are colored by
  type (physical/poison/burn/heal) and enlarged + gold on crits.
- Camera shake (`camera_rig.shake`): a local-only decaying offset on the
  Camera3D, triggered when the local player is hit (stronger on crits) and
  when they land a crit. Never replicated.
- Dungeon atmosphere. `world.tscn` gains a `WorldEnvironment` (dark ambient,
  ACES tonemap, glow/bloom, depth fog). New
  `entities/world/environment_controller.gd` (client-only) crossfades between
  a dark/foggy dungeon preset and a brighter/warmer town preset based on the
  local player's position, also tuning the lone `DirectionalLight3D`.
- Torch/brazier/candle lights. These props were bare meshes; they now carry a
  warm `OmniLight3D` (no shadows, distance-faded) with `flicker_light.gd`
  sine-flicker (client-only, deliberately unsynced) plus ember particles on
  torches/braziers. Shared `flame_light*.tscn` wrappers.
- Item rarity colors (groundwork). `data/rarity.gd` color map, applied to item
  names in the inventory and shop lists. Mechanically inert until M16.

### Fixed
- `entities/enemy/enemy.gd`: `on_enemy_hit` early-returned on `is_server()`,
  so on a **listen host** (where `is_server()` is true) the host never saw
  enemy hit flashes or damage numbers. Now `is_dedicated_server()` — the same
  listen-host presentation-gating class as the v0.16.0 audit.
- `ui/hud/hud.gd`: the HUD waited for `connected_to_server`, which never fires
  for the listen host itself, so the host's own HUD never populated. It now
  starts searching immediately in `LISTEN_HOST` mode (mirrors the
  character-creation screen's existing special case).
- `entities/player/camera_rig.gd`: the rig is a child of the player body and
  silently inherited the body's movement-driven yaw, so the "fixed-angle"
  camera turned with the character. Set `top_level = true` (all rig
  positioning is already in global space).

### Verified
- Listen host (`./run.sh --host`): created a Mage, walked town -> dungeon
  through the gate portal; confirmed the environment crossfades dark on entry
  and the dungeon reads as warm flickering torch-pools over dark-blue
  ambience with glow on the flames.
- Scripted server-side combat scenario on the host: basic-attack pursuit kills
  a skeleton (armor visibly reducing damage), standing by a zombie applies a
  ticking `POISONED` status (green DoT numbers, HUD label), `shield_bash`-style
  stun + slow freeze/slow a goblin, an equipped Elven Sword's basic attack
  kills a goblin and awards 15 kill XP through the `last_attacker_peer_id`
  path. "You Died / Respawning" + town respawn still work; status effects are
  cleared on death and respawn (caught and fixed a corpse-reburn that ticked a
  respawned player).
- Dedicated server + windowed client (`--server` + default client): client
  created a character and spawned into town with a live HUD; both logs clean.
- Headless dedicated boot is error/warning-free after temp verification
  scaffolding was removed.

## [0.16.0] - 2026-06-11

### Added
- Listen-host mode: a single process can now act as both the authoritative
  server (peer 1) and a playable client, for singleplayer or casual
  "host + friends connect to me" sessions -- the existing dedicated-server
  setup is unaffected and still the recommended way to run a persistent
  server.
  - `bootstrap/network_mode.gd`: new `Mode.LISTEN_HOST`, selected via a
    `--host` launch argument. `is_server()` is true for both
    `DEDICATED_SERVER` and `LISTEN_HOST`; a new `is_dedicated_server()`
    is true only for `DEDICATED_SERVER`; `is_client()` is true for both
    `CLIENT` and `LISTEN_HOST`.
  - `bootstrap/bootstrap.gd`: `--host` boots the normal client scene and
    also starts `NetworkManager.host()`, so the host plays alongside
    connecting clients.
  - `run.sh`: new helper script to launch the project-local Godot binary
    with the right arguments (`--host`, `--connect=`, `--server`,
    `--port=`) for manual testing.

### Fixed
- A self-targeted `rpc_id(1, ...)` from peer 1 to itself (the listen host
  issuing its own gameplay requests, e.g. character creation, movement,
  equip, item use, skill/spell casts, shop trades, storage, chest/loot
  pickup) hard-errored with "RPC on yourself is not allowed by selected
  mode" under `call_remote`. All client -> server request RPCs (and their
  targeted server -> client replies) across `world.gd`,
  `player_input.gd`, and the player components
  (`equipment_component.gd`, `inventory_component.gd`,
  `skill_component.gd`, `spellbook_component.gd`, `shop_component.gd`,
  `level_component.gd`) plus `storage_chest.gd`, `loot_drop.gd`, and
  `chest.gd` are now declared `call_local`, which executes correctly for
  both self-targeted and remote-targeted calls.
- `entities/player/player.gd`: `is_owner` now also requires
  `NetworkMode.is_client()`, so on a listen host the host's own player
  correctly activates its camera and input (previously gated on
  `not is_server()`, which is never true for a listen host).
- `ui/character_creation/character_creation_screen.gd`: the listen host
  shows the character-creation screen immediately on ready, since
  `connected_to_server` (which drives this for regular clients) never
  fires for the host itself.
- Audited every remaining `is_server()`-gated presentation path (model
  visuals, audio init/playback, animation processing, inventory/skill/
  spell UI signals, death/boss VFX and SFX) and switched the ones that
  mean "skip this when headless" to `is_dedicated_server()` or
  `is_client()` as appropriate, across `model_view.gd`,
  `audio_manager.gd`, `equipment_component.gd`,
  `enemy_visual_animator.gd`, `enemy.gd`, `dragon.gd`,
  `inventory_component.gd`, `skill_component.gd`, and
  `spellbook_component.gd` -- so a listen host sees and hears its own
  game world like any other client.

## [0.15.0] - 2026-06-11

### Fixed
- `entities/player/camera_rig.gd`: the boom camera lerped toward the
  player's position every tick, including right after a teleport (death
  respawn or dungeon/town portal). Across the long town<->dungeon
  distances introduced in M14, that lerp couldn't catch up fast enough and
  the character sat outside the camera's view for a beat after
  respawning -- looking like the character had vanished. The camera now
  detects a per-tick jump larger than normal movement (`TELEPORT_DISTANCE`)
  and snaps instantly instead of lerping.

### Added
- Death now drops the player's bag at the death location: `player.gd`'s
  `_on_died()` calls a new `_drop_inventory_on_death()` which spawns a
  `loot_drop` (via `world.spawn_loot_drop`) for each item in
  `InventoryComponent.items` (scattered with a small random offset so
  multiple drops don't fully overlap), then clears the inventory. Equipped
  gear is unaffected. Combined with M14's town respawn, dying lets you walk
  back to where you fell and pick your items back up.

## [0.14.0] - 2026-06-11

### Added
- Starting town hub: a new `Town` subtree in `world.tscn`, centered at
  (-40, 0, 0) and built from extracted Kenney fantasy-town-kit pieces
  (`entities/town/kenney/*.glb`) -- a walled plaza with a fountain, two
  market stalls, a "Dungeon Gate" alcove/archway, fences, trees, lanterns,
  and reused barrel/crate clutter.
- `entities/world/world.gd`: generalized the dungeon's `_dungeon_cells()`
  pattern into shared `_build_navigation_mesh_for_cells()`,
  `_build_floor_colliders_for_cells()`, and
  `_build_wall_colliders_for_cells()` helpers. New `_town_floor_areas()` /
  `_town_cells()` describe the plaza + gate alcove on the same 4-unit cell
  grid (Kenney town-kit pieces scaled 4x to match), feeding a new
  `TownNavigationRegion3D` plus `TownFloorColliders`/`TownWallColliders` --
  the existing dungeon adjacency-based wall-gap algorithm needed zero
  special-casing for the gate opening.
- Gold currency: `StatsComponent.gold` (starts at 100, replicated
  ON_CHANGE alongside hp/mp), shown on the HUD stats bar.
- Item economy: `value: int` added to `EquipmentItem`/`ConsumableItem` and
  set on existing items (`health_potion`=15, `sword`=50, `axe`=60,
  `elven_dagger`=150, `elven_bow`=180, `elven_sword`=200). Buy price =
  `value`, sell price = `value / 2`.
- Shop system: `data/shop_definition.gd` + `GameDatabase.shops`
  (`content/shops/{general_store,blacksmith}.tres`),
  `entities/player/components/shop_component.gd`
  (`request_buy_item`/`request_sell_item` RPCs with gold/inventory
  validation and an `on_trade_rejected` reply), and
  `ui/hud/shop/shop_panel.gd`/`.tscn`.
- Merchant NPCs: `entities/npc/merchant/{merchant_blacksmith,
  merchant_general_store}.tscn` (converted dwarf/wizard models) standing at
  the two stalls; interacting opens the shop panel for that merchant's
  stock.
- Personal storage chest: `entities/items/storage_chest/storage_chest.gd`/
  `.tscn`, server-only per-peer `_storage` dict (never replicated),
  `request_open_storage`/`request_deposit_item`/`request_withdraw_item`
  RPCs + targeted `on_storage_updated` reply, and
  `ui/hud/storage/storage_panel.gd`/`.tscn`.
- Dungeon <-> town teleport portals: `entities/world/area_portal.gd`/
  `.tscn` (server-only `Area3D`, reuses `player_controller.gd.reset_to()`
  -- the same mechanism as respawn). `PortalToDungeon` (town gate alcove ->
  EntryRoom) and `PortalToTown` (EntryRoom -> town plaza).
- New `TownSpawn1`/`TownSpawn2` markers inserted as `SpawnPoints[0..1]`
  (existing dungeon spawns shift to indices 2-5). New characters and
  post-death respawns (`get_spawn_position(0)`) now place players in the
  town plaza; `world.gd` cycles new characters through the two town spawns
  (`TOWN_SPAWN_COUNT`) to avoid coincident spawns.

### Fixed
- `storage_chest.gd`: `_storage.get(peer_id, [])` can't be assigned to an
  `Array[StringName]`-typed local (the `[]` default is an untyped `Array`,
  which fails Godot's typed-array runtime check) -- threw a script error on
  every player's first storage interaction. Replaced with a shared
  `_stored_items()` helper used by all three storage RPC handlers.

### Verified
- Headless server + 2 clients on localhost: both new characters spawned in
  the town plaza at `TownSpawn1`/`TownSpawn2` (not the dungeon). Walking
  into the Dungeon Gate alcove teleported the player to the EntryRoom
  (`PortalToDungeon` -> the old `Spawn1` position), and walking into the
  EntryRoom portal teleported back to `TownSpawn1` (`PortalToTown`).
  Buying/selling at the general store and blacksmith adjusted gold
  correctly (100 -> 85 -> 92 -> 42 across a potion buy/sell and a sword
  purchase); an over-budget purchase was rejected with "Not enough gold"
  and left gold/inventory unchanged. Each player's storage chest opened
  empty, round-tripped a deposited item back to inventory, and the
  server's `_storage` ended as `{peerA: [], peerB: [item]}` -- confirming
  per-peer privacy. `_build_town_*` produced zero navmesh edge-error
  warnings, and a clean dual-boot restart logged zero script
  errors/warnings.

## [0.13.0] - 2026-06-11

### Added
- Dragon boss in the Boss Chamber: `content/enemies/dragon.tres` (500 HP, 20
  melee damage, `is_boss=true`). `EnemyDefinition` gained boss-only fields
  (`is_boss`, `phase2_hp_ratio`, `fire_breath_damage`, `fire_breath_range`,
  `fire_breath_cone_degrees`, `fire_breath_cooldown`), copied into
  `enemy_stats_component.gd` like the existing stats.
  `entities/enemy/boss/dragon.tscn` is a standalone `CharacterBody3D` (larger
  `CapsuleShape3D`, radius 1.2 / height 5.4) with
  `entities/enemy/boss/dragon_controller.gd` extending
  `enemy_controller.gd`: at <= `phase2_hp_ratio` HP the dragon also fires a
  cone fire-breath (`world.gd.apply_cone_hit`) at players within
  `fire_breath_range`/`fire_breath_cone_degrees`, on its own cooldown, in
  addition to its existing melee attack. `entities/enemy/boss/dragon.gd`
  (extends `enemy.gd`) adds a broadcast `on_dragon_breath` RPC that plays the
  attack animation, the `dragon_roar` SFX, and spawns
  `entities/vfx/fire_breath.tscn` (a one-shot cone `GPUParticles3D` +
  `OmniLight3D`) oriented along the dragon's facing.
- Goblin and Zombie enemies: `content/enemies/{goblin,zombie}.tres` (goblin:
  25 HP/4 dmg/fast skirmisher; zombie: 80 HP/10 dmg/slow brute, drops a health
  potion). Models converted from `MyAssets/dungeon-pack1.zip` via
  `MyAssets/scripts/convert_dungeon_pack1.py` into
  `entities/enemy/{goblin,zombie}/{goblin,zombie}.glb`, wrapped in
  `*_visual.tscn` instance scenes.
- Enemy animations: new `entities/enemy/components/enemy_visual_animator.gd`
  (`Animator` node added to `entities/enemy/enemy.tscn`) finds an
  `AnimationPlayer` inside the enemy's instantiated visual scene and drives
  `idle`/`walk` (looping, based on movement) plus one-shot `attack`/`death`
  clips. `enemy.gd` gained a broadcast `on_attack_performed` RPC (called from
  `enemy_controller.gd._process_attack` alongside existing damage
  application) and `on_died` now tries `_animator.play_death()` before
  falling back to the old scale-to-zero tween. Goblin, zombie, and dragon all
  ship with idle/walk/attack/death clips; the dragon's came from actions
  already present in its source `.blend` (no DAE retargeting needed).
- Floor-completion flow: `entities/world/exit_portal.tscn`/`.gd` is a hidden,
  inert swirling-vortex `Area3D` (`GPUParticles3D` + `OmniLight3D`) placed in
  the Boss Chamber. `enemy.gd.on_died` calls the new
  `world.gd.activate_exit_portal()` for `is_boss` enemies, making it visible
  and (server-only) starting to listen for `body_entered`. Walking into it
  triggers a new targeted `world.gd.on_floor_cleared(xp_reward)` RPC, bridged
  to a `floor_cleared` signal the HUD uses to show
  `ui/hud/floor_cleared/floor_cleared_overlay.tscn` ("Floor Cleared! +500
  XP", fades out after a hold).
- Boss health bar: `ui/hud/boss_health_bar/boss_health_bar.tscn`/`.gd` is a
  top-center `TextureProgressBar` (Kenney red bar) showing "Dragon HP N / N",
  hidden until the local player enters the new `World/BossChamberArea`
  (`Area3D`), wired up in `hud.gd`.
- World layout: 6 new `EnemySpawnPoints` markers (`EnemySpawn5-10`) for the 3
  goblins (Side Room A), 2 zombies (Hub), and the dragon (Boss Chamber).
  `world.gd`'s hardcoded skeleton-only initial spawn loop is replaced by a
  10-entry `INITIAL_ENEMY_SPAWNS` roster (4 skeleton warriors, 3 goblins, 2
  zombies, 1 dragon); `_spawn_enemy` instantiates
  `entities/enemy/boss/dragon.tscn` for the dragon definition id.
- Audio: new `dragon_roar` SFX (`audio/sfx/dragon_roar.ogg`, CC0, recorded in
  `audio/ATTRIBUTION.md`), played on the dragon's fire-breath RPC.

### Verified
- Headless server + 1 client on localhost: `GameDatabase.enemies` has
  `goblin`/`zombie`/`dragon`; `World/Enemies` spawned all 10
  `INITIAL_ENEMY_SPAWNS` entries with the expected `definition_id`s
  (`Enemy_9` = dragon, 500/500 HP). A debug area-hit dropped the dragon to
  249/500 HP, flipping `dragon_controller._is_phase2()` to true. A subsequent
  `apply_cone_hit` along the dragon's facing dealt the full
  `fire_breath_damage` (15) to a player positioned in the cone, and zero
  damage to one positioned behind it. `on_attack_performed` and
  `on_dragon_breath` both left `current_animation == "attack"` on the
  dragon's `AnimationPlayer`, confirming the converted dragon GLB's clip
  naming. Killing the dragon fired `on_died`, which set `is_boss`-driven
  `activate_exit_portal()`: the `ExitPortal` became visible, its
  `GPUParticles3D` started emitting, and (server-only) `monitoring` turned
  true. Walking the player into the portal delivered
  `on_floor_cleared(500)` to that client, surfacing the "Floor Cleared!"
  overlay text. Walking the player into/out of `BossChamberArea` toggled the
  client's `BossHealthBar.visible` while `HpLabel` continued to reflect the
  replicated `Dragon HP 0 / 500`. Zero script errors; only the pre-existing
  navmesh edge-merge warning.

## [0.12.0] - 2026-06-10

### Added
- M12 VFX & UI polish: `res://assets/` (new top-level dir) holds 2 RPicster CC0
  particle textures (`vfx_textures/effect_1.png`, `effect_3.png`), 2 OFL
  Google Fonts (`fonts/Cinzel-Variable.ttf`, `fonts/MedievalSharp.ttf`), and
  6 Kenney CC0 UI textures (`ui/kenney_fantasy_borders/panel-009.png`,
  `ui/kenney_ui_rpg/{buttonLong_brown,buttonLong_brown_pressed,
  barRed_horizontalMid,barBlue_horizontalBlue,barBack_horizontalMid}.png`),
  all recorded in `res://assets/ATTRIBUTION.md`.
- Fireball projectile VFX: `Spell` gained an optional
  `projectile_vfx: PackedScene` field (set on `content/spells/fireball.tres`).
  `entities/vfx/fireball_projectile.tscn`/`.gd` is a glowing orange
  `GPUParticles3D` projectile with an `OmniLight3D` and a trailing particle
  stream; `spellbook_component.gd._maybe_spawn_projectile_vfx` (client-only)
  spawns one under `World` on `on_spell_cast`, travelling toward the nearest
  in-range enemy and exploding into an impact burst on arrival.
- Enemy hit-flash + floating damage numbers: `enemy_health_component.gd`
  gained a `hit(amount)` signal (emitted from `apply_damage` before HP
  reaches zero); `enemy.gd` broadcasts a new
  `on_enemy_hit(amount)` RPC that, on every client, flashes the enemy's mesh
  white via a transient `material_overlay` tween and spawns a fading
  `Label3D` damage number (Cinzel font) above the enemy.
- Enemy death particle burst: `entities/vfx/death_burst.tscn`/`.gd` is a
  one-shot bone/smoke `GPUParticles3D` burst, spawned under `World` by
  `enemy.gd.on_died` on every client.
- Dark-fantasy UI theme: `ui/theme/dungeon_theme.tres` (new `Theme` resource)
  styles `Panel`/`PanelContainer` with a tinted Kenney stone border, `Button`
  with Kenney brown button textures (normal/hover/pressed), and
  `Label`/`Button` text in Cinzel with a parchment font color. Applied to
  every top-level HUD panel (`ui/hud/hud.tscn`) and the character-creation
  screen (`ui/character_creation/character_creation_screen.tscn`, whose title
  now uses MedievalSharp at a larger size).
- `ui/hud/stats_bar/`: HP/MP are now Kenney `TextureProgressBar`s (red/blue
  fill over a back-plate texture) with an overlay label retaining the
  existing "`%d / %d`" readout; the level label uses a Cinzel `wght=700`
  `FontVariation`.

### Verified
- Headless server + 2 clients on localhost: `dungeon_theme.tres` loads and
  `StatsBar/VBox/HpBar` is a `TextureProgressBar` with non-null
  `texture_under`/`texture_progress`. A debug Mage cast `fireball` near a
  weakened skeleton warrior: `_maybe_spawn_projectile_vfx` spawned a
  `FireballProjectile` targeting the nearest enemy on both clients;
  `on_enemy_hit(30)` fired (and the hit-flash/damage-label code ran) for
  every enemy in the area-of-effect; the killed enemy's `on_died` spawned a
  `DeathBurst` under `World` on both clients. Zero script errors; only the
  pre-existing navmesh edge-merge warning.

## [0.11.0] - 2026-06-10

### Added
- M11 audio layer: new `AudioManager` autoload (`systems/audio_manager.gd`,
  registered last so `NetworkMode` is ready first), client-only (`_ready()`
  returns early `if NetworkMode.is_server()`). Preloads 9 curated CC0 audio
  files (`res://audio/{sfx,music,ambient}/*.ogg`, provenance in
  `res://audio/ATTRIBUTION.md`) into `_streams`. `play_sfx(key)` fires a
  one-shot on a round-robin pool of 8 `AudioStreamPlayer`s; `play_music(key)`
  crossfades between two players over 1 s via `Tween`; `play_ambient(key)`
  starts a single looping ambience player (`loop`/`loop_mode` set on load for
  `AudioStreamOggVorbis`/`AudioStreamMP3`/`AudioStreamWAV`).
- SFX hooks wired across gameplay: `hud.gd` plays `sword_swing` on
  `SkillComponent.skill_cast`, `spell_cast` on
  `SpellbookComponent.spell_cast`, `spell_learn` on `spell_learned`, and
  `ui_click` on each I/Q/T/M panel toggle; `inventory_component.gd` plays
  `item_pickup` when `items` grows; `enemy.gd.on_died` plays `enemy_death` on
  every client; `model_view.gd` plays a looping `footstep_stone` every 0.4 s
  while `Controller.move_blend` exceeds 0.1; `world.gd._ready()` starts
  `dungeon_ambience` (looping ambience) and `dungeon_explore` (looping music)
  on every client.
- New playable class: Rogue (`content/classes/rogue.tres`, 100 HP / 60 MP /
  8 INT, starts with `backstab`). New skill `content/skills/backstab.tres`
  (15 MP, 2.5 s cooldown, 1.5 m range, 30 dmg, 30 XP).
- `SkillUnlockSystem.newly_unlocked_at` gained a level-2 table: Warrior ->
  `shield_bash` (`content/skills/shield_bash.tres`: 10 MP, 4 s cooldown, 2 m
  range, 20 dmg, 20 XP), Rogue -> `evasion`
  (`content/skills/evasion.tres`: 20 MP, 8 s cooldown, 0 range/damage —
  placeholder effect, `request_use_skill` already skips `apply_area_hit` for
  zero-damage skills).
- Two new spells: `content/spells/ice_lance.tres` (INT >= 8, 40% base chance,
  25 MP, 3.5 s cooldown, 8 m range, 35 dmg) and
  `content/spells/thunder_bolt.tres` (INT >= 12, 35% base chance, 35 MP, 5 s
  cooldown, 10 m range, 50 dmg). A new `SpellScroll_IceLance` in the Boss
  Chamber (`entities/world/world.tscn`, position (-4, 0.125, 16)) teaches
  `ice_lance`.
- Three new elven weapons exported from
  `MyAssets/elven_weapon_set_by_pfunked.zip`
  (`ElvenLongSword`/`ElvenBow`/`ElvenShortSword`) as
  `entities/items/weapons/{elven_sword,elven_bow,elven_dagger}/*.glb+.tscn`
  and `content/items/{elven_sword,elven_bow,elven_dagger}.tres`
  (`EquipmentItem`, `slot = &"main_hand"`), following the existing
  `health_potion.tscn` GLB-wrapper pattern.

### Verified
- Headless server + 2 clients on localhost: `GameDatabase.classes.size() ==
  3` (warrior/mage/rogue); a Rogue character spawns with
  `SkillComponent.known_skill_ids == [&"backstab"]`. Driving a Warrior and a
  Rogue to level 2 via `power_strike`/`backstab` XP grants `shield_bash` and
  `evasion` respectively through `leveled_up`. A Mage walks to
  `SpellScroll_IceLance` and learns `ice_lance`. `equipment_component.
  request_equip(&"main_hand", &"elven_sword"/"elven_bow"/"elven_dagger")`
  attaches each visual via `BoneAttachment3D` with no warnings on both
  clients. `AudioManager._streams` holds all 9 keys with non-null streams
  (no missing-file warnings); `dungeon_ambience` and `dungeon_explore` are
  both `playing` after world `_ready()`; casting `power_strike` plays
  `sword_swing` on an SFX-pool player. Zero script errors; only the
  pre-existing navmesh edge-merge warning.

## [0.10.0] - 2026-06-10

### Added
- M10 loot, inventory & consumables: loot drops are now collectible into a
  real per-player inventory, chests can be opened to spawn loot, and health
  potions heal HP from a now-functional inventory panel.
- New `ConsumableItem` Resource (`data/consumable_item.gd`): id, display_name,
  `use_effect: Dictionary` (e.g. `{&"restore_hp": 40}`), visual_scene. Coexists
  with `EquipmentItem` in `GameDatabase.items` — `_load_category` is duck-typed
  on `id`, so no shared base-class refactor was needed. First content:
  `content/items/health_potion.tres` (+40 HP), with a world-pickup mesh
  exported from `MyAssets/from_opengameart/OGA_Potions_by_unknown.blend`
  (`entities/items/potions/health_potion.glb`/`.tscn`).
- `ItemUseSystem` (`systems/item_use_system.gd`): pure-function
  `can_use(item_id, items)`/`apply_use(item_id, stats)`, same shape as
  `SkillUseSystem` — interprets `use_effect` keys (`restore_hp`/`restore_mp`)
  against `StatsComponent`, capped at `max_hp`/`max_mp`.
- `InventoryComponent` (`entities/player/components/inventory_component.gd`):
  replicated ON_CHANGE+spawn=true `items: Array[StringName]`. Server-only
  `add_item(item_id)` (called directly by loot pickup); `request_use_item`
  any_peer RPC validates ownership and `ItemUseSystem.can_use`, applies the
  effect, and removes the item — mirroring `skill_component`'s
  request/validate/mutate pattern with a targeted `on_item_use_rejected` RPC.
- Loot drop (`entities/items/loot_drop/loot_drop.gd`) rewritten for real
  pickup: `request_pickup` resolves the requesting peer's `Player_<id>` node,
  hands the item to its `InventoryComponent`, and despawns. `_ready()` swaps
  the placeholder sphere for the item's `visual_scene` when one is defined.
- Chest prop (`entities/items/chest/`): `chest_model.glb` exported from
  `MyAssets/chest3-final.blend` (rigged, with `Open`/`Close` animations).
  `chest.gd` opens once per session — `request_open` (any_peer) ->
  `on_chest_opened` (authority, call_local broadcast) plays the `Open`
  animation on every connected peer and spawns 2x `health_potion` via
  `world.spawn_loot_drop`. Two chests placed in `world.tscn` (Side Room A and
  Side Room B), using the existing `interact(player)` raycast dispatch — no
  input-handling changes needed.
- Inventory UI (`ui/hud/inventory/`): the placeholder panel is now an
  `ItemList`. `inventory_panel.gd` groups duplicate item ids by count for
  display ("Health Potion x2"); double-clicking a row sends
  `request_use_item` to the server. Wired up in `hud.gd._connect_to_player`
  alongside the other per-player components.
- `player.tscn`/`player.gd._setup_replication` gained `InventoryComponent` as
  a new ON_CHANGE+spawn=true replicated property, same as `equipped_slots`.

### Verified
- Headless server + 2 clients on localhost: client A opens a chest, the
  `Open` animation plays in sync on both clients (confirmed via a brief poll
  of `AnimationPlayer.current_animation` on client B, since the 1 s
  non-looping clip resets to `""` once finished); 2 health potions spawn near
  the chest. Client A picks up both, its inventory shows
  `[health_potion, health_potion]`. With HP reduced to 50/150, using a potion
  heals to 90/150 (capped at `max_hp`) and leaves one potion in the inventory.
  Client B observes the same HP and inventory state for client A (cross-peer
  replication), while its own inventory remains empty (per-player scoping,
  not shared/global). Zero script errors; only the pre-existing navmesh
  edge-merge warning.

## [0.9.0] - 2026-06-10

### Added
- M9 enemy combat loop: server-authoritative AI enemies that patrol, aggro,
  attack, can be killed by player skills/spells, and drop loot.
- `CombatSystem.compute_damage(base_damage)` (`systems/combat_system.gd`) —
  pure damage-resolution helper shared by player skills/spells and enemy
  attacks; currently a clamped passthrough, the single seam for future
  modifiers (defense, crit, resistance).
- New `EnemyDefinition` Resource (`data/enemy_definition.gd`): id,
  display_name, max_hp, attack_damage, move_speed, aggro_radius,
  attack_range, xp_reward, loot_item_id, visual_scene. First enemy:
  `content/enemies/skeleton_warrior.tres` (40 HP, 8 dmg, 6 m aggro radius,
  drops `bone_shard`). `GameDatabase` gained an `enemies` category.
- Enemy entity (`entities/enemy/`): `CharacterBody3D` + `NavigationAgent3D`
  driven by a server-only `enemy_controller.gd` state machine (IDLE -> PATROL
  -> AGGRO -> ATTACK), with `enemy_health_component.gd`
  (hp/max_hp, ON_CHANGE+spawn=true replicated, server-only `apply_damage`)
  and `enemy_stats_component.gd` (server-only combat stats). `enemy.gd`
  orchestrates initialization from `GameDatabase.enemies`, broadcasts
  `on_died` (`@rpc("authority","call_local","reliable")`) for a synchronized
  death tween, awards XP to the killer's `LevelComponent`, spawns a loot drop,
  and despawns via `queue_free()` (replicated automatically by
  `MultiplayerSpawner`). Spawned at 4 new `EnemySpawnPoints` markers (3 in
  Side Room B, 1 in the Boss Chamber) via a new `EnemySpawner`.
- `Skill`/`Spell` gained `range`/`damage_base` fields (`power_strike`: 2.5 m /
  15 dmg; `fireball`: 8 m / 30 dmg). `skill_component.gd`/
  `spellbook_component.gd` call new `world.gd.apply_area_hit(origin, range,
  damage, attacker_peer_id)`, which applies `CombatSystem.compute_damage` to
  every enemy in range.
- Loot drop entity (`entities/items/loot_drop/`): a `StaticBody3D` pickup
  spawned via a new `LootSpawner`/`world.gd.spawn_loot_drop`, mirroring
  `spell_scroll.gd`'s `interact(player)` -> `rpc_id(1, ...)` pattern;
  `request_pickup` prints `"[loot] picked up <item_id>"` and despawns.
  `StaticBody3D` (not the plan's tumbling `RigidBody3D`) since the dungeon
  has no floor colliders for it to land on — consistent with the existing
  spell-scroll prop pattern.

### Notes
- `skeleton_warrior`'s visual (`entities/enemy/skeleton_visual.tscn`) is a
  placeholder bone-white capsule+sphere — the KayKit Skeletons pack remains
  blocked behind an itch.io login (see M8 notes). Swap in the real model once
  available; no other code changes needed.

### Verified
- Headless server + 2 simultaneous clients on localhost: both connect and
  spawn (Elf Warrior / Dark Elf Mage); the warrior walks to the Boss Chamber
  and casts `power_strike` on the skeleton there; the mage, watching the same
  enemy from across the map, observes its replicated HP drop in lockstep
  (40 -> 25 -> 10 -> 0); on death the enemy plays its despawn tween and is
  removed on both peers; the warrior gains XP and levels up (2); a loot drop
  spawns at the death position and replicates to both peers; the warrior
  picks it up and the server prints `[loot] picked up bone_shard`. Zero
  script errors; the only warning is the pre-existing M8 navmesh edge-merge
  warning.

## [0.8.0] - 2026-06-10

### Added
- M8 real dungeon level: replaced the flat test arena
  (`entities/world/world.tscn`) with a hand-crafted 4-room dungeon built from
  the Kenney Modular Dungeon Kit (CC0 GLBs in `entities/dungeon/kenney/`) —
  Entry Room, a corridor to Side Room A, a corridor/hub/corridor run to Side
  Room B, and a corridor down to the Boss Chamber. 9 piece instances placed
  on a 4-unit grid with rotations derived from each piece's local opening
  orientation.
- 8 atmosphere props extracted from the Kenney prop pack into standalone
  `entities/dungeon/props/*.tscn` scenes (torch, barrel, crate, two chests,
  candle, brazier, weapon rack) and scattered through the dungeon.
- `world.gd._build_dungeon_navigation_mesh` replaces the single flat-plane
  navmesh with a procedural union of 4×4 unit grid cells (`_dungeon_cells`)
  whose shared corner vertices are deduplicated to the same vertex index —
  every room/corridor polygon connects edge-to-edge into one walkable mesh
  with no baking step, verified via direct `NavigationServer3D.map_get_path`
  queries across all 9 areas.
- `SpawnPoints` (4 `Marker3D`s) replace the single spawn location; the
  training dummy moved to the Entry Room and the fireball spell scroll moved
  to Side Room A.

### Fixed
- `world.gd._spawn_player` slotted spawn position by `peer_id % N`, which can
  collide for two simultaneously-spawning peers whenever their (effectively
  random) ENet ids share a residue mod `N` — a recurrence of the coincident-
  spawn `move_and_slide()` collision explosion from [[lessons_multiplayer_replication]]
  lesson 4. Fixed by passing a server-assigned sequential `spawn_index`
  (`_players_root.get_child_count()` at spawn time) through the spawn `data`
  dict and slotting by that instead — guaranteed distinct for any concurrent
  spawns up to the spawn-point count.
- `level_component.gd`'s level-up skill-unlock branch
  (`var updated := skill_comp.known_skill_ids.duplicate()`) failed to compile
  — GDScript can't infer a type from a `Variant`-typed property access — which
  made `load(PLAYER_SCENE).instantiate()` return a `LevelComponent` with no
  script attached, so `_spawn_player`'s `.initialize()` call threw "Nonexistent
  function 'initialize' in base 'Node'" and **every** character-creation
  request failed server-side. Fixed by explicitly typing
  `updated: Array[StringName]`.

### Verified
- Headless server + 2 clients on localhost: both connect, create characters
  (Elf Warrior / Dark Elf Mage), spawn at distinct spawn points, and
  successfully navigate via `NavigationAgent3D` through corridors to Side
  Room A and the Boss Chamber respectively — final position within 1 m of
  target in both cases, no collision or physics anomalies.

## [0.7.0] - 2026-06-09

### Added
- M7 spell-learning loop: closes the vertical slice end-to-end (connect →
  create character → equip gear → fight → level up → unlock skill →
  **learn a spell from a scroll**).
- New `Spell` Resource (`data/spell.gd`): `id`, `display_name`,
  `int_requirement`, `base_chance`, `mp_cost`, `cooldown_seconds`.
  First spell: `content/spells/fireball.tres` (INT ≥ 5, 50 % base chance,
  20 MP cost, 3 s cooldown).
- `SpellLearningSystem.attempt_learn(spell, intelligence, rng)` pure static
  function (`systems/spell_learning_system.gd`): threshold = base_chance +
  (INT − int_requirement) × 0.05, clamped to [0.05, 0.95]. Returns
  `{success, roll, threshold}`. Server calls it authoritatively; client may
  call the same function for an odds preview — server always re-rolls
  independently and the client's number is never trusted.
- `SpellbookComponent` (`entities/player/components/spellbook_component.gd`):
  replicated ON_CHANGE+spawn=true `known_spell_ids: Array[StringName]`;
  `request_read_scroll` any_peer RPC → server validates ownership/existence/
  duplicate, calls `SpellLearningSystem.attempt_learn`, mutates
  `known_spell_ids` on success, sends targeted `on_learn_result` RPC
  (private: contains roll/threshold detail, not broadcast to all peers);
  `request_cast_spell` validates known/cooldown/MP, deducts MP, sets
  cooldown, broadcasts `on_spell_cast`.
- `StatsComponent` gained `intelligence: int` stat (replicated
  ON_CHANGE+spawn=true), initialised from `CharacterClass.base_stats`
  `&"intelligence"` key. Mage = 15, Warrior = 5.
- `SpellScroll` world prop (`entities/items/scroll/spell_scroll.gd`):
  a `StaticBody3D` with `@export spell_id`; clicking it calls
  `interact(player)` → `spellbook.request_read_scroll.rpc_id(1, spell_id)`.
  One fireball scroll placed in the test arena at (−3, 0.125, −2).
- `player_input._handle_click` now checks for an `interact` method on the
  clicked collider (or its parent) before falling through to `request_move_to`
  — a general interactable dispatch hook reusable for chests, NPCs, etc.
- Hotbar extended: skills fill slots first, then known spells fill remaining
  slots; pressing a bound key dispatches to `SkillComponent.request_use_skill`
  or `SpellbookComponent.request_cast_spell` depending on slot type.
- HUD wired to `SpellbookComponent`: `spells_changed` → hotbar refresh;
  `spell_learned` → console feedback with roll/threshold detail.
- `player.gd._setup_replication` extended with 2 new ON_CHANGE+spawn=true
  properties: `StatsComponent:intelligence`, `SpellbookComponent:known_spell_ids`.
- `world.gd._spawn_player` calls `SpellbookComponent.initialize(class_def)`
  (no-op; reserved for future starter-spell tables).

## [0.6.0] - 2026-06-09

### Added
- M6 stats/level/skill loop + hotbar UI: the first complete "use a skill →
  gain XP → level up → unlock skills" pipeline, networked end-to-end.
- New `Skill` Resource (`data/skill.gd`): `id`, `display_name`, `mp_cost`,
  `cooldown_seconds`, `xp_reward`. First skill: `content/skills/power_strike.tres`
  (Warrior only, free cast, 2 s cooldown, 25 XP per use).
- New `LevelCurve` Resource (`data/level_curve.gd`): `xp_per_level` array
  (index 0 = XP to advance from level 1 to 2, etc.).
  `content/level_curves/default_curve.tres` — 100/250/450/700/1000/… XP curve.
- `CharacterClass` gained `base_stats: Dictionary` (StringName → int, e.g.
  `{&"max_hp": 150, &"max_mp": 30}`), `starting_skill_ids: Array[StringName]`,
  and `level_curve_id: StringName`. Warrior/Mage `.tres` files updated.
- Three new pure-function systems under `systems/`:
  - `XPSystem.compute_gain` — deterministic XP→level math, shared client/server.
  - `SkillUnlockSystem.newly_unlocked_at` — returns skills granted at a given level.
  - `SkillUseSystem.can_use` — validates skill_id, cooldown, and MP cost.
- Three new player components under `entities/player/components/`:
  - `StatsComponent` (`hp`/`max_hp`/`mp`/`max_mp`): initialised from class
    `base_stats`; replicated ON_CHANGE+spawn=true; `hp_changed`/`mp_changed`
    signals drive the HUD stats bar.
  - `LevelComponent` (`level`/`current_xp`): server-only `gain_xp(amount)`;
    replicated ON_CHANGE+spawn=true; `on_level_up` RPC delivers new-level +
    newly-unlocked skill list to the owning peer only.
  - `SkillComponent` (`known_skill_ids`): replicated ON_CHANGE+spawn=true;
    `request_use_skill` intent RPC; `on_skill_cast` authority+call_local
    broadcast (all peers + server see the trigger); `on_skill_rejected` targeted
    RPC for the requesting peer. Cooldowns (`_cooldowns` dict) are server-only
    and never replicated. Deducts MP, sets cooldown, calls `gain_xp`, then
    broadcasts `on_skill_cast` — one atomic server-side sequence per use.
- `world.gd._spawn_player` now initialises all three components from the class
  def (deterministic on every peer, same as race/class identity fields; harmless
  if the MultiplayerSynchronizer spawn snapshot overwrites them with live values
  for late joiners).
- `player.gd._setup_replication` extended with 7 new ON_CHANGE+spawn=true
  properties: `StatsComponent:{hp,max_hp,mp,max_mp}`,
  `LevelComponent:{level,current_xp}`, `SkillComponent:known_skill_ids`.
- Training dummy prop added to `entities/world/world.tscn` (capsule mesh at
  position (4,0,0)) — visual reference target for skill use; no collision or
  interaction logic needed since XP accrues on any valid skill cast.
- HUD (`ui/hud/hud.tscn` + `hud.gd`): client-only CanvasLayer that polls
  `World/Players/Player_<peer_id>` once per frame until found, then connects
  to component signals for live updates. Children:
  - `StatsBar` — top-left panel: Level / HP / MP labels.
  - `Hotbar` — bottom-centre: 10 slots (keys 1–0), populated from
    `SkillComponent.known_skill_ids`; pressing a bound key calls
    `request_use_skill` on the owning peer's SkillComponent.
  - Placeholder panels (hidden by default): Inventory (I), Quest Log (Q),
    Travel (T), Map (M) — all toggled via new Input Map actions. Full content
    arrives in M7+.
- 14 Input Map actions added to `project.godot`:
  `hotbar_1`–`hotbar_9`, `hotbar_0` (keys 1–0),
  `toggle_inventory` (I), `toggle_quest_log` (Q),
  `toggle_travel` (T), `toggle_map` (M).
- HUD added to `net/client_main.tscn`.

### Verified
- Headless server + 1–2 clients on localhost (manual verification):
  character spawns with correct HP/MP from class (Warrior 150/30, Mage 80/120);
  Warrior hotbar slot 1 shows "Power Strike"; pressing 1 sends
  `request_use_skill` → server validates → deducts cooldown, awards 25 XP →
  broadcasts `on_skill_cast` (print visible in all terminals); after 4 uses
  (100 XP) level increments to 2 (replicated, visible in stats bar);
  `on_level_up` RPC arrives at the owning peer; cooldown rejection fires if
  key is pressed again within 2 s; I/Q/T/M toggle the placeholder panels.
  Late joiner reconstructs correct level, XP, and known skills from spawn
  snapshot with zero history replay.

## [0.5.0] - 2026-06-08

### Added
- M5 equipment visual replication: players can now equip weapons mid-session
  and have the change appear on every peer's screen, including late joiners —
  the first system that mutates a character's *appearance* after spawn rather
  than riding the one-shot creation `data` dict. New `EquipmentItem` `Resource`
  (`data/equipment_item.gd`, id/display_name/slot/visual_scene) loaded as
  `.tres` content (`content/items/{sword,axe}.tres`); `RaceModel` gained
  `attachment_points: Dictionary[StringName, StringName]` (slot -> bone name,
  e.g. `{&"main_hand": &"Weapon_R"}`), authored per-race since rigs differ
  (Elf also has `Weapon_L`/`Arrow`, Dark Elf has neither).
- First `systems/*.gd` pure-function module:
  `EquipValidationSystem.can_equip(item_id, slot)` — validates item existence
  and slot match, returns `""` on success or a rejection reason. Narrow on
  purpose, like M4's `CharacterClass` deferring `base_stats`: stat/level
  gating waits for `StatsComponent`/`LevelComponent` (M6/M7) and will extend
  this signature additively, not rewrite it.
- New `entities/player/components/equipment_component.gd` (first module under
  a `components/` layout `stats_`/`skill_component.gd` will follow), wired as
  a sibling of `Controller`/`Input` in `player.tscn`. Implements the
  established request -> validate -> mutate -> broadcast pattern:
  `request_equip` (`@rpc("any_peer")`) checks sender ownership via a new
  public `player.gd.owning_peer_id()` accessor (promoted from the private
  `_owning_peer_id()` so siblings can reuse it without duplicating the
  name-parsing) and `EquipValidationSystem.can_equip`, then mutates
  `equipped_slots` and broadcasts `on_equip_changed` (`@rpc("authority")`,
  deliberately no `call_local` — the headless server has nothing to attach a
  visual to). `_attach_visual_for_slot` frees any prior `BoneAttachment3D` for
  the slot, then resolves item -> `visual_scene` and race -> bone name purely
  from ids via `GameDatabase` (mirroring how `model_view.gd` re-resolves
  `race_id` locally) and parents a fresh `BoneAttachment3D` under the
  `Skeleton3D` found via `find_child`.
- Late-joiner reconciliation: `equipped_slots` rides the existing
  `MultiplayerSynchronizer` (spawn=true, `REPLICATION_MODE_ON_CHANGE` — rare
  changes, unlike position/rotation/move_blend's `ALWAYS`) with a `: set`
  property setter that re-drives `_attach_visual_for_slot` for every entry
  whenever the dict is replaced wholesale (which only the synchronizer does —
  the server's own `request_equip` mutates in place, deliberately not
  triggering its own setter, since the headless server has no visuals to
  drive). **Spike finding**: the setter approach won — confirmed empirically
  to fire for both the late-joiner spawn snapshot and live updates — but it
  fires *very* early on a freshly-instantiated late-joiner node: before
  `@onready` vars are populated and even before `get_parent()` resolves (the
  node isn't parented yet). `_attach_visual_for_slot` therefore re-fetches
  `get_parent()` fresh each call and `call_deferred`-retries itself if either
  the player or its `Skeleton3D` isn't resolvable yet — `_attached_items`
  keeps every retry/dual-path (setter + `on_equip_changed` RPC can both fire
  for the same change) idempotent. Recorded in
  [[lessons_multiplayer_replication]] as a new ordering hazard to watch for.

### Verified
- Headless server + up to 3 clients on localhost, all 6 scenarios from the
  M5 plan: single-client equip (sword visible at the hand bone); cross-peer
  visibility (peer A sees peer B's correct weapon and vice versa, proving
  per-peer `GameDatabase` re-resolution rather than local echo); late joiner
  (a third client reconstructs both existing characters' weapons with zero
  history replay — the exact behavior the spawn-snapshot setter spike needed
  to deliver); validation (`Unknown item.` for an unrecognized id, `That item
  doesn't go in that slot.` for a slot mismatch, and a silent server-side
  rejection — logged only as a server warning, no feedback RPC — for a
  non-owning peer attempting to equip another character); and re-equip
  (sword -> axe leaves exactly one `BoneAttachment3D` attached, the old one
  freed rather than stacked). Temporary CLI-flag-gated debug harness
  (`--debug-equip=`/`--debug-equip-attack=` in `world.gd`) fully removed
  after verification.

## [0.4.0] - 2026-06-07

### Added
- M4 character creation over the network: replaced the placeholder
  spawn-on-connect (hardcoded to the Elf race) with a real client-driven
  creation flow. New `RaceModel`/`CharacterClass` `Resource` subclasses
  (`data/race_model.gd`, `data/character_class.gd`) authored as `.tres`
  content (`content/races/{elf,dark_elf}.tres`, `content/classes/{warrior,mage}.tres`)
  and loaded through `GameDatabase` — the project's first data-driven content
  pipeline, the pattern M5 (items/equipment) and M6 (skills/spells) will reuse.
- First UI scene (`ui/character_creation/character_creation_screen.tscn`):
  a `CanvasLayer` overlay letting the player pick a race, class, and name,
  shown once `NetworkManager.connected_to_server` fires and hidden on success.
- `world.gd` now exposes `request_create_character` — an
  `@rpc("any_peer", ...)` intent mirroring `player_input.gd`'s
  `request_move_to` (request -> validate -> apply -> replicate). The server
  validates race/class existence, name (non-empty, length-bounded), and
  one-character-per-peer, then seeds the spawn via
  `MultiplayerSpawner.spawn({peer_id, race_id, class_id, character_name})` —
  primitives only, since `Resource`/`PackedScene`/`Node` don't survive the
  spawner's variant encoding. `_spawn_player` re-resolves the chosen
  `RaceModel`/`CharacterClass` from `GameDatabase` by id, so every peer
  (including late joiners, who get the spawner's automatic `data` replay)
  reconstructs an identical character with zero roster code. Feedback travels
  back via `on_character_created`/`on_character_creation_failed`
  `@rpc("authority", ...)` calls to the requesting peer only, each just
  bridging "called over the network" into a local signal the UI connects to.
- `player.gd` gained `race_id`/`class_id`/`character_name` identity fields,
  set deterministically by `_spawn_player` before the node enters the tree —
  intentionally unreplicated, like `name`, since every peer derives the same
  values from the same spawn `data`. `model_view.gd` now resolves its visual
  via `GameDatabase.races[race_id].visual_scene` instead of a hardcoded
  `preload`, so Dark Elf characters finally render as Dark Elves.

### Verified
- Headless server + 3 clients on localhost: single-client creation with the
  correct race/class/name and visual model; rejection of an unknown race and
  of a duplicate creation attempt from the same peer ("You already have a
  character."); two peers picking different races each see the other's
  correct model (proving the spawn `data` dict survives replication intact);
  and a third, late-joining client reconstructs both existing characters with
  correct races/names purely from the spawner's automatic `data` replay.

## [0.3.0] - 2026-06-07

### Added
- M3 real character models + animation sync: converted `Elf-Final.blend`/
  `DarkElf-Final.blend` to `.glb` via a self-contained portable Blender 5.1.2
  in `.tools/blender/` (raw `.blend`s extracted to `MyAssets/extracted/`,
  exported rigs in `MyAssets/converted/`, imported game-ready copies under
  `entities/player/models/{elf,dark_elf}/`). Replaced the placeholder capsule
  with `model_view.gd`: instances the rigged model (scaled to match the
  existing capsule height), builds an `AnimationTree` blend tree (`idle` <->
  `Walk-sexy - fixed`) driven by a new `player_controller.gd` value,
  `move_blend` — a small normalized locomotion float (0=idle, 1=walking)
  computed server-side and replicated via `MultiplayerSynchronizer` alongside
  position/rotation, exactly as the plan calls for ("blend *parameter*, not
  raw frames, for jitter resilience"). Verified end-to-end with a headless
  server + 2 clients: each peer sees the other's model walk and its animation
  blend transition in lockstep with the replicated value, never computing it
  locally.

### Fixed
- World spawn points: `world.gd._spawn_player` previously placed every
  character at the exact same point, which is harmless with one player but
  causes degenerate `CharacterBody3D` collision resolution with two or more
  (coincident capsules launch each other hundreds of units skyward within a
  second — only surfaced once M3 testing had two clients move at once). Now
  spawns are deterministically slotted by `peer_id` around a small circle.

### Notes
- The source rig's animation set doesn't match the milestone plan's assumed
  Idle/Walk/Attack/Run/Die — actual clips are stylized (`Walk-sexy - fixed`,
  `Run-flee`, `Shoot-bow`/`shoot-gun`, `Death-Backwards`, `idle`, etc.). M3
  uses `idle`/`Walk-sexy - fixed` for the locomotion blend; better-fitting
  walk/run/melee-attack clips may need sourcing or re-authoring later. Both
  rigs do, however, ship ready-made `Weapon_L`/`Weapon_R` attachment bones —
  a clean fit for M5's `BoneAttachment3D` equipment visuals.

## [0.2.0] - 2026-06-07

### Added
- Project skeleton: Godot 4.6.3 project structure (`bootstrap/`, `net/`, `data/`,
  `database/`, `content/`, `systems/`, `entities/`, `ui/`) per the architecture plan.
- M0 networking skeleton: `NetworkMode`, `GameDatabase`, `NetworkManager`, `Bootstrap`
  autoloads; `main.tscn` / `server_main.tscn` / `client_main.tscn`; CLI parsing for
  `--server`, `--port=`, `--connect=`. A headless server can listen and a client can
  connect, both logging success — pure plumbing, no gameplay yet.
- M1 synced click-to-move: flat test arena (`entities/world/`) with a runtime-built
  `NavigationRegion3D`, placeholder capsule `player.tscn` (`CharacterBody3D` +
  `NavigationAgent3D`), server-authoritative `player_controller.gd` (owns pathing and
  movement), client-local `player_input.gd` (raycasts mouse clicks, ships destination
  via `@rpc`), and `camera_rig.gd` (diagonal top-down boom camera). Spawned through
  `MultiplayerSpawner` with position/rotation replicated via `MultiplayerSynchronizer`
  + `SceneReplicationConfig`. Verified end-to-end: click-to-path-to-walk, replicated
  identically between server and client.
- M2 multi-client sync: verified that two simultaneously connected clients each see
  both capsules spawn, path independently under their own owner's clicks, and
  replicate smoothly to every peer — confirmed via roster comparison across server
  and both clients (`Players` node children byte-identical on all three).
