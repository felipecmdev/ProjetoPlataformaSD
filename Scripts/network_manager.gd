extends Node

## Listen-server com UDP: um jogador é host, outro envia input e recebe estado.
## Executar host: `Godot.exe --path . -- --host`
## Executar cliente: `Godot.exe --path . -- --join=IP_DO_HOST` (LAN: ex. 192.168.0.10)

enum Role { NONE, HOST, CLIENT }

const DEFAULT_PORT := 7777
## Porta local só do cliente (host usa `port`). Evita conflito host+cliente no mesmo PC.
const CLIENT_LOCAL_PORT := 7788

var role: Role = Role.NONE
var port: int = DEFAULT_PORT
var join_address: String = "127.0.0.1"

var udp := PacketPeerUDP.new()
var _client_ip: String = ""
var _client_port: int = 0

var client_move_x: float = 0.0
var client_jump_pending: bool = false

var player0: CharacterBody2D
var player1: CharacterBody2D


func _enter_tree() -> void:
	_parse_cmdline_args()


func _ready() -> void:
	if not is_online():
		return
	if role == Role.HOST:
		if udp.bind(port, "*") != OK:
			push_error("[NET] Bind UDP falhou na porta %d" % port)
			role = Role.NONE
			return
		print("[NET] Host ativo na porta %d. Cliente: --join=<este_IP>" % port)
	elif role == Role.CLIENT:
		if udp.bind(CLIENT_LOCAL_PORT, "*") != OK:
			push_error("[NET] Cliente: bind local porta %d falhou (fecha outro cliente ou muda CLIENT_LOCAL_PORT)." % CLIENT_LOCAL_PORT)
			role = Role.NONE
			return
		udp.set_dest_address(join_address, port)
		print("[NET] Cliente → %s:%d (escuta local UDP %d)" % [join_address, port, CLIENT_LOCAL_PORT])
	get_tree().physics_frame.connect(_on_physics_frame_end)


func is_host() -> bool:
	return role == Role.HOST


func is_client() -> bool:
	return role == Role.CLIENT


func is_online() -> bool:
	return role == Role.HOST or role == Role.CLIENT


## 0 = host (máquina do servidor), 1 = cliente.
func local_peer_slot() -> int:
	match role:
		Role.HOST:
			return 0
		Role.CLIENT:
			return 1
		_:
			return 0


func register_players(p0: CharacterBody2D, p1: CharacterBody2D) -> void:
	player0 = p0
	player1 = p1


func poll_receive_host() -> void:
	while udp.get_available_packet_count() > 0:
		var raw := udp.get_packet()
		var s := raw.get_string_from_utf8()
		var ip: String = udp.get_packet_ip()
		var prt: int = udp.get_packet_port()
		
		if s.begins_with("I|"):
			_client_ip = ip
			_client_port = prt
			var parts := s.split("|")
			if parts.size() >= 3:
				client_move_x = clampf(float(parts[1]), -1.0, 1.0)
				if parts[2] == "1":
					client_jump_pending = true


func poll_receive_client() -> void:
	while udp.get_available_packet_count() > 0:
		var s := udp.get_packet().get_string_from_utf8()
		if s.begins_with("S|"):
			_apply_snapshot(s)


func send_snapshot_host() -> void:
	if _client_ip.is_empty() or player0 == null or player1 == null:
		return
	udp.set_dest_address(_client_ip, _client_port)
	var msg := "S|%f|%f|%f|%f|%f|%f|%f|%f" % [
		player0.global_position.x,
		player0.global_position.y,
		player0.velocity.x,
		player0.velocity.y,
		player1.global_position.x,
		player1.global_position.y,
		player1.velocity.x,
		player1.velocity.y,
	]
	udp.put_packet(msg.to_utf8_buffer())


func send_input_client() -> void:
	if player1 == null:
		return
	var dx := Input.get_axis(&"move_left", &"move_right")
	var j := 1 if Input.is_action_just_pressed(&"jump") else 0
	var msg := "I|%f|%d" % [dx, j]
	udp.set_dest_address(join_address, port)
	udp.put_packet(msg.to_utf8_buffer())


func _apply_snapshot(s: String) -> void:
	var p := s.split("|")
	if p.size() < 9:
		return
	if player0 == null or player1 == null:
		return
	player0.global_position = Vector2(float(p[1]), float(p[2]))
	player0.velocity = Vector2(float(p[3]), float(p[4]))
	player1.global_position = Vector2(float(p[5]), float(p[6]))
	player1.velocity = Vector2(float(p[7]), float(p[8]))


func _on_physics_frame_end() -> void:
	if not is_online():
		return
	if role == Role.HOST:
		send_snapshot_host()
	elif role == Role.CLIENT:
		poll_receive_client()
		send_input_client()


func _parse_cmdline_args() -> void:
	for a in OS.get_cmdline_user_args():
		_apply_net_arg(a)
	if role == Role.NONE:
		for a in OS.get_cmdline_args():
			if a == "--host" or a.begins_with("--join=") or a.begins_with("--port="):
				_apply_net_arg(a)


func _apply_net_arg(a: String) -> void:
	if a == "--host":
		role = Role.HOST
	elif a.begins_with("--join="):
		role = Role.CLIENT
		join_address = a.get_slice("=", 1)
	elif a.begins_with("--port="):
		port = int(a.get_slice("=", 1))


func _exit_tree() -> void:
	udp.close()
