import 'dart:async';
import 'dart:convert';
import 'dart:io';

class RoomSocketClient {
  Uri uri;
  final Future<Map<String, String>?> Function()? headerProvider;
  final Function? onConnect;
  final Duration reconnectInterval;
  final Duration timeoutDuration;

  WebSocket? _socket;
  Timer? _reconnectTimer;
  Map<String, String>? _headers;
  bool _connected = false;
  bool _manuallyClosed = false;

  final List<dynamic> _sendQueue = [];

  int? errorCode;

  final List<void Function(dynamic)> _manualDataListeners = [];
  final List<void Function()> _manualDoneListeners = [];
  final List<void Function(dynamic)> _manualErrorListeners = [];

  RoomSocketClient(
    this.uri, {
    Map<String, String>? headers,
    this.headerProvider,
    this.onConnect,
    this.reconnectInterval = const Duration(seconds: 5),
    this.timeoutDuration = const Duration(seconds: 10),
  }) : _headers = headers;

  WebSocket? get socket => _socket;
  bool get isConnected => _connected;

  Future<bool> connect({Uri? uri}) async {
    if (uri != null) this.uri = uri;
    _headers = await headerProvider?.call() ?? _headers;

    try {
      _socket = await WebSocket.connect(
        this.uri.toString(),
        headers: _headers,
      ).timeout(timeoutDuration);

      _connected = true;
      onConnect?.call();
      _attachListeners();
      _flushQueue();
      _stopReconnectLoop();
      return true;
    } on WebSocketException catch (e) {
      errorCode = e.httpStatusCode ?? 0;
      _connected = false;
      if (!_manuallyClosed) _startReconnectLoop();
      return false;
    } catch (_) {
      errorCode = 0;
      _connected = false;
      if (!_manuallyClosed) _startReconnectLoop();
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
      if (!_connected) {
        await connect();
      }
    });
  }

  void _stopReconnectLoop() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void send(dynamic message) {
    if (_connected && _socket != null) {
      try {
        _socket!.add(message);
      } catch (_) {
        _sendQueue.add(message);
        if (!_manuallyClosed) _startReconnectLoop();
      }
    } else {
      _sendQueue.add(message);
      if (!_manuallyClosed) _startReconnectLoop();
    }
  }

  void _flushQueue() {
    while (_sendQueue.isNotEmpty && _connected && _socket != null) {
      final msg = _sendQueue.removeAt(0);
      try {
        _socket!.add(msg);
      } catch (_) {
        _sendQueue.insert(0, msg);
        break;
      }
    }
  }

  void listen(
    void Function(dynamic data) onData, {
    void Function()? onDone,
    void Function(dynamic error)? onError,
  }) {
    _manualDataListeners.add(onData);
    if (onDone != null) _manualDoneListeners.add(onDone);
    if (onError != null) _manualErrorListeners.add(onError);
  }

  void _attachListeners(
      {void Function(dynamic data)? onData,
      void Function()? onDone,
      void Function(dynamic error)? onError}) {
    _socket?.listen(
      (data) {
        try {
          final msg = jsonDecode(data);
          if (msg is Map && msg['type'] == 'ping') {
            _socket!.add(jsonEncode({"type": "pong"}));
            return;
          }
        } catch (_) {}

        for (var listener in _manualDataListeners) {
          listener(data);
        }

        onData?.call(data);
      },
      onDone: () {
        _connected = false;
        _socket = null;

        for (var listener in _manualDoneListeners) {
          listener();
        }

        onDone?.call();
        if (!_manuallyClosed) _startReconnectLoop();
      },
      onError: (error) {
        _connected = false;
        _socket = null;

        for (var listener in _manualErrorListeners) {
          listener(error);
        }

        onError?.call(error);
        if (!_manuallyClosed) _startReconnectLoop();
      },
      cancelOnError: true,
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
        await _socket!.close(code ?? WebSocketStatus.normalClosure, reason);
      } catch (_) {}
      _socket = null;
      _connected = false;
    }
  }
}
