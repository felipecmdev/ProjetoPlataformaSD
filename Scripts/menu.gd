extends Control
@onready var nome_label := $VBoxContainer/NomeText
@onready var error_label := $VBoxContainer/ErrorLabel
const MAX_CARACTERES_NOME := 20

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	NetworkManager.connection_approved.connect(_on_connection_approved)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func validar_nome() -> bool:
	
	# Ele tira os espaços extras nas pontas, e tira os "|" do nome
	# Como a comunicação do jogo é feita por algo como C|%s|%d, e a | significa
	# Que parou uma informação e iniciou a próxima, o jogador poderia colocar
	# No nome dele algo como Nome|1000|1000, e bugar alguma coisa dentro do jogo
	var nome_digitado = nome_label.text.strip_edges().replace("|", "")
	
	if nome_digitado == "":
		error_label.text = "Digite um nome\n
							antes de entrar!"

		error_label.show()
		return false
	
	if nome_digitado.length() > MAX_CARACTERES_NOME:
		error_label.text = "O nome é muito grande!"
		error_label.show()
		return false

	nome_label.text = nome_digitado
	
	error_label.hide()
	NetworkManager.my_player_name = nome_digitado
	return true
	
func _on_host_button_pressed() -> void:
	if !validar_nome():
		return
		
	print("Iniciando como Host")
	NetworkManager.role = NetworkManager.Role.HOST
	NetworkManager.setup_connection()
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")


func _on_join_button_pressed() -> void:
	
	if !validar_nome():
		return
	
	var ip_digitado = %IpTexto.text # Pega o texto do nó LineEdit
	if ip_digitado.strip_edges() == "":
		print ("Nenhum IP foi digitado. Usando IP local para teste (127.0.0.1)")
		ip_digitado = "127.0.0.1"
	
	print ("Conectando ao IP: ", ip_digitado)
	NetworkManager.role = NetworkManager.Role.CLIENT
	NetworkManager.join_address = ip_digitado
	NetworkManager.setup_connection()
	print("Aguardando Aprovação do servidor...")
	
func _on_connection_approved() -> void: # Só muda de cena quando a conexão é aprovada, 
	# senão da um caos completo e ele vira o player 1
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")
