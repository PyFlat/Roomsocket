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
  bool _paused = false;
  bool _isConnecting = false;

  int _generation = 0;

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
  bool get isPaused => _paused;

  Future<bool> connect({Uri? uri}) async {
    if (_connected) return false;
    _isConnecting = true;
    _manuallyClosed = false;
    _paused = false;

    if (uri != null) this.uri = uri;
    _headers = await headerProvider?.call() ?? _headers;

    final generation = ++_generation;
    WebSocketChannel? channel;

    try {
      await _killSocket();
      final finalUri = _prepareUri();

      channel = isWeb
          ? WebSocketChannel.connect(finalUri)
          : IOWebSocketChannel.connect(
              finalUri,
              headers: _headers,
              connectTimeout: timeoutDuration,
            );

      await channel.ready.timeout(timeoutDuration);

      if (generation != _generation) {
        await _closeChannel(channel);
        return false;
      }

      _channel = channel;
      _connected = true;
      _attachListeners(channel, generation);
      _flushQueue();
      onConnect?.call();
      return true;
    } catch (e) {
      if (channel != null) await _closeChannel(channel);

      if (generation == _generation) {
        _connected = false;
        onReconnectFailed?.call(e);
        _ensureReconnectLoop();
      }
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  Future<bool> reconnect({Uri? uri}) async {
    _manuallyClosed = false;
    _paused = false;
    _generation++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _killSocket();
    _isConnecting = false;
    return await connect(uri: uri);
  }

  Future<void> pause() async {
    if (_paused) return;
    _paused = true;
    _generation++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _killSocket();
  }

  Future<bool> resume() async {
    if (!_paused) return _connected;
    _paused = false;
    _generation++;
    _isConnecting = false;
    return await connect();
  }

  void _ensureReconnectLoop() {
    if (_manuallyClosed || _paused || _connected || _reconnectTimer != null) {
      return;
    }

    _reconnectTimer = Timer.periodic(reconnectInterval, (timer) {
      if (_connected || _manuallyClosed || _paused) {
        timer.cancel();
        _reconnectTimer = null;
        return;
      }

      if (!_isConnecting) {
        connect();
      }
    });
  }

  void _attachListeners(WebSocketChannel channel, int generation) {
    channel.stream.listen(
      (data) {
        if (generation != _generation) return;
        final wasHandledInternally = _handleIncomingData(data);
        if (!wasHandledInternally) {
          for (var listener in List.of(_manualDataListeners)) {
            listener(data);
          }
        }
      },
      onDone: () => _handleDisconnection(generation),
      onError: (error) => _handleDisconnection(generation, error: error),
      cancelOnError: true,
    );
  }

  void _handleDisconnection(int generation, {Object? error}) {
    if (generation != _generation) return;

    _connected = false;
    _channel = null;

    if (error != null) {
      for (var listener in List.of(_manualErrorListeners)) {
        listener(error);
      }
    }
    for (var listener in List.of(_manualDoneListeners)) {
      listener();
    }

    if (!_manuallyClosed && !_paused) {
      _ensureReconnectLoop();
    }
  }

  String? _findHeader(String name) {
    if (_headers == null) return null;
    for (final entry in _headers!.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }

  Uri _prepareUri() {
    if (!isWeb) return uri;

    final authHeader = _findHeader('authorization');
    if (authHeader == null) return uri;

    final token =
        authHeader.replaceFirst(RegExp('^Bearer ', caseSensitive: false), '');
    return uri.replace(
      queryParameters: {...uri.queryParameters, "token": token},
    );
  }

  Future<void> _killSocket() async {
    final channel = _channel;
    _channel = null;
    _connected = false;
    if (channel == null) return;
    await _closeChannel(channel);
  }

  Future<void> _closeChannel(WebSocketChannel channel) async {
    try {
      await channel.sink.close().timeout(
            const Duration(seconds: 1),
            onTimeout: () {},
          );
    } catch (e) {
      print("Error while killing socket: $e");
    }
  }

  void send(dynamic message) {
    if (_connected && _channel != null) {
      try {
        _channel!.sink.add(message);
        return;
      } catch (_) {
        // Sink is already broken (e.g. dead-but-not-yet-detected socket);
        // fall through to queue it like any other disconnected send.
      }
    }
    _sendQueue.add(message);
    if (!_paused) _ensureReconnectLoop();
  }

  void _flushQueue() {
    while (_sendQueue.isNotEmpty && _connected && _channel != null) {
      final message = _sendQueue.removeAt(0);
      try {
        _channel!.sink.add(message);
      } catch (_) {
        _sendQueue.insert(0, message);
        break;
      }
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
    _paused = false;
    _generation++;
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
