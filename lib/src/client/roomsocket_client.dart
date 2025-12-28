import 'dart:io';

class RoomSocketClient {
  final Uri uri;
  final Map<String, String>? headers;

  WebSocket? _socket;
  int? errorCode;

  Function? onConnect;

  RoomSocketClient(this.uri, {this.headers, this.onConnect});

  WebSocket? get socket => _socket;

  Future<bool> connect() async {
    try {
      _socket = await WebSocket.connect(
        uri.toString(),
        headers: headers,
      );

      bool closedImmediately = false;
      _socket!.done.then((_) {
        closedImmediately = true;
        _socket = null;
      });

      await Future.delayed(Duration(milliseconds: 50));

      if (closedImmediately) {
        errorCode = 401;
        return false;
      }

      onConnect?.call();
      return true;
    } on WebSocketException catch (e) {
      errorCode = e.httpStatusCode ?? 0;
      return false;
    } catch (_) {
      errorCode = 0;
      return false;
    }
  }

  void send(dynamic message) {
    if (_socket != null) {
      _socket!.add(message);
    } else {
      throw Exception('Cannot send message. Socket not connected.');
    }
  }

  void listen(
    void Function(dynamic data) onData, {
    void Function()? onDone,
    void Function(dynamic error)? onError,
  }) {
    if (_socket != null) {
      _socket!.listen(
        onData,
        onDone: () {
          onDone?.call();
          _socket = null;
        },
        onError: (error) {
          onError?.call(error);
          _socket = null;
        },
      );
    } else {
      throw Exception('Cannot listen. Socket not connected.');
    }
  }

  Future<void> close([int? code, String? reason]) async {
    if (_socket != null) {
      await _socket!.close(code ?? WebSocketStatus.normalClosure, reason);
      _socket = null;
    }
  }
}
