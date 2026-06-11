class_name ShopDefinition
extends Resource

## Designer-authored merchant stock list, loaded by GameDatabase from
## res://content/shops/*.tres. Stock is infinite -- buying an item never
## removes it from `stock`, it just charges the buyer via shop_component.gd.

@export var id: StringName = &""
@export var display_name: String = ""
@export var stock: Array[StringName] = []
