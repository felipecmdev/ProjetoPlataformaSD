extends Node

var MAX_JOGADORES: int = 4 # Esse número conta com o cliente, então 4 significa Host + 3 Clientes

enum Role { NONE, HOST, CLIENT }
enum GameState { LOBBY, PLAYING, PICKING, BUILDING }
var current_state : GameState = GameState.LOBBY

const DEFAULT_PORT := 7777
## Porta local só do cliente (host usa `port`). Evita conflito host+cliente no mesmo PC.
const CLIENT_LOCAL_PORT := 7788

# Variáveis de estado para suportar mais de um cliente
signal connection_approved
signal player_spawn_requested(id: int)
signal game_phase_changed(new_state: GameState)
signal build_data_updated
signal item_placed(item_type: String, position: Vector2)

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
var my_skin_name: String = "Azul"

signal lobby_players_updated
var players_data: Dictionary = {}

var players_ready: Dictionary = {}
var players_skin: Dictionary = {}
var round_number: int = 0
var placed_items: Array = []
var current_build_options: Dictionary = {}
var current_selected_items: Dictionary = {}
var build_order: Array[int] = []
var current_builder_id: int = -1
## IDs usados em rede e no mapa. Regiões do sprite: `Scripts/build_items_config.gd`
const BUILD_ITEM_POOL: Array[String] = [
	"GRASS",
	"SPRING",
	"LADDER",
	"LUCKY",
	"SPIKE",
	"COIN",
]

var last_disconnect_reason: String = ""

func _reset_session_state() -> void:
	connected_clients.clear()
	players_nodes.clear()
	players_data.clear()
	players_ready.clear()
	players_skin.clear()
	placed_items.clear()
	current_build_options.clear()
	current_selected_items.clear()
	build_order.clear()
	current_builder_id = -1
	round_number = 0
	current_state = GameState.LOBBY
	my_player_id = -1
	role = Role.NONE

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
		players_skin[my_player_id] = my_skin_name
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
			
			elif mensagem_texto.begins_with("SKN|"):
				var partes = mensagem_texto.split("|")
				if partes.size() >= 3:
					var skn_id = int(partes[1])
					var skin = partes[2]
					players_skin[skn_id] = skin
					lobby_players_updated.emit()
					
					if players_nodes.has(skn_id):
						var boneco_skn = players_nodes[skn_id]
						if is_instance_valid(boneco_skn) and boneco_skn.has_method("set_skin"):
							boneco_skn.set_skin(skin)
					
					var buffer = mensagem_texto.to_utf8_buffer()
					for key in connected_clients.keys():
						udp.set_dest_address(connected_clients[key]["ip"], connected_clients[key]["port"])
						udp.put_packet(buffer)
			# Quit
			elif mensagem_texto.begins_with("Q|"):
				if client_id != -1:
					_desconectar_jogador(client_id)
			
			elif mensagem_texto.begins_with("FIN|"):
				var partes = mensagem_texto.split("|")
				if partes.size() >= 2:
					_begin_build_phase(int(partes[1]))
			
			elif mensagem_texto.begins_with("SEL|"):
				var partes = mensagem_texto.split("|")
				if partes.size() >= 3:
					_on_item_selected_host(int(partes[1]), partes[2])
			
			elif mensagem_texto.begins_with("PLC|"):
				var partes = mensagem_texto.split("|")
				if partes.size() >= 5:
					_on_item_placed_host(int(partes[1]), partes[2], Vector2(float(partes[3]), float(partes[4])))
			
		
		else:
			# Connect
			if mensagem_texto.begins_with("C|"):
				
				if current_state != GameState.LOBBY:
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
					
					var msg_host_skin = "SKN|%d|%s" % [my_player_id, my_skin_name]
					udp.put_packet(msg_host_skin.to_utf8_buffer())
					
					for key in connected_clients.keys():
						var dados_antigos = connected_clients[key]
						
						if dados_antigos["id"] != client_id:
							var msg_antiga = "N|%d|%s" % [dados_antigos["id"], dados_antigos["name"]] 
							udp.set_dest_address(ip_cliente, porta_cliente)
							udp.put_packet(msg_antiga.to_utf8_buffer())
							
							var antigo_ta_pronto = "true" if players_ready.get(dados_antigos["id"], false) else "false"
							var msg_antiga_rdy = "RDY|%d|%s" % [dados_antigos["id"], antigo_ta_pronto]
							udp.put_packet(msg_antiga_rdy.to_utf8_buffer())
							
							var skin_antigo = str(players_skin.get(dados_antigos["id"], "Azul"))
							var msg_antiga_skin = "SKN|%d|%s" % [dados_antigos["id"], skin_antigo]
							udp.put_packet(msg_antiga_skin.to_utf8_buffer())
							
							var msg_nova = "N|%d|%s" % [client_id, nome_recebido]
							udp.set_dest_address(dados_antigos["ip"], dados_antigos["port"])
							udp.put_packet(msg_nova.to_utf8_buffer())
							
							var msg_nova_skin = "SKN|%d|%s" % [client_id, "Azul"]
							udp.put_packet(msg_nova_skin.to_utf8_buffer())
					
					players_skin[client_id] = "Azul"
							
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
				
				# Se o host caiu/fechou, derruba a sessão inteira do cliente.
				if id_desconectado == 0:
					print("[NET] Host desconectou. Voltando ao menu.")
					last_disconnect_reason = "Host desconectou."
					udp.close()
					_reset_session_state()
					lobby_players_updated.emit()
					get_tree().change_scene_to_file("res://scenes/Menu.tscn")
					return
				
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
		
		elif mensagem_recebida.begins_with("SKN|"):
			var partes = mensagem_recebida.split("|")
			if partes.size() >= 3:
				var id_alvo = int(partes[1])
				var skin_alvo = partes[2]
				
				players_skin[id_alvo] = skin_alvo
				lobby_players_updated.emit()
				
				if players_nodes.has(id_alvo):
					var boneco = players_nodes[id_alvo]
					if is_instance_valid(boneco) and boneco.has_method("set_skin"):
						boneco.set_skin(skin_alvo)
		
		elif mensagem_recebida.begins_with("RDY|"):
			var partes = mensagem_recebida.split("|")
			if partes.size() >= 3:
				var rdy_id = int(partes[1])
				var is_ready = (partes[2] == "true")
				players_ready[rdy_id] = is_ready
				lobby_players_updated.emit()
		
		elif mensagem_recebida == "START|":
			current_state = GameState.PLAYING
			game_phase_changed.emit(current_state)
			get_tree().change_scene_to_file("res://scenes/FaseTeste.tscn")
		
		elif mensagem_recebida.begins_with("PHASE|"):
			var partes = mensagem_recebida.split("|")
			if partes.size() >= 3:
				var phase_name = partes[1]
				round_number = int(partes[2])
				_set_phase_from_name(phase_name)
		
		elif mensagem_recebida.begins_with("OPT|"):
			var partes = mensagem_recebida.split("|")
			if partes.size() >= 3:
				var target_id = int(partes[1])
				var options_raw = partes[2]
				var options := []
				if options_raw != "":
					options = options_raw.split(",")
				current_build_options[target_id] = options
				build_data_updated.emit()
		
		elif mensagem_recebida.begins_with("TURN|"):
			var partes = mensagem_recebida.split("|")
			if partes.size() >= 2:
				current_builder_id = int(partes[1])
				current_state = GameState.BUILDING
				game_phase_changed.emit(current_state)
				build_data_updated.emit()
		
		elif mensagem_recebida.begins_with("SEL|"):
			var partes = mensagem_recebida.split("|")
			if partes.size() >= 3:
				current_selected_items[int(partes[1])] = partes[2]
				build_data_updated.emit()
		
		elif mensagem_recebida.begins_with("PLC|"):
			var partes = mensagem_recebida.split("|")
			if partes.size() >= 5:
				var pid = int(partes[1])
				var item_type = partes[2]
				var pos = Vector2(float(partes[3]), float(partes[4]))
				current_selected_items.erase(pid)
				_register_placed_item(item_type, pos)
		
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
		if role == Role.HOST:
			# Avisa todos os clientes que o host encerrou.
			var msg_quit := "Q|0"
			var buffer_quit := msg_quit.to_utf8_buffer()
			for key in connected_clients.keys():
				var dados = connected_clients[key]
				udp.set_dest_address(dados["ip"], dados["port"])
				udp.put_packet(buffer_quit)
		
		elif role == Role.CLIENT and my_player_id != -1:
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
	players_skin.erase(id_desconectado)
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

func send_skin_state(skin: String) -> void:
	my_skin_name = skin
	players_skin[my_player_id] = skin
	lobby_players_updated.emit()
	
	if role == Role.HOST:
		if players_nodes.has(my_player_id):
			var boneco = players_nodes[my_player_id]
			if is_instance_valid(boneco) and boneco.has_method("set_skin"):
				boneco.set_skin(skin)
		
		var msg = "SKN|%d|%s" % [my_player_id, skin]
		var buffer = msg.to_utf8_buffer()
		for key in connected_clients.keys():
			var dados = connected_clients[key]
			udp.set_dest_address(dados["ip"], dados["port"])
			udp.put_packet(buffer)
		
	elif role == Role.CLIENT and my_player_id != -1:
		udp.set_dest_address(join_address, port)
		var msg = "SKN|%d|%s" % [my_player_id, skin]
		udp.put_packet(msg.to_utf8_buffer())

func start_game_host() -> void:
	if role == Role.HOST:
		placed_items.clear()
		current_build_options.clear()
		current_selected_items.clear()
		build_order.clear()
		current_builder_id = -1
		round_number = 0
		current_state = GameState.PLAYING
		var buffer = "START|".to_utf8_buffer()
		for key in connected_clients.keys():
			udp.set_dest_address(connected_clients[key]["ip"], connected_clients[key]["port"])
			udp.put_packet(buffer)
		
		get_tree().change_scene_to_file("res://scenes/FaseTeste.tscn")
		game_phase_changed.emit(current_state)

func _set_phase_from_name(phase_name: String) -> void:
	match phase_name:
		"LOBBY":
			current_state = GameState.LOBBY
		"PICKING":
			current_state = GameState.PICKING
		"BUILDING":
			current_state = GameState.BUILDING
		_:
			current_state = GameState.PLAYING
	game_phase_changed.emit(current_state)

func _broadcast_text(msg: String) -> void:
	var buffer = msg.to_utf8_buffer()
	for key in connected_clients.keys():
		var dados = connected_clients[key]
		udp.set_dest_address(dados["ip"], dados["port"])
		udp.put_packet(buffer)

func _begin_build_phase(_winner_id: int) -> void:
	if role != Role.HOST:
		return
	if current_state == GameState.PICKING or current_state == GameState.BUILDING:
		return
	
	round_number += 1
	current_state = GameState.PICKING
	current_build_options.clear()
	current_selected_items.clear()
	current_builder_id = -1
	build_order.clear()
	
	var ids := players_data.keys()
	ids.sort()
	for id in ids:
		var iid = int(id)
		build_order.append(iid)
		current_build_options[iid] = _generate_item_options()
	
	game_phase_changed.emit(current_state)
	build_data_updated.emit()
	_broadcast_text("PHASE|PICKING|%d" % round_number)
	
	for id in current_build_options.keys():
		var options: Array = current_build_options[id]
		var msg = "OPT|%d|%s" % [id, ",".join(options)]
		_broadcast_text(msg)

func _generate_item_options() -> Array[String]:
	## Todas as opções do catálogo (não é mais subconjunto aleatório de 3).
	return BUILD_ITEM_POOL.duplicate()

func send_finish_reached() -> void:
	if my_player_id == -1:
		return
	if role == Role.HOST:
		_begin_build_phase(my_player_id)
	else:
		udp.set_dest_address(join_address, port)
		udp.put_packet(("FIN|%d" % my_player_id).to_utf8_buffer())

func send_item_selection(item_type: String) -> void:
	if my_player_id == -1:
		return
	current_selected_items[my_player_id] = item_type
	build_data_updated.emit()
	if role == Role.HOST:
		_on_item_selected_host(my_player_id, item_type)
	else:
		udp.set_dest_address(join_address, port)
		udp.put_packet(("SEL|%d|%s" % [my_player_id, item_type]).to_utf8_buffer())

func _on_item_selected_host(player_id: int, item_type: String) -> void:
	if role != Role.HOST:
		return
	if current_state != GameState.PICKING:
		return
	if not build_order.has(player_id):
		return
	current_selected_items[player_id] = item_type
	build_data_updated.emit()
	_broadcast_text("SEL|%d|%s" % [player_id, item_type])
	
	for id in build_order:
		if not current_selected_items.has(id):
			return
	_start_next_build_turn()

func _start_next_build_turn() -> void:
	if build_order.is_empty():
		current_builder_id = -1
		current_state = GameState.PLAYING
		game_phase_changed.emit(current_state)
		_broadcast_text("PHASE|PLAYING|%d" % round_number)
		return
	
	current_builder_id = int(build_order[0])
	current_state = GameState.BUILDING
	game_phase_changed.emit(current_state)
	build_data_updated.emit()
	_broadcast_text("TURN|%d" % current_builder_id)

func send_item_placement(item_type: String, position: Vector2) -> void:
	if my_player_id == -1:
		return
	if not validate_build_placement(position):
		return
	if role == Role.HOST:
		_on_item_placed_host(my_player_id, item_type, position)
	else:
		udp.set_dest_address(join_address, port)
		udp.put_packet(("PLC|%d|%s|%f|%f" % [my_player_id, item_type, position.x, position.y]).to_utf8_buffer())

## Livre = sem tile no layer `Chao` da cena atual e sem outro item na mesma âncora.
func validate_build_placement(world_position: Vector2) -> bool:
	for item in placed_items:
		var p := Vector2(float(item.get("x", 0.0)), float(item.get("y", 0.0)))
		if p.distance_squared_to(world_position) < 4.0:
			return false
	var tree := get_tree()
	if tree == null:
		return true
	var scene: Node = tree.current_scene
	if scene == null:
		return true
	var chao_node: Node = scene.get_node_or_null("Chao")
	if chao_node is TileMapLayer:
		var chao: TileMapLayer = chao_node
		if chao.tile_set != null:
			var local := chao.to_local(world_position)
			var cell: Vector2i = chao.local_to_map(local)
			if chao.get_cell_source_id(cell) != -1:
				return false
	return true

func _on_item_placed_host(player_id: int, item_type: String, position: Vector2) -> void:
	if role != Role.HOST:
		return
	if current_state != GameState.BUILDING:
		return
	if player_id != current_builder_id:
		return
	if not current_selected_items.has(player_id):
		return
	if not validate_build_placement(position):
		return
	
	current_selected_items.erase(player_id)
	_register_placed_item(item_type, position)
	_broadcast_text("PLC|%d|%s|%f|%f" % [player_id, item_type, position.x, position.y])
	
	if not build_order.is_empty():
		build_order.remove_at(0)
	_start_next_build_turn()

func _register_placed_item(item_type: String, position: Vector2) -> void:
	placed_items.append({
		"type": item_type,
		"x": position.x,
		"y": position.y
	})
	item_placed.emit(item_type, position)
	build_data_updated.emit()
		

func _exit_tree() -> void:
	udp.close()
