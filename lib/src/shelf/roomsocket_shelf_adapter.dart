import 'dart:async';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../server/roomsocket_server.dart';

class RoomSocketShelfAdapter {
  final RoomSocketServer server;
  final String path;

  final FutureOr<Response?> Function(Request request)? authenticator;
  final Response Function()? notFoundResponse;

  final dynamic Function(Request request)? extractRequestData;

  RoomSocketShelfAdapter(
    this.server, {
    this.path = 'ws',
    this.authenticator,
    this.notFoundResponse,
    this.extractRequestData,
  });

  Handler get handler {
    return (Request request) async {
      if (request.url.path != path) {
        return rejectRequest(
            notFoundResponse?.call() ?? Response.notFound('Not Found'));
      }

      if (authenticator != null) {
        final authResponse = await authenticator!(request);
        if (authResponse != null) {
          return rejectRequest(authResponse);
        }
      }

      final wsHandler = webSocketHandler(
        (WebSocketChannel channel, _) {
          final payload = extractRequestData?.call(request);
          server.handleSocket(channel, payload: payload);
        },
      );

      return wsHandler(request);
    };
  }

  Response rejectRequest(Response response) {
    return response.change(
      headers: {
        ...response.headers,
        'connection': 'close',
      },
    );
  }
}
