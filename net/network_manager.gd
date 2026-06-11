extends Node

## Owns the ENetMultiplayerPeer for this process and exposes a small
## host()/join() surface. Bootstrap calls into this; gameplay code reacts to
## the signals below (e.g. to spawn/despawn characters on peer connect).

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal connected_to_server()
signal connection_failed()
signal server_disconnected()

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 32


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("NetworkManager: failed to create server on port %d (error %d)" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	print("NetworkManager: listening on port %d (my id = %d)" % [port, multiplayer.get_unique_id()])
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("NetworkManager: failed to connect to %s:%d (error %d)" % [address, port, err])
		return err
	multiplayer.multiplayer_peer = peer
	print("NetworkManager: connecting to %s:%d ..." % [address, port])
	return OK


func close() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null


func _on_peer_connected(peer_id: int) -> void:
	print("NetworkManager: peer connected -> %d" % peer_id)
	peer_connected.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("NetworkManager: peer disconnected -> %d" % peer_id)
	peer_disconnected.emit(peer_id)


func _on_connected_to_server() -> void:
	print("NetworkManager: connected to server (my id = %d)" % multiplayer.get_unique_id())
	connected_to_server.emit()


func _on_connection_failed() -> void:
	push_error("NetworkManager: connection to server failed")
	connection_failed.emit()


func _on_server_disconnected() -> void:
	push_warning("NetworkManager: server disconnected")
	server_disconnected.emit()
