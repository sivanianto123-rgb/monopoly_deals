import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'models/client_view.dart';

enum ConnectionStatus { disconnected, connecting, connected, failed }

/// Owns the WebSocket connection to the Monopoly Deal server and exposes
/// everything the UI needs as plain observable state (see
/// server/README.md for the wire protocol this speaks). The server is the
/// only source of truth — this class never predicts or locally applies a
/// move; it just sends it and waits for the next `gameState` broadcast.
class GameClient extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  ConnectionStatus status = ConnectionStatus.disconnected;
  String? connectError;

  String? roomCode;
  String? myPlayerId;
  List<LobbyPlayer> lobbyPlayers = [];

  ClientGameState? gameState;
  String? lastError;

  Future<void> connect(Uri uri) async {
    status = ConnectionStatus.connecting;
    connectError = null;
    notifyListeners();

    try {
      final channel = WebSocketChannel.connect(uri);
      await channel.ready;
      _channel = channel;
      status = ConnectionStatus.connected;
      _subscription = channel.stream.listen(_onMessage, onDone: _onDone, onError: _onSocketError);
    } catch (e) {
      status = ConnectionStatus.failed;
      connectError = e.toString();
    }
    notifyListeners();
  }

  void createRoom(String playerName) => _send({'type': 'createRoom', 'playerName': playerName});

  void joinRoom(String roomCode, String playerName) =>
      _send({'type': 'joinRoom', 'roomCode': roomCode, 'playerName': playerName});

  void startGame() => _send({'type': 'startGame'});

  void move(String action, [Map<String, dynamic> params = const {}]) =>
      _send({'type': 'move', 'action': action, ...params});

  void clearError() {
    lastError = null;
    notifyListeners();
  }

  void _send(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  void _onMessage(dynamic raw) {
    final msg = jsonDecode(raw as String) as Map<String, dynamic>;
    switch (msg['type']) {
      case 'roomCreated':
      case 'joined':
        roomCode = msg['roomCode'] as String;
        myPlayerId = msg['playerId'] as String;
      case 'lobby':
        lobbyPlayers = (msg['players'] as List).map((p) => LobbyPlayer.fromJson(p as Map<String, dynamic>)).toList();
      case 'gameState':
        gameState = ClientGameState.fromJson(msg);
      case 'error':
        lastError = msg['message'] as String;
    }
    notifyListeners();
  }

  void _onDone() {
    status = ConnectionStatus.disconnected;
    notifyListeners();
  }

  void _onSocketError(Object error) {
    lastError = 'Connection error: $error';
    status = ConnectionStatus.disconnected;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
