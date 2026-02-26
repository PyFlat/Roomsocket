import 'dart:convert';

import 'package:roomsocket/roomsocket.dart';

void main() async {
  RoomSocketClient socket =
      RoomSocketClient(Uri.parse('ws://localhost:8080/ws'), headers: {
    'authorization': 'Bearer secret',
  }, onConnect: () {
    print('Connected to the server.');
  });

  final connected = await socket.connect();
  if (!connected) {
    return;
  }

  socket.listen((data) {
    print('Received: $data');
  }, onDone: () {
    print('Connection closed.');
  }, onError: (error) {
    print('Error: $error');
  });

  socket.send(jsonEncode({'message': 'Hello, Server!'}));

  Future.delayed(Duration(seconds: 3), () {
    socket.reconnect();
  });
}
