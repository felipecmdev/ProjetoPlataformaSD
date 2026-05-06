extends Node

var MAX_JOGADORES: int = 4 # Esse número conta com o cliente, então 4 significa Host + 3 Clientes

enum Role { NONE, HOST, CLIENT }
enum GameState { LOBBY, PLAYING }
var current_state : GameState = GameState.LOBBY

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

var my_player_name: String = "Visitante"

signal lobby_players_updated
var players_data: Dictionary = {}

var players_ready: Dictionary = {}

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
		
		players_data[my_player_id] = my_player_name
		lobby_players_updated.emit()
		
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
			
			
			# Posições
			if mensagem_texto.begins_with("P|"):
				var partes = mensagem_texto.split("|")
				if partes.size() >= 5:
					if players_nodes.has(client_id):
						var nodo_cliente = players_nodes[client_id]
						if is_instance_valid(nodo_cliente):
							nodo_cliente.global_position = Vector2(float(partes[1]), float(partes[2]))
							nodo_cliente.velocity = Vector2(float(partes[3]), float(partes[4]))
			
			
			# Knockback
			elif mensagem_texto.begins_with("K|"):
				_process_knockback(mensagem_texto)
				var buffer = mensagem_texto.to_utf8_buffer()
				for key in connected_clients.keys():
					var dados_clientes = connected_clients[key]
					udp.set_dest_address(dados_clientes["ip"], dados_clientes["port"])
					udp.put_packet(buffer)
			
			elif mensagem_texto.begins_with("RDY|"):
				var partes = mensagem_texto.split("|")
				if partes.size() >= 3:
					var rdy_id = int(partes[1])
					var is_ready = (partes[2] == "true")
					
					players_ready[rdy_id] = is_ready
					lobby_players_updated.emit()
					
					var buffer = mensagem_texto.to_utf8_buffer()
					for key in connected_clients.keys():
						udp.set_dest_address(connected_clients[key]["ip"], connected_clients[key]["port"])
						udp.put_packet(buffer)
			# Quit
			elif mensagem_texto.begins_with("Q|"):
				if client_id != -1:
					_desconectar_jogador(client_id)
			
		
		else:
			# Connect
			if mensagem_texto.begins_with("C|"):
				
				if current_state == GameState.PLAYING:
					print ("[NET] Rejeitando conexão: Partida já começou.")
					udp.set_dest_address(ip_cliente, port)
					udp.put_packet("R|Jogo em andamento".to_utf8_buffer())
					continue
				
				var partes := mensagem_texto.split("|")
				var nome_recebido = "Visitante"
				if partes.size() >= 2:
					nome_recebido = partes[1]
				
				var novo_id := _get_free_player_id()
				if novo_id != -1:
					client_id = novo_id
					connected_clients[client_key] = {
						"ip": ip_cliente, 
						"port": porta_cliente,
						"id": client_id,
						"name": nome_recebido
						}
						
					players_data[client_id] = nome_recebido
					lobby_players_updated.emit()
					
					print ("[NET] Novo Cliente conectado. ID: %d" % novo_id)
					player_spawn_requested.emit(client_id)
					
					# Handshake
					
					var msg_welcome := "W|%d" % client_id
					udp.set_dest_address(ip_cliente, porta_cliente)
					udp.put_packet(msg_welcome.to_utf8_buffer())
					
					var msg_host = "N|%d|%s" % [my_player_id, my_player_name]
					udp.set_dest_address(ip_cliente, porta_cliente)
					udp.put_packet(msg_host.to_utf8_buffer())
					
					for key in connected_clients.keys():
						var dados_antigos = connected_clients[key]
						
						if dados_antigos["id"] != client_id:
							var msg_antiga = "N|%d|%s" % [dados_antigos["id"], dados_antigos["name"]] 
							udp.set_dest_address(ip_cliente, porta_cliente)
							udp.put_packet(msg_antiga.to_utf8_buffer())
							
							var antigo_ta_pronto = "true" if players_ready.get(dados_antigos["id"], false) else "false"
							var msg_antiga_rdy = "RDY|%d|%s" % [dados_antigos["id"], antigo_ta_pronto]
							udp.put_packet(msg_antiga_rdy.to_utf8_buffer())
							
							var msg_nova = "N|%d|%s" % [client_id, nome_recebido]
							udp.set_dest_address(dados_antigos["ip"], dados_antigos["port"])
							udp.put_packet(msg_nova.to_utf8_buffer())
							
				# Servidor cheio
				else:
					print ("Servidor lotado!")
			
			# Se a chave não ta registrada e não foi pedido de conexão, ele pula
			# Isso aqui que resolve o bug de sair e não desconectar
			else:
				pass
					
func poll_receive_client() -> void:
	while udp.get_available_packet_count() > 0:
		var mensagem_recebida := udp.get_packet().get_string_from_utf8()
		
		# Handshake
		
		if mensagem_recebida.begins_with("W|"):
			var partes = mensagem_recebida.split("|")
			if my_player_id == -1:
				my_player_id = int (partes[1])
				
				players_data[my_player_id] = my_player_name
				lobby_players_updated.emit()
				
				print ("[NET] Aceito no servidor! ID: %d " % my_player_id)
				connection_approved.emit()
			
		# Snapshot
		elif mensagem_recebida.begins_with("S|"):
			_apply_snapshot(mensagem_recebida)
		
		# Knockback
		elif mensagem_recebida.begins_with("K|"):
			_process_knockback(mensagem_recebida)
		
		# Quit
		elif mensagem_recebida.begins_with("Q|"):
			var partes = mensagem_recebida.split("|")
			if partes.size() >= 2:
				var id_desconectado = int(partes[1])
				
				if players_nodes.has(id_desconectado):
					var boneco = players_nodes[id_desconectado]
					if is_instance_valid(boneco):
						boneco.queue_free()
						
					players_nodes.erase(id_desconectado)
		
		elif mensagem_recebida.begins_with("R|"):
			var partes = mensagem_recebida.split("|")
			if partes.size() >= 2:
				var motivo = partes[1]
				print ("[NET] Não foi possível conectar. Motivo: %s" % motivo)
			
			else:
				print ("[NET] Não foi possível conectar. Motivo desconhecido!")
		
			udp.close()
			my_player_id = -1
			role = Role.NONE
		
		elif mensagem_recebida.begins_with("N|"):
			var partes = mensagem_recebida.split("|")
			if partes.size() >= 3:
				var id_alvo = int(partes[1])
				var nome_alvo = partes[2]
				
				players_data[id_alvo] = nome_alvo
				lobby_players_updated.emit()
				
				if players_nodes.has(id_alvo):
					var boneco = players_nodes[id_alvo]
					if is_instance_valid(boneco) and boneco.has_method("set_player_name"):
						boneco.set_player_name(nome_alvo)
		
		elif mensagem_recebida.begins_with("RDY|"):
			var partes = mensagem_recebida.split("|")
			if partes.size() >= 3:
				var rdy_id = int(partes[1])
				var is_ready = (partes[2] == "true")
				players_ready[rdy_id] = is_ready
				lobby_players_updated.emit()
		
		elif mensagem_recebida == "START|":
			current_state = GameState.PLAYING
			get_tree().change_scene_to_file("res://scenes/FaseTeste.tscn")
		
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
		var mensagem := "C|" + my_player_name
		udp.put_packet(mensagem.to_utf8_buffer())
		
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


#Funções pra excluir o jogador quando desconectar
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if role == Role.CLIENT and my_player_id != -1:
			udp.set_dest_address(join_address, port)
			udp.put_packet("Q|".to_utf8_buffer())
		
		udp.close()
		get_tree().quit()

func _desconectar_jogador(id_desconectado: int):
	var msg_quit := "Q|%d" % id_desconectado
	var buffer_quit := msg_quit.to_utf8_buffer()
	
	for key in connected_clients.keys():
		var dados = connected_clients[key]
		
		# Não vai notificar o próprio jogador que desconectou
		if dados["id"] != id_desconectado:
			udp.set_dest_address(dados["ip"], dados["port"])
			udp.put_packet(buffer_quit)
		
	if players_nodes.has(id_desconectado):
		var boneco = players_nodes[id_desconectado]
		if is_instance_valid(boneco):
			boneco.queue_free()
			players_nodes.erase(id_desconectado)
	
	var chave_para_remover = ""
	for key in connected_clients.keys():
			if connected_clients[key]["id"] == id_desconectado:
				chave_para_remover = key
				break
	
	if chave_para_remover != "":
		connected_clients.erase(chave_para_remover)
	
	players_ready.erase(id_desconectado)
	players_data.erase(id_desconectado)
	lobby_players_updated.emit()

func _get_free_player_id() -> int:
	for i in range (1, MAX_JOGADORES):
		var id_em_uso = false
		for key in connected_clients.keys():
			if connected_clients[key]["id"] == i:
				id_em_uso = true
				break
		
		if !id_em_uso:
			return i
		
	return -1
	
func send_ready_state(is_ready: bool) -> void:
	if role == Role.CLIENT:
		var msg = "RDY|%d|%s" % [my_player_id, "true" if is_ready else "false"]
		udp.set_dest_address(join_address, port)
		udp.put_packet(msg.to_utf8_buffer())

func start_game_host() -> void:
	if role == Role.HOST:
		current_state = GameState.PLAYING
		var buffer = "START|".to_utf8_buffer()
		for key in connected_clients.keys():
			udp.set_dest_address(connected_clients[key]["ip"], connected_clients[key]["port"])
			udp.put_packet(buffer)
		
		get_tree().change_scene_to_file("res://scenes/FaseTeste.tscn")
		

func _exit_tree() -> void:
	udp.close()
