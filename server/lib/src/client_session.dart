import 'room.dart';
import 'room_manager.dart';

/// Per-connection protocol handler: tracks which room/player this
/// connection belongs to (none, until it sends createRoom/joinRoom) and
/// routes incoming JSON messages. Transport-agnostic — [send] is just "how
/// to deliver a JSON message to this one client," so this class doesn't
/// know or care whether it's wired to a real WebSocket or a test double.
class ClientSession {
  final RoomManager roomManager;
  final Sender send;
  Room? _room;
  String? _playerId;

  ClientSession({required this.roomManager, required this.send});

  void handleMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    switch (type) {
      case 'createRoom':
        _createRoom(msg);
      case 'joinRoom':
        _joinRoom(msg);
      case 'startGame':
        _startGame();
      case 'move':
        _handleMove(msg);
      default:
        send({'type': 'error', 'message': 'Unknown message type: $type'});
    }
  }

  void handleDisconnect() {
    _room?.removeConnection(_playerId);
  }

  void _createRoom(Map<String, dynamic> msg) {
    final name = (msg['playerName'] as String?)?.trim();
    if (name == null || name.isEmpty) {
      send({'type': 'error', 'message': 'playerName is required.'});
      return;
    }
    final room = roomManager.createRoom();
    _room = room;
    _playerId = room.addPlayer(name, send);
    send({'type': 'roomCreated', 'roomCode': room.code, 'playerId': _playerId});
    room.broadcastLobby();
  }

  void _joinRoom(Map<String, dynamic> msg) {
    final code = (msg['roomCode'] as String?)?.trim().toUpperCase();
    final name = (msg['playerName'] as String?)?.trim();
    if (code == null || code.isEmpty || name == null || name.isEmpty) {
      send({'type': 'error', 'message': 'roomCode and playerName are required.'});
      return;
    }
    final room = roomManager.getRoom(code);
    if (room == null) {
      send({'type': 'error', 'message': 'No room with code $code.'});
      return;
    }
    if (room.isStarted) {
      send({'type': 'error', 'message': 'Room $code has already started.'});
      return;
    }
    if (room.connections.length >= Room.maxPlayers) {
      send({'type': 'error', 'message': 'Room $code is full.'});
      return;
    }
    _room = room;
    _playerId = room.addPlayer(name, send);
    send({'type': 'joined', 'roomCode': room.code, 'playerId': _playerId});
    room.broadcastLobby();
  }

  void _startGame() {
    final room = _room;
    if (room == null) {
      send({'type': 'error', 'message': 'Not in a room.'});
      return;
    }
    room.start();
  }

  void _handleMove(Map<String, dynamic> msg) {
    final room = _room;
    final playerId = _playerId;
    if (room == null || playerId == null) {
      send({'type': 'error', 'message': 'Not in a room.'});
      return;
    }
    room.handleMove(playerId, msg);
  }
}
