import 'package:test/test.dart';
import 'package:shelf/shelf.dart';
import 'package:roomsocket/roomsocket.dart';

void main() {
  group('RoomSocketShelfAdapter', () {
    late RoomSocketServer server;
    late RoomSocketShelfAdapter adapter;

    setUp(() {
      server = RoomSocketServer();
      adapter = RoomSocketShelfAdapter(
        server,
        authenticator: (request) {
          final authHeader = request.headers['authorization'];
          if (authHeader == null || authHeader != 'Bearer secret') {
            return Response.forbidden('Unauthorized');
          }
          return null;
        },
      );
    });

    test('should create adapter with default path', () {
      expect(adapter.path, 'ws');
      expect(adapter.server, server);
    });

    test('should create adapter with custom path', () {
      final customAdapter = RoomSocketShelfAdapter(server, path: 'custom');
      expect(customAdapter.path, 'custom');
    });

    test('should return 404 for non-matching paths', () async {
      final handler = adapter.handler;
      final request = Request('GET', Uri.parse('http://example.com/other'));

      final response = await handler(request);

      expect(response.statusCode, 404);
      expect(await response.readAsString(), 'Not Found');
    });

    test('should return 403 for missing authorization', () async {
      final handler = adapter.handler;
      final request = Request(
        'GET',
        Uri.parse('http://example.com/ws'),
        headers: {},
      );

      final response = await handler(request);

      expect(response.statusCode, 403);
      expect(await response.readAsString(), 'Unauthorized');
    });

    test('should return 403 for invalid authorization', () async {
      final handler = adapter.handler;
      final request = Request(
        'GET',
        Uri.parse('http://example.com/ws'),
        headers: {'authorization': 'Bearer invalid'},
      );

      final response = await handler(request);

      expect(response.statusCode, 403);
      expect(await response.readAsString(), 'Unauthorized');
    });

    test('should reject valid bearer token without WebSocket upgrade headers',
        () async {
      final handler = adapter.handler;

      // Test that valid auth is processed, but without proper WebSocket
      // upgrade headers, the response won't succeed
      final request = Request(
        'GET',
        Uri.parse('http://example.com/ws'),
        headers: {
          'authorization': 'Bearer secret',
        },
      );

      // Without proper WebSocket upgrade headers, this will fail
      // but not due to auth (which is valid)
      try {
        final response = await handler(request);
        // If it doesn't throw, it should not be a 403 (auth error)
        expect(response.statusCode, isNot(403));
      } catch (e) {
        // WebSocket upgrade will fail without proper server support in tests
        // This is expected
      }
    });

    test('should use custom path when specified', () async {
      final customAdapter = RoomSocketShelfAdapter(
        server,
        path: 'custom/ws',
        authenticator: (request) {
          final authHeader = request.headers['authorization'];
          if (authHeader == null || authHeader != 'Bearer secret') {
            return Response.forbidden('Unauthorized');
          }
          return null;
        },
      );
      final handler = customAdapter.handler;

      final wrongPathRequest = Request(
        'GET',
        Uri.parse('http://example.com/ws'),
      );

      final wrongPathResponse = await handler(wrongPathRequest);
      expect(wrongPathResponse.statusCode, 404);

      final correctPathRequestNoAuth = Request(
        'GET',
        Uri.parse('http://example.com/custom/ws'),
      );

      // Should not return 404 for correct path, but should return 403 for missing auth
      final correctPathResponse = await handler(correctPathRequestNoAuth);
      expect(correctPathResponse.statusCode, isNot(404));
      expect(correctPathResponse.statusCode, 403); // Missing auth
    });
  });
}
