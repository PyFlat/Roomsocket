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

  RoomSocketShelfAdapter(
    this.server, {
    this.path = 'ws',
    this.authenticator,
    this.notFoundResponse,
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
          server.handleSocket(channel);
        },
        pingInterval: Duration(seconds: 10),
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
