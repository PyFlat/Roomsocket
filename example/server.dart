import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:roomsocket/roomsocket.dart';
import 'package:shelf_router/shelf_router.dart';

void main() async {
  final server = RoomSocketServer();

  server.onConnect = (client) {
    print('Connected: ${client.id}');
    server.addToRoom('chat', client);
  };

  server.onDisconnect = (client) {
    print('Disconnected: ${client.id}');
  };

  server.onMessage = (client, data) {
    final json = jsonDecode(data as String);
    server.broadcast('chat', {
      'from': client.id,
      'message': json['message'],
    });
  };

  final shelfAdapter =
      RoomSocketShelfAdapter(server, authenticator: (request) async {
    final token = request.headers['authorization'];
    if (token != 'Bearer secret') {
      return Response.forbidden('Unauthorized');
    }
    return null;
  });

  final router = Router();

  router.get('/health', (Request request) {
    return Response.ok(
      jsonEncode({'status': 'ok'}),
      headers: {'content-type': 'application/json'},
    );
  });

  router.post('/echo', (Request request) async {
    final body = await request.readAsString();
    return Response.ok(
      body,
      headers: {'content-type': 'application/json'},
    );
  });

  final handler =
      Pipeline().addMiddleware(logRequests()).addHandler((Request request) {
    final httpResponse = router(request);
    return httpResponse.then((response) {
      if (response.statusCode == 404) {
        return shelfAdapter.handler(request);
      }
      return response;
    });
  });

  await io.serve(handler, 'localhost', 8080);
  print('Server running on ws://localhost:8080/ws');
}
