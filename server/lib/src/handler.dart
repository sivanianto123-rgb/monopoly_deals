import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';

import 'client_session.dart';
import 'room_manager.dart';

/// Builds the shelf [Handler] that upgrades every request to a WebSocket
/// and wires it to a [ClientSession] backed by [roomManager]. Factored out
/// of bin/server.dart so integration tests can serve the exact same
/// handler in-process instead of spawning a subprocess.
Handler buildHandler(RoomManager roomManager) {
  return webSocketHandler((webSocket, protocol) {
    final session = ClientSession(
      roomManager: roomManager,
      send: (msg) => webSocket.sink.add(jsonEncode(msg)),
    );
    webSocket.stream.listen(
      (raw) {
        try {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          session.handleMessage(msg);
        } catch (e) {
          webSocket.sink.add(jsonEncode({'type': 'error', 'message': 'Malformed message: $e'}));
        }
      },
      onDone: session.handleDisconnect,
    );
  });
}
