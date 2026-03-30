extends SceneTree

func _init():
	var done := false # := força o tipo da variável, 
	# é mais rápido e evita uns bugs futuros, também ajuda a debugar
	var socket := PacketPeerUDP.new()
	var numero_porta := 8080
	
	if (socket.bind(numero_porta, "127.0.0.1") != OK):
		# 127.0.0.1 é o endereço onde serão feitas as requisições
		print ("Um erro ocorreu tentando escutar na porta %d" % numero_porta)
	else:
		print ("Escutando na porta %d no localhost" % numero_porta)
		
	while (!done):
		if (socket.get_available_packet_count() > 0):
			var data := socket.get_packet().get_string_from_utf8()
			if (data == "quit"):
				done = true
			else:
				print ("Data recebida: %s" % data)
		
		OS.delay_msec(10) # Pausa o loop por 10ms pra n usar tudo da CPU aqui

	socket.close()
	print ("Saindo da aplicação")
	self.quit()
