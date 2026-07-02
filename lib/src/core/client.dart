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
  bool _closed = false;

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
    if (_closed) return;
    try {
      channel.sink.add(jsonEncode(json));
    } catch (_) {
      close();
    }
  }

  Stream<dynamic> get stream =>
      channel.stream.map((event) => jsonDecode(event));

  void close() {
    if (_closed) return;
    _closed = true;
    _pingTimer?.cancel();
    _pingTimer = null;
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
    try {
      channel.sink.close();
    } catch (_) {}
  }

  void _startHeartbeat() {
    send({"type": "ping"});
    _pingTimer = Timer.periodic(heartbeatInterval, (_) {
      _disconnectTimer?.cancel();
      send({"type": "ping"});
      _disconnectTimer = Timer(disconnectDuration, close);
    });
  }

  void resetTimer() {
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
  }
}
