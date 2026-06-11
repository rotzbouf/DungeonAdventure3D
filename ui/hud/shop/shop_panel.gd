extends PanelContainer

## CLIENT-ONLY shop panel, opened by merchant.gd via hud.gd.open_shop().
## Mirrors inventory_panel.gd's group-by-id/double-click pattern: the stock
## list (left) shows the merchant's wares with buy prices, the inventory list
## (right) shows the player's items with sell prices. Double-clicking either
## sends a buy/sell RPC to the server; gold/inventory updates arrive via the
## already-replicated StatsComponent.gold and InventoryComponent.items.

@onready var _title_label: Label = $VBox/Header/TitleLabel
@onready var _stock_list: ItemList = $VBox/Lists/StockColumn/StockList
@onready var _inventory_list: ItemList = $VBox/Lists/InventoryColumn/InventoryList

var _shop_component: Node
var _inventory_component: Node
var _shop_id: StringName = &""
var _stock_ids: Array[StringName] = []
## Unique item ids in display order, parallel to _inventory_list's rows.
var _unique_inventory_ids: Array[StringName] = []


func open_shop(shop_id: StringName, shop_component: Node, inventory_component: Node) -> void:
	if _inventory_component != null and _inventory_component.inventory_changed.is_connected(_on_inventory_changed):
		_inventory_component.inventory_changed.disconnect(_on_inventory_changed)
	if _shop_component != null and _shop_component.trade_rejected.is_connected(_on_trade_rejected):
		_shop_component.trade_rejected.disconnect(_on_trade_rejected)

	_shop_id = shop_id
	_shop_component = shop_component
	_inventory_component = inventory_component

	var shop: Resource = GameDatabase.shops.get(shop_id)
	_title_label.text = shop.display_name if shop != null else String(shop_id)
	_stock_ids = shop.stock if shop != null else []
	_refresh_stock()

	_inventory_component.inventory_changed.connect(_on_inventory_changed)
	_shop_component.trade_rejected.connect(_on_trade_rejected)
	_on_inventory_changed(_inventory_component.items)

	visible = true


func _refresh_stock() -> void:
	_stock_list.clear()
	for id in _stock_ids:
		var item: Resource = GameDatabase.items.get(id)
		var item_name: String = item.display_name if item != null else String(id)
		var price: int = item.value if item != null else 0
		_stock_list.add_item("%s - %d gold" % [item_name, price])


func _on_inventory_changed(items: Array[StringName]) -> void:
	var counts: Dictionary = {}
	_unique_inventory_ids.clear()
	for id in items:
		if id not in counts:
			_unique_inventory_ids.append(id)
		counts[id] = counts.get(id, 0) + 1

	_inventory_list.clear()
	for id in _unique_inventory_ids:
		var item: Resource = GameDatabase.items.get(id)
		var item_name: String = item.display_name if item != null else String(id)
		var sell_price: int = (item.value / 2) if item != null else 0
		var count: int = counts[id]
		var label := "%s - %d gold" % [item_name, sell_price]
		_inventory_list.add_item(label if count == 1 else "%s x%d" % [label, count])


func _on_stock_list_item_activated(index: int) -> void:
	if index < 0 or index >= _stock_ids.size():
		return
	_shop_component.request_buy_item.rpc_id(1, _shop_id, _stock_ids[index])


func _on_inventory_list_item_activated(index: int) -> void:
	if index < 0 or index >= _unique_inventory_ids.size():
		return
	_shop_component.request_sell_item.rpc_id(1, _unique_inventory_ids[index])


func _on_trade_rejected(reason: String) -> void:
	print("[shop] %s" % reason)


func _on_close_button_pressed() -> void:
	visible = false
