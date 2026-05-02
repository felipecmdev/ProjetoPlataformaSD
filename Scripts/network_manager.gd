extends Node

var MAX_JOGADORES: int = 4 # Esse número conta com o cliente, então 4 significa Host + 3 Clientes

enum Role { NONE, HOST, CLIENT }

const DEFAULT_PORT := 7777
## Porta local só do cliente (host usa `port`). Evita conflito host+cliente no mesmo PC.
const CLIENT_LOCAL_PORT := 7788

# Variáveis de estado para suportar mais de um cliente
signal connection_approved
signal player_spawn_requested(id: int)

var next_player_id: int = 1
var clients_input: Dictionary = {} # Guarda os botões apertados por cada cliente
var players_nodes: Dictionary = {} # Guarda a referência dos bonecos (aquele CharacterBody2D) na tela

var role: Role = Role.NONE
var port: int = DEFAULT_PORT
var join_address: String = "127.0.0.1"

var udp := PacketPeerUDP.new()

# Os clientes vão ficar em um dicionário, isso permite armazenar 
# mais de um cliente e tornando o jogo escalável
var connected_clients: Dictionary = {}
var my_player_id: int = -1

func _ready() -> void:
	get_tree().physics_frame.connect(_on_physics_frame_end)
	

func setup_connection() -> void:
	udp.close()
	
	if role == Role.HOST:
		if udp.bind(port, "*") != OK:
			push_error("[NET] Bind UDP falhou na porta %d" % port)
			role = Role.NONE
			return
		print("[NET] Host ativo na porta %d. Aguardando clientes..." % port)
		my_player_id = 0 # O Host é o ID 0
	elif role == Role.CLIENT:
		var port_bound := false
		var current_test_port := CLIENT_LOCAL_PORT # vvai da 7788 pra frente
		var tentativas_maximas := 20 # vai tentar em 20 portas diferentes
		
		for i in range (tentativas_maximas):
			if udp.bind(current_test_port, "*") == OK:
				port_bound = true
				break
			else:
				print ("[NET] Porta %d ocupada, tentando a próxima..." % current_test_port)
				current_test_port += 1
				
		if not port_bound:
			push_error("[NET] Cliente: Falha ao encontrar uma porta local livre")
			role = Role.NONE
			return
		
		udp.set_dest_address(join_address, port)
		print ("[NET] Cliente configurado para -> %s:%d (Usando porta local %d)" % [join_address, port, current_test_port])

func is_host() -> bool:
	return role == Role.HOST

func is_client() -> bool:
	return role == Role.CLIENT

func is_online() -> bool:
	return role == Role.HOST or role == Role.CLIENT

func local_peer_slot() -> int:
	return my_player_id
	
func register_player_node(id: int, node: CharacterBody2D) -> void:
	players_nodes[id] = node

func poll_receive_host() -> void:
	while udp.get_available_packet_count() > 0:
		var pacote_em_bytes := udp.get_packet()
		var mensagem_texto := pacote_em_bytes.get_string_from_utf8()
		var ip_cliente: String = udp.get_packet_ip()
		var porta_cliente: int = udp.get_packet_port()
		
		var client_key = ip_cliente + ":" + str(porta_cliente)
		var client_id = -1
		
		if connected_clients.has(client_key):
			client_id = connected_clients[client_key]["id"]
		
		else:
			if next_player_id < MAX_JOGADORES:
				client_id = next_player_id
				connected_clients[client_key] = {"ip": ip_cliente, 
				"port": porta_cliente, "id": client_id}
				clients_input[client_id] = {"move_x": 0.0, "jump": false}
				print ("[NET] Novo cliente conectado: %s (ID: %d)" % [client_key, client_id])
				player_spawn_requested.emit(client_id)
				next_player_id += 1
			else:
				print ("[NET] Servidor Lotado!")
				continue
		
		if mensagem_texto.begins_with("C|"):
			var msg_welcome := "W|%d" % client_id
			udp.set_dest_address(ip_cliente, porta_cliente)
			udp.put_packet(msg_welcome.to_utf8_buffer())
		
		elif mensagem_texto.begins_with("P|"):
			var parts := mensagem_texto.split("|")
			if parts.size() >= 5:
				if players_nodes.has(client_id):
					var nodo_cliente = players_nodes[client_id]
					if is_instance_valid(nodo_cliente):
						nodo_cliente.global_position = Vector2(float(parts[1]), float(parts[2]))
						nodo_cliente.velocity = Vector2(float(parts[3]), float(parts[4]))
		
		elif mensagem_texto.begins_with("K|"):
			_process_knockback(mensagem_texto)
			var buffer = mensagem_texto.to_utf8_buffer()
			for key in connected_clients.keys():
				var dados_cliente = connected_clients[key]
				udp.set_dest_address(dados_cliente["ip"], dados_cliente["port"])
				udp.put_packet(buffer)
				
func poll_receive_client() -> void:
	while udp.get_available_packet_count() > 0:
		var mensagem_recebida := udp.get_packet().get_string_from_utf8()
		
		if mensagem_recebida.begins_with("W|"):
			var partes = mensagem_recebida.split("|")
			if my_player_id == -1:
				my_player_id = int (partes[1])
				print ("[NET] Aceito no servidor! ID: %d " % my_player_id)
				connection_approved.emit()
				
		elif mensagem_recebida.begins_with("S|"):
			_apply_snapshot(mensagem_recebida)
		
		elif mensagem_recebida.begins_with("K|"):
			_process_knockback(mensagem_recebida)

func send_snapshot_host() -> void:
	if connected_clients.is_empty() or players_nodes.is_empty():
		return
		
	var pacote_texto := "S"
	# Junta todas as informações de todos os jogadores em um único lugar
	for id in players_nodes.keys():
		var nodo_jogador = players_nodes[id]
		if is_instance_valid(nodo_jogador):
			pacote_texto += "|%d|%f|%f|%f|%f" % [
				id,
				nodo_jogador.global_position.x,
				nodo_jogador.global_position.y,
				nodo_jogador.velocity.x,
				nodo_jogador.velocity.y
			]
	var buffer := pacote_texto.to_utf8_buffer()
	# Dispara a string pra todos os IPs no dicionário
	for key in connected_clients.keys():
		var dados_cliente = connected_clients[key]
		udp.set_dest_address(dados_cliente["ip"], dados_cliente["port"])
		udp.put_packet(buffer)


func send_input_client() -> void:
	if my_player_id == -1:
		udp.set_dest_address(join_address, port)
		udp.put_packet("C|".to_utf8_buffer())
		return
	
	if not players_nodes.has(my_player_id):
		return
		
	var meu_personagem = players_nodes[my_player_id]
	var mensagem_pos := "P|%f|%f|%f|%f" % [
		meu_personagem.global_position.x,
		meu_personagem.global_position.y,
		meu_personagem.velocity.x,
		meu_personagem.velocity.y
	]
	# Pacote do cliente
	udp.set_dest_address(join_address, port)
	udp.put_packet(mensagem_pos.to_utf8_buffer())

func _apply_snapshot(mensagem_estado: String) -> void:
	var partes_pacote := mensagem_estado.split("|")
	var i = 1 # Vai pular o S no i=0

	while i < partes_pacote.size() - 4:
		var id_jogador = int (partes_pacote[i])
		
		if players_nodes.has(id_jogador):
			var nodo_jogador = players_nodes[id_jogador]
			
			if is_instance_valid(nodo_jogador):
				
				if (id_jogador == my_player_id):
					i += 5
					continue
				
				nodo_jogador.global_position = Vector2(
					float(partes_pacote[i+1]),
					float(partes_pacote[i+2])
				)
				nodo_jogador.velocity = Vector2(
					float(partes_pacote[i+3]),
					float(partes_pacote[i+4])
				)
		else:
			player_spawn_requested.emit(id_jogador)
		i += 5

func _on_physics_frame_end() -> void:
	if not is_online():
		return
		
	if role == Role.HOST:
		poll_receive_host()
		send_snapshot_host()
		
	elif role == Role.CLIENT:
		poll_receive_client()
		send_input_client()

func send_push_command(target_id: int, push_dir: float) -> void:
	var msg := "K|%d|%f" % [
		target_id,
		push_dir
	]
	
	if role == Role.HOST:
		_process_knockback(msg)
		var buffer = msg.to_utf8_buffer()
		for key in connected_clients.keys():
			var dados = connected_clients[key]
			udp.set_dest_address(dados["ip"], dados["port"])
			udp.put_packet(buffer)
	
	else:
		udp.set_dest_address(join_address, port)
		udp.put_packet(msg.to_utf8_buffer())

func _process_knockback(msg: String) -> void:
	var parts = msg.split("|")
	if parts.size() >= 3:
		var target_id = int(parts[1])
		var push_dir = float(parts[2])
		
		if target_id == my_player_id and players_nodes.has(my_player_id):
			players_nodes[my_player_id].receive_knockback(push_dir)
	

func _exit_tree() -> void:
	udp.close()
