import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/client.dart';
import '../core/room_manager.dart';

typedef MessageHandler = void Function(
  ConnectedClient client,
  dynamic message,
);

class RoomSocketServer {
  final _uuid = const Uuid();
  final _clients = <String, ConnectedClient>{};
  final _rooms = RoomManager();

  void Function(ConnectedClient client)? onConnect;
  void Function(ConnectedClient client)? onDisconnect;
  MessageHandler? onMessage;

  Future<void> handleSocket(WebSocketChannel channel, {dynamic payload}) async {
    final client = ConnectedClient(
      id: _uuid.v4(),
      channel: channel,
      payload: payload,
    );

    _clients[client.id] = client;
    onConnect?.call(client);

    channel.stream.listen(
      (data) => onMessage?.call(client, data),
      onDone: () => _remove(client),
      onError: (_) => _remove(client),
    );
  }

  Iterable<ConnectedClient> get clients => _clients.values;

  void addToRoom(String room, ConnectedClient client) {
    _rooms.add(room, client);
  }

  void removeFromRoom(String room, ConnectedClient client) {
    _rooms.remove(room, client);
  }

  void broadcast(String room, dynamic json) {
    for (final client in _rooms.clients(room)) {
      client.send(json);
    }
  }

  void send(ConnectedClient client, dynamic json) {
    client.send(json);
  }

  void _remove(ConnectedClient client) {
    _rooms.removeClient(client);
    _clients.remove(client.id);
    onDisconnect?.call(client);
  }
}
