import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

const isWeb = bool.fromEnvironment('dart.library.js_interop');

class RoomSocketClient {
  Uri uri;
  final Future<Map<String, String>?> Function()? headerProvider;
  final Function? onConnect;
  final Function(dynamic)? onReconnectFailed;
  final Duration reconnectInterval;
  final Duration timeoutDuration;

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Map<String, String>? _headers;

  bool _connected = false;
  bool _manuallyClosed = false;
  bool _isConnecting = false;

  final List<dynamic> _sendQueue = [];
  final List<void Function(dynamic)> _manualDataListeners = [];
  final List<void Function()> _manualDoneListeners = [];
  final List<void Function(dynamic)> _manualErrorListeners = [];

  RoomSocketClient(
    this.uri, {
    Map<String, String>? headers,
    this.headerProvider,
    this.onConnect,
    this.onReconnectFailed,
    this.reconnectInterval = const Duration(seconds: 5),
    this.timeoutDuration = const Duration(seconds: 10),
  }) : _headers = headers;

  bool get isConnected => _connected;

  Future<bool> connect({Uri? uri}) async {
    if (_isConnecting || _connected) return false;
    _isConnecting = true;
    _manuallyClosed = false;

    if (uri != null) this.uri = uri;
    _headers = await headerProvider?.call() ?? _headers;

    try {
      await _killSocket();
      Uri finalUri = _prepareUri();

      if (isWeb) {
        _channel = WebSocketChannel.connect(finalUri);
      } else {
        _channel = IOWebSocketChannel.connect(
          finalUri,
          headers: _headers,
          connectTimeout: timeoutDuration,
        );
      }

      await _channel!.ready.timeout(timeoutDuration);

      _connected = true;
      _isConnecting = false;

      _attachListeners();
      _flushQueue();
      onConnect?.call();
      return true;
    } catch (e) {
      _connected = false;
      _isConnecting = false;

      onReconnectFailed?.call(e);

      _ensureReconnectLoop();
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  Future<bool> reconnect({Uri? uri}) async {
    _manuallyClosed = false;

    await _killSocket();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    return await connect(uri: uri);
  }

  void _ensureReconnectLoop() {
    if (_manuallyClosed || _connected || _reconnectTimer != null) return;

    _reconnectTimer = Timer.periodic(reconnectInterval, (timer) async {
      if (_connected || _manuallyClosed) {
        timer.cancel();
        _reconnectTimer = null;
        return;
      }

      if (!_isConnecting) {
        await connect();
      }
    });
  }

  void _attachListeners() {
    _channel?.stream.listen(
      (data) {
        final wasHandledInternally = _handleIncomingData(data);
        if (!wasHandledInternally) {
          for (var listener in _manualDataListeners) {
            listener(data);
          }
        }
      },
      onDone: () => _handleDisconnection("Done"),
      onError: (error) => _handleDisconnection("Error: $error"),
      cancelOnError: true,
    );
  }

  void _handleDisconnection(String reason) {
    _connected = false;
    _channel = null;

    for (var listener in _manualDoneListeners) {
      listener();
    }

    if (!_manuallyClosed) {
      _ensureReconnectLoop();
    }
  }

  Uri _prepareUri() {
    if (isWeb && _headers?["Authorization"] != null) {
      final token = _headers!["Authorization"]!.replaceFirst("Bearer ", "");
      return uri.replace(
        queryParameters: {...uri.queryParameters, "token": token},
      );
    }
    return uri;
  }

  Future<void> _killSocket() async {
    if (_channel == null) return;

    final closingChannel = _channel;
    _channel = null;
    _connected = false;

    try {
      await closingChannel!.sink.close().timeout(
            const Duration(seconds: 1),
            onTimeout: () {},
          );
    } catch (e) {
      print("Error while killing socket: $e");
    }
  }

  void send(dynamic message) {
    if (_connected && _channel != null) {
      _channel!.sink.add(message);
    } else {
      _sendQueue.add(message);
      _ensureReconnectLoop();
    }
  }

  void _flushQueue() {
    while (_sendQueue.isNotEmpty && _connected && _channel != null) {
      _channel!.sink.add(_sendQueue.removeAt(0));
    }
  }

  bool _handleIncomingData(dynamic data) {
    try {
      final msg = jsonDecode(data);
      if (msg is Map && msg['type'] == 'ping') {
        _channel?.sink.add(jsonEncode({"type": "pong"}));
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> close() async {
    _manuallyClosed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _killSocket();
  }

  void listen(void Function(dynamic data) onData,
      {void Function()? onDone, void Function(dynamic error)? onError}) {
    _manualDataListeners.add(onData);
    if (onDone != null) _manualDoneListeners.add(onDone);
    if (onError != null) _manualErrorListeners.add(onError);
  }
}
