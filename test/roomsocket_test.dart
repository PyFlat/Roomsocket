import 'dart:async';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:roomsocket/roomsocket.dart';
import 'package:roomsocket/src/core/room_manager.dart';

void main() {
  group('RoomSocketClient', () {
    test('should create client with id, channel, and authData', () {
      final controller = StreamController<dynamic>();
      final channel = _MockWebSocketChannel(
        controller.stream,
        _MockSink(),
      );

      final client = ConnectedClient(
        id: 'test-id',
        channel: channel,
      );

      expect(client.id, 'test-id');
    });

    test('should send JSON encoded messages', () {
      final controller = StreamController<dynamic>();
      final mockSink = _MockSink();
      final channel = _MockWebSocketChannel(
        controller.stream,
        mockSink,
      );

      final client = ConnectedClient(
        id: 'test-id',
        channel: channel,
      );

      client.send({'type': 'test', 'data': 'hello'});

      expect(mockSink.messages.length, 1);
      expect(mockSink.messages[0], '{"type":"test","data":"hello"}');
    });

    test('should decode received messages from stream', () async {
      final controller = StreamController<dynamic>();
      final mockSink = _MockSink();
      final channel = _MockWebSocketChannel(
        controller.stream,
        mockSink,
      );

      final client = ConnectedClient(
        id: 'test-id',
        channel: channel,
      );

      final messagesFuture = client.stream.take(2).toList();

      controller.add('{"type":"message1"}');
      controller.add('{"type":"message2"}');

      final messages = await messagesFuture;
      expect(messages[0], {'type': 'message1'});
      expect(messages[1], {'type': 'message2'});

      controller.close();
    });

    test('should close channel', () {
      final controller = StreamController<dynamic>();
      final mockSink = _MockSink();
      final channel = _MockWebSocketChannel(
        controller.stream,
        mockSink,
      );

      final client = ConnectedClient(
        id: 'test-id',
        channel: channel,
      );

      client.close();

      expect(mockSink.closed, true);
    });
  });

  group('RoomManager', () {
    late RoomManager manager;
    late ConnectedClient client1;
    late ConnectedClient client2;

    setUp(() {
      manager = RoomManager();

      final controller1 = StreamController<dynamic>();
      client1 = ConnectedClient(
        id: 'client-1',
        channel: _MockWebSocketChannel(controller1.stream, _MockSink()),
      );

      final controller2 = StreamController<dynamic>();
      client2 = ConnectedClient(
        id: 'client-2',
        channel: _MockWebSocketChannel(controller2.stream, _MockSink()),
      );
    });

    test('should add client to room', () {
      manager.add('room1', client1);

      final clients = manager.clients('room1').toList();
      expect(clients.length, 1);
      expect(clients[0].id, 'client-1');
    });

    test('should not add same client multiple times to room', () {
      manager.add('room1', client1);
      manager.add('room1', client1);

      final clients = manager.clients('room1').toList();
      expect(clients.length, 1);
      expect(clients[0].id, 'client-1');
    });

    test('should add multiple clients to same room', () {
      manager.add('room1', client1);
      manager.add('room1', client2);

      final clients = manager.clients('room1').toList();
      expect(clients.length, 2);
      expect(clients.map((c) => c.id).toSet(), {'client-1', 'client-2'});
    });

    test('should add client to multiple rooms', () {
      manager.add('room1', client1);
      manager.add('room2', client1);

      expect(manager.clients('room1').toList().length, 1);
      expect(manager.clients('room2').toList().length, 1);
    });

    test('should remove client from specific room', () {
      manager.add('room1', client1);
      manager.add('room1', client2);
      manager.remove('room1', client1);

      final clients = manager.clients('room1').toList();
      expect(clients.length, 1);
      expect(clients[0].id, 'client-2');
    });

    test('should remove empty room after removing last client', () {
      manager.add('room1', client1);
      manager.remove('room1', client1);

      final clients = manager.clients('room1').toList();
      expect(clients.isEmpty, true);
    });

    test('should return empty iterable for non-existent room', () {
      final clients = manager.clients('nonexistent').toList();
      expect(clients.isEmpty, true);
    });

    test('should remove client from all rooms', () {
      manager.add('room1', client1);
      manager.add('room2', client1);
      manager.add('room1', client2);

      manager.removeClient(client1);

      expect(manager.clients('room1').toList().length, 1);
      expect(manager.clients('room1').first.id, 'client-2');
      expect(manager.clients('room2').toList().isEmpty, true);
    });

    test('should handle removing client that is not in any room', () {
      manager.removeClient(client1);
      // Should not throw
      expect(manager.clients('room1').toList().isEmpty, true);
    });
  });

  group('RoomSocketServer', () {
    late RoomSocketServer server;

    setUp(() {
      server = RoomSocketServer();
    });

    test('should handle new WebSocket connection', () async {
      final controller = StreamController<dynamic>();
      final channel = _MockWebSocketChannel(
        controller.stream,
        _MockSink(),
      );

      var connectCalled = false;
      server.onConnect = (client) {
        connectCalled = true;
        expect(client.id.isNotEmpty, true);
      };

      await server.handleSocket(channel);

      expect(connectCalled, true);
      expect(server.clients.length, 1);

      controller.close();
    });

    test('should call onMessage when client sends message', () async {
      final controller = StreamController<dynamic>();
      final channel = _MockWebSocketChannel(
        controller.stream,
        _MockSink(),
      );

      var messageCalled = false;
      dynamic receivedMessage;
      ConnectedClient? receivedClient;

      server.onMessage = (client, message) {
        messageCalled = true;
        receivedMessage = message;
        receivedClient = client;
      };

      await server.handleSocket(channel);

      controller.add('test message');
      await Future.delayed(Duration.zero);

      expect(messageCalled, true);
      expect(receivedMessage, 'test message');
      expect(receivedClient?.id.isNotEmpty, true);

      controller.close();
    });

    test('should call onDisconnect when connection closes', () async {
      final controller = StreamController<dynamic>();
      final channel = _MockWebSocketChannel(
        controller.stream,
        _MockSink(),
      );

      var disconnectCalled = false;
      String? disconnectedClientId;

      server.onDisconnect = (client) {
        disconnectCalled = true;
        disconnectedClientId = client.id;
      };

      await server.handleSocket(channel);
      final clientId = server.clients.first.id;

      controller.close();
      await Future.delayed(Duration.zero);

      expect(disconnectCalled, true);
      expect(disconnectedClientId, clientId);
      expect(server.clients.isEmpty, true);
    });

    test('should add client to room', () async {
      final controller = StreamController<dynamic>();
      final mockSink = _MockSink();
      final channel = _MockWebSocketChannel(
        controller.stream,
        mockSink,
      );

      await server.handleSocket(channel);
      final client = server.clients.first;

      server.addToRoom('game-1', client);

      // Verify by broadcasting to the room
      mockSink.messages.clear();

      server.broadcast('game-1', {'type': 'test'});

      expect(mockSink.messages.length, 1);
      expect(mockSink.messages[0], '{"type":"test"}');

      controller.close();
    });

    test('should remove client from specific room', () async {
      final controller = StreamController<dynamic>();
      final mockSink = _MockSink();
      final channel = _MockWebSocketChannel(
        controller.stream,
        mockSink,
      );

      await server.handleSocket(channel);
      final client = server.clients.first;

      server.addToRoom('game-1', client);
      mockSink.messages.clear();

      server.removeFromRoom('game-1', client);
      server.broadcast('game-1', {'type': 'test'});

      expect(mockSink.messages.isEmpty, true);

      controller.close();
    });

    test('should broadcast message to all clients in room', () async {
      final controller1 = StreamController<dynamic>();
      final mockSink1 = _MockSink();
      final channel1 = _MockWebSocketChannel(controller1.stream, mockSink1);

      final controller2 = StreamController<dynamic>();
      final mockSink2 = _MockSink();
      final channel2 = _MockWebSocketChannel(controller2.stream, mockSink2);

      await server.handleSocket(channel1);
      await server.handleSocket(channel2);

      final client1 = server.clients.first;
      final client2 = server.clients.last;

      server.addToRoom('game-1', client1);
      server.addToRoom('game-1', client2);

      server.broadcast('game-1', {'type': 'broadcast', 'data': 'hello'});

      expect(mockSink1.messages.length, 1);
      expect(mockSink2.messages.length, 1);
      expect(mockSink1.messages[0], '{"type":"broadcast","data":"hello"}');
      expect(mockSink2.messages[0], '{"type":"broadcast","data":"hello"}');

      controller1.close();
      controller2.close();
    });

    test('should send message to specific client', () async {
      final controller = StreamController<dynamic>();
      final mockSink = _MockSink();
      final channel = _MockWebSocketChannel(controller.stream, mockSink);

      await server.handleSocket(channel);
      final client = server.clients.first;

      server.send(client, {'type': 'direct', 'message': 'hello'});

      expect(mockSink.messages.length, 1);
      expect(mockSink.messages[0], '{"type":"direct","message":"hello"}');

      controller.close();
    });

    test('should remove client from all rooms on disconnect', () async {
      final controller1 = StreamController<dynamic>();
      final mockSink1 = _MockSink();
      final channel1 = _MockWebSocketChannel(controller1.stream, mockSink1);

      final controller2 = StreamController<dynamic>();
      final mockSink2 = _MockSink();
      final channel2 = _MockWebSocketChannel(controller2.stream, mockSink2);

      await server.handleSocket(channel1);
      await server.handleSocket(channel2);

      final client1 = server.clients.first;
      final client2 = server.clients.last;

      server.addToRoom('game-1', client1);
      server.addToRoom('game-1', client2);

      // Close first client
      controller1.close();
      await Future.delayed(Duration.zero);

      mockSink2.messages.clear();
      server.broadcast('game-1', {'type': 'test'});

      // Only client2 should receive the broadcast
      expect(mockSink1.messages.isEmpty, true);
      expect(mockSink2.messages.length, 1);

      controller2.close();
    });

    test('should generate unique client IDs', () async {
      final controller1 = StreamController<dynamic>();
      final channel1 = _MockWebSocketChannel(controller1.stream, _MockSink());

      final controller2 = StreamController<dynamic>();
      final channel2 = _MockWebSocketChannel(controller2.stream, _MockSink());

      await server.handleSocket(channel1);
      await server.handleSocket(channel2);

      final ids = server.clients.map((c) => c.id).toList();
      expect(ids.length, 2);
      expect(ids[0] != ids[1], true);

      controller1.close();
      controller2.close();
    });
  });
}

// Mock WebSocketChannel for testing
class _MockWebSocketChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  final Stream<dynamic> _stream;
  final _MockWebSocketSink _sink;

  _MockWebSocketChannel(this._stream, StreamSink<dynamic> rawSink)
      : _sink = _MockWebSocketSink(rawSink);

  @override
  Stream<dynamic> get stream => _stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future.value();
}

// Mock WebSocketSink
class _MockWebSocketSink implements WebSocketSink {
  final StreamSink<dynamic> _inner;

  _MockWebSocketSink(this._inner);

  @override
  void add(dynamic event) => _inner.add(event);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future addStream(Stream stream) => _inner.addStream(stream);

  @override
  Future close([int? closeCode, String? closeReason]) => _inner.close();

  @override
  Future get done => _inner.done;
}

// Mock sink for testing
class _MockSink implements StreamSink<dynamic> {
  final List<String> messages = [];
  bool closed = false;

  @override
  void add(dynamic event) {
    messages.add(event);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream stream) async {}

  @override
  Future close() async {
    closed = true;
  }

  @override
  Future get done => Future.value();
}
