import 'dart:async';
import 'dart:io';

class RoomSocketClient {
  Uri uri;

  final Future<Map<String, String>?> Function()? headerProvider;

  final Function? onConnect;

  final Duration reconnectInterval;

  WebSocket? _socket;
  Timer? _reconnectTimer;
  Map<String, String>? _headers;

  int? errorCode;
  bool _manuallyClosed = false;

  RoomSocketClient(
    this.uri, {
    Map<String, String>? headers,
    this.headerProvider,
    this.onConnect,
    this.reconnectInterval = const Duration(seconds: 5),
  }) : _headers = headers;

  WebSocket? get socket => _socket;
  bool get isConnected => _socket != null;

  Future<bool> connect({Uri? uri}) async {
    try {
      _headers = await headerProvider?.call() ?? _headers;

      if (uri != null) {
        this.uri = uri;
      }

      _socket = await WebSocket.connect(
        this.uri.toString(),
        headers: _headers,
      );

      bool closedImmediately = false;

      _socket!.done.then((_) {
        _socket = null;

        if (!_manuallyClosed) {
          _startReconnectLoop();
        }

        closedImmediately = true;
      });

      await Future.delayed(const Duration(milliseconds: 50));

      if (closedImmediately) {
        errorCode = 401;
        return false;
      }

      _stopReconnectLoop();
      _manuallyClosed = false;

      onConnect?.call();
      return true;
    } on WebSocketException catch (e) {
      errorCode = e.httpStatusCode ?? 0;
      _startReconnectLoop();
      return false;
    } catch (_) {
      errorCode = 0;
      _startReconnectLoop();
      return false;
    }
  }

  Future<void> reconnect({Uri? uri}) async {
    _manuallyClosed = false;
    await _killSocket();
    await connect(uri: uri);
  }

  void _startReconnectLoop() {
    if (_reconnectTimer != null) return;

    _reconnectTimer = Timer.periodic(reconnectInterval, (_) async {
      if (_socket == null) {
        await connect();
      }
    });
  }

  void _stopReconnectLoop() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
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
    if (_socket == null) {
      throw Exception('Cannot listen. Socket not connected.');
    }

    _socket!.listen(
      onData,
      onDone: () {
        _socket = null;
        onDone?.call();
        if (!_manuallyClosed) _startReconnectLoop();
      },
      onError: (error) {
        _socket = null;
        onError?.call(error);
        if (!_manuallyClosed) _startReconnectLoop();
      },
    );
  }

  Future<void> close([int? code, String? reason]) async {
    _manuallyClosed = true;
    _stopReconnectLoop();
    await _killSocket(code, reason);
  }

  Future<void> _killSocket([int? code, String? reason]) async {
    if (_socket != null) {
      try {
        await _socket!.close(
          code ?? WebSocketStatus.normalClosure,
          reason,
        );
      } catch (_) {}
      _socket = null;
    }
  }
}
