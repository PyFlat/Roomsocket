import 'client.dart';

class RoomManager {
  final Map<String, Set<ConnectedClient>> _rooms = {};
  final Map<ConnectedClient, Set<String>> _clientRooms = {};

  void add(String room, ConnectedClient client) {
    _rooms.putIfAbsent(room, () => {}).add(client);
    _clientRooms.putIfAbsent(client, () => {}).add(room);
  }

  void remove(String room, ConnectedClient client) {
    _rooms[room]?.remove(client);
    _clientRooms[client]?.remove(room);
    if (_rooms[room]?.isEmpty ?? false) {
      _rooms.remove(room);
    }
    if (_clientRooms[client]?.isEmpty ?? false) {
      _clientRooms.remove(client);
    }
  }

  Iterable<ConnectedClient> clients(String room) {
    return _rooms[room] ?? const [];
  }

  void removeClient(ConnectedClient client) {
    for (final room in (_clientRooms[client] ?? {}).toList()) {
      remove(room, client);
    }
  }
}
