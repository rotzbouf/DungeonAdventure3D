extends Node

## The boot-flow brain. main.tscn is intentionally almost empty — this
## autoload's _ready() decides what the process actually is (per NetworkMode)
## and instantiates the right root scene, then starts hosting or joining.
##
## CLI args (after "--", via OS.get_cmdline_user_args()):
##   --server            force dedicated-server mode from the client/editor binary
##   --port=<port>       port to host on (server) or connect to (client)
##   --connect=<ip[:port]>  address to connect to (client only)

const SERVER_MAIN_SCENE := "res://net/server_main.tscn"
const CLIENT_MAIN_SCENE := "res://net/client_main.tscn"
const DEFAULT_PORT := 7777
const DEFAULT_ADDRESS := "127.0.0.1"


func _ready() -> void:
	var args := _parse_args()
	if NetworkMode.is_server():
		_boot_server(args)
	else:
		_boot_client(args)


func _parse_args() -> Dictionary:
	var result := {
		"port": DEFAULT_PORT,
		"address": DEFAULT_ADDRESS,
	}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			result.port = int(arg.substr(len("--port=")))
		elif arg.begins_with("--connect="):
			var value := arg.substr(len("--connect="))
			var parts := value.split(":")
			result.address = parts[0]
			if parts.size() > 1:
				result.port = int(parts[1])
	return result


func _boot_server(args: Dictionary) -> void:
	print("Bootstrap: booting as DEDICATED SERVER")
	var root: Node = load(SERVER_MAIN_SCENE).instantiate()
	get_tree().root.add_child.call_deferred(root)
	NetworkManager.host(args.port)


func _boot_client(args: Dictionary) -> void:
	print("Bootstrap: booting as CLIENT")
	var root: Node = load(CLIENT_MAIN_SCENE).instantiate()
	get_tree().root.add_child.call_deferred(root)
	NetworkManager.join(args.address, args.port)
