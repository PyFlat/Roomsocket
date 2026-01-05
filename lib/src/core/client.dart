import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class ConnectedClient {
  final String id;
  final WebSocketChannel channel;
  final dynamic payload;
  final Duration heartbeatInterval;
  final Duration disconnectDuration;
  Timer? _pingTimer;
  Timer? _disconnectTimer;

  ConnectedClient({
    required this.id,
    required this.channel,
    this.heartbeatInterval = const Duration(seconds: 10),
    this.disconnectDuration = const Duration(seconds: 30),
    this.payload,
  }) {
    _startHeartbeat();
  }

  void send(dynamic json) {
    channel.sink.add(jsonEncode(json));
  }

  Stream<dynamic> get stream =>
      channel.stream.map((event) => jsonDecode(event));

  void close() {
    _pingTimer?.cancel();
    _disconnectTimer?.cancel();
    channel.sink.close();
  }

  void _startHeartbeat() {
    send({"type": "ping"});
    _pingTimer = Timer.periodic(heartbeatInterval, (_) {
      send({"type": "ping"});

      _disconnectTimer = Timer(disconnectDuration, () {
        close();
      });
    });
  }

  void resetTimer() {
    _disconnectTimer?.cancel();
  }
}
