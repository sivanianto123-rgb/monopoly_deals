import 'package:monopoly_deal_engine/monopoly_deal_engine.dart' show Random;

import 'room.dart';

const _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I ambiguity

/// In-memory room registry. No persistence yet — a server restart drops
/// every in-progress game (noted as a TODO for when reconnect/resume
/// support is added).
class RoomManager {
  final Map<String, Room> _rooms = {};
  final Random _random;

  RoomManager({Random? random}) : _random = random ?? Random();

  Room createRoom() {
    String code;
    do {
      code = _generateCode();
    } while (_rooms.containsKey(code));
    // Every room shares this manager's Random source: handy for tests
    // (pass RoomManager(random: Random(seed)) for deterministic deals), and
    // otherwise no different from each room having its own unseeded one.
    final room = Room(code, random: _random);
    _rooms[code] = room;
    return room;
  }

  Room? getRoom(String code) => _rooms[code];

  String _generateCode() => List.generate(5, (_) => _codeChars[_random.nextInt(_codeChars.length)]).join();
}
