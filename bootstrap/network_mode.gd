extends Node

## Determines whether this process is a dedicated server, a client, or a
## listen-host (server + local player), and exposes that to every other system.
## Decided once at startup, before anything else depends on it — this is why
## it is the very first autoload.

enum Mode {
	DEDICATED_SERVER,
	CLIENT,
	LISTEN_HOST,
}

var mode: Mode = Mode.CLIENT


func _enter_tree() -> void:
	if OS.has_feature("dedicated_server"):
		mode = Mode.DEDICATED_SERVER
	elif "--server" in OS.get_cmdline_user_args():
		mode = Mode.DEDICATED_SERVER
	else:
		mode = Mode.CLIENT


func is_server() -> bool:
	return mode == Mode.DEDICATED_SERVER or mode == Mode.LISTEN_HOST


func is_dedicated_server() -> bool:
	return mode == Mode.DEDICATED_SERVER


func is_client() -> bool:
	return mode == Mode.CLIENT or mode == Mode.LISTEN_HOST
