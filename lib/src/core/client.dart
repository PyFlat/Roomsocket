import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class ConnectedClient {
  final String id;
  final WebSocketChannel channel;

  ConnectedClient({
    required this.id,
    required this.channel,
  });

  void send(dynamic json) {
    channel.sink.add(jsonEncode(json));
  }

  Stream<dynamic> get stream =>
      channel.stream.map((event) => jsonDecode(event));

  void close() {
    channel.sink.close();
  }
}
