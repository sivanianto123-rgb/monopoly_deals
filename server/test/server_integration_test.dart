import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:monopoly_deal_engine/monopoly_deal_engine.dart';
import 'package:monopoly_deal_server/monopoly_deal_server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

/// Thin wrapper around a real WebSocket connection to the test server:
/// buffers every decoded message (via [StreamQueue], so nothing is lost if
/// several arrive before a test gets around to awaiting them) and lets a
/// test wait for the next message of a given `type`, skipping unrelated
/// ones (e.g. a 'lobby' update arriving while waiting for 'gameState').
class TestClient {
  final IOWebSocketChannel channel;
  late final StreamQueue<Map<String, dynamic>> _queue;

  TestClient(this.channel) {
    _queue = StreamQueue(channel.stream.map((raw) => jsonDecode(raw as String) as Map<String, dynamic>));
  }

  void send(Map<String, dynamic> msg) => channel.sink.add(jsonEncode(msg));

  Future<Map<String, dynamic>> next(String type) async {
    while (true) {
      final msg = await _queue.next.timeout(const Duration(seconds: 5));
      if (msg['type'] == type) return msg;
    }
  }

  Future<void> close() async {
    await _queue.cancel(immediate: true);
    await channel.sink.close();
  }
}

void main() {
  late HttpServer httpServer;
  late RoomManager roomManager;
  late Uri wsUri;

  setUp(() async {
    roomManager = RoomManager();
    httpServer = await shelf_io.serve(buildHandler(roomManager), InternetAddress.loopbackIPv4, 0);
    wsUri = Uri.parse('ws://127.0.0.1:${httpServer.port}');
  });

  tearDown(() async {
    await httpServer.close(force: true);
  });

  TestClient connect() => TestClient(IOWebSocketChannel.connect(wsUri));

  test('create room, join, start game, play a card, end turn rotates to next player', () async {
    final alice = connect();
    final bob = connect();

    alice.send({'type': 'createRoom', 'playerName': 'Alice'});
    final created = await alice.next('roomCreated');
    final roomCode = created['roomCode'] as String;
    final aliceId = created['playerId'] as String;
    await alice.next('lobby');

    bob.send({'type': 'joinRoom', 'roomCode': roomCode, 'playerName': 'Bob'});
    final joined = await bob.next('joined');
    final bobId = joined['playerId'] as String;
    await bob.next('lobby');
    await alice.next('lobby'); // Alice is told Bob joined too

    alice.send({'type': 'startGame'});
    final aliceState1 = await alice.next('gameState');
    await bob.next('gameState');

    expect(aliceState1['phase'], 'draw');
    final currentId = aliceState1['currentPlayerId'] as String;
    final currentClient = currentId == aliceId ? alice : bob;

    // Privacy: each client sees its own hand in full, the other's as a count.
    final aliceSelf = (aliceState1['players'] as List).firstWhere((p) => p['id'] == aliceId) as Map;
    final aliceOfBob = (aliceState1['players'] as List).firstWhere((p) => p['id'] == bobId) as Map;
    expect(aliceSelf['hand'], hasLength(5));
    expect(aliceOfBob.containsKey('hand'), isFalse);
    expect(aliceOfBob['handCount'], 5);

    currentClient.send({'type': 'move', 'action': 'startTurn'});
    final afterDraw = await currentClient.next('gameState');
    expect(afterDraw['phase'], 'play');

    final selfJson = (afterDraw['players'] as List).firstWhere((p) => p['id'] == currentId) as Map;
    final hand = (selfJson['hand'] as List).cast<Map>();
    expect(hand.length, 7); // 5 dealt + 2 drawn

    // Play whatever's playable so this doesn't depend on the random deal:
    // a money card straight to the bank, or a property card to its set.
    final moneyCard = hand.where((c) => c['kind'] == 'money').cast<Map?>().firstWhere((_) => true, orElse: () => null);
    final propertyCard = hand.where((c) => c['kind'] == 'property').cast<Map?>().firstWhere((_) => true, orElse: () => null);

    if (moneyCard != null) {
      currentClient.send({'type': 'move', 'action': 'playToBank', 'cardId': moneyCard['id']});
      final afterPlay = await currentClient.next('gameState');
      final selfAfter = (afterPlay['players'] as List).firstWhere((p) => p['id'] == currentId) as Map;
      expect((selfAfter['bank'] as List).any((c) => c['id'] == moneyCard['id']), isTrue);
    } else if (propertyCard != null) {
      currentClient.send({'type': 'move', 'action': 'playToProperty', 'cardId': propertyCard['id']});
      final afterPlay = await currentClient.next('gameState');
      final selfAfter = (afterPlay['players'] as List).firstWhere((p) => p['id'] == currentId) as Map;
      final sets = (selfAfter['properties'] as List).cast<Map>();
      expect(sets.any((s) => (s['cards'] as List).any((c) => c['id'] == propertyCard['id'])), isTrue);
    }

    currentClient.send({'type': 'move', 'action': 'endTurn'});
    final afterEnd = await currentClient.next('gameState');
    expect(afterEnd['currentPlayerId'], isNot(currentId));

    await alice.close();
    await bob.close();
  });

  test('an illegal move is rejected with an error sent only to the player who sent it', () async {
    final alice = connect();
    final bob = connect();

    alice.send({'type': 'createRoom', 'playerName': 'Alice'});
    final created = await alice.next('roomCreated');
    final aliceId = created['playerId'] as String;
    await alice.next('lobby');

    bob.send({'type': 'joinRoom', 'roomCode': created['roomCode'], 'playerName': 'Bob'});
    await bob.next('joined');
    await bob.next('lobby');
    final aliceLobby2 = await alice.next('lobby');
    expect((aliceLobby2['players'] as List).length, 2);

    alice.send({'type': 'startGame'});
    final state1 = await alice.next('gameState');
    await bob.next('gameState');
    final currentId = state1['currentPlayerId'] as String;
    final notCurrentClient = currentId == aliceId ? bob : alice;

    // The player whose turn it ISN'T tries to start the turn -> rejected.
    notCurrentClient.send({'type': 'move', 'action': 'startTurn'});
    final error = await notCurrentClient.next('error');
    expect(error['message'], contains('not your turn'));

    await alice.close();
    await bob.close();
  });

  test('a Rent card can be answered with Just Say No, cancelling the debt', () async {
    final alice = connect();
    final bob = connect();

    alice.send({'type': 'createRoom', 'playerName': 'Alice'});
    final created = await alice.next('roomCreated');
    final roomCode = created['roomCode'] as String;
    final aliceId = created['playerId'] as String;
    await alice.next('lobby');

    bob.send({'type': 'joinRoom', 'roomCode': roomCode, 'playerName': 'Bob'});
    final joined = await bob.next('joined');
    final bobId = joined['playerId'] as String;
    await bob.next('lobby');
    await alice.next('lobby');

    alice.send({'type': 'startGame'});
    await alice.next('gameState');
    await bob.next('gameState');

    // White-box setup over the real in-process Room: the random deal won't
    // reliably hand out a Rent card plus a complete color set plus a Just
    // Say No in the opponent's hand, so this scenario is engineered
    // directly on server state. Everything from here on is still driven
    // through the real WebSocket protocol, exercising the same dispatch
    // path real clients use.
    final room = roomManager.getRoom(roomCode)!;
    final state = room.state!;
    final alicePlayer = state.players.firstWhere((p) => p.id == aliceId);
    final bobPlayer = state.players.firstWhere((p) => p.id == bobId);
    state.currentPlayerIndex = state.players.indexOf(alicePlayer);
    state.phase = TurnPhase.play;
    state.actionsPlayedThisTurn = 0;

    alicePlayer.hand.clear();
    final rent = RentCard(id: 'test-rent', bankValue: 1, colors: {PropertyColor.brown, PropertyColor.lightBlue});
    alicePlayer.hand.add(rent);
    alicePlayer.properties[PropertyColor.brown] = PropertySet(PropertyColor.brown)
      ..cards.addAll([
        PropertyCard(id: 'test-b1', bankValue: 1, name: 'Baltic Avenue', color: PropertyColor.brown),
        PropertyCard(id: 'test-b2', bankValue: 1, name: 'Mediterranean Avenue', color: PropertyColor.brown),
      ]);

    bobPlayer.hand.clear();
    final jsn = ActionCard(id: 'test-jsn', bankValue: 4, type: ActionType.justSayNo);
    bobPlayer.hand.add(jsn);

    alice.send({'type': 'move', 'action': 'playRent', 'cardId': 'test-rent', 'colorCharged': 'brown'});
    final afterRent = await alice.next('gameState');
    await bob.next('gameState');
    final pending = (afterRent['pendingActions'] as List).single as Map;
    expect(pending['targetPlayerId'], bobId);
    expect(pending['amountOwed'], 2); // brown full-set rent
    expect(pending['nextResponderId'], bobId);

    bob.send({'type': 'move', 'action': 'playJustSayNo', 'cardId': 'test-jsn'});
    final afterJsn = await bob.next('gameState');
    await alice.next('gameState');
    final pendingAfterJsn = (afterJsn['pendingActions'] as List).single as Map;
    expect(pendingAfterJsn['isCancelled'], isTrue);
    expect(pendingAfterJsn['nextResponderId'], aliceId);

    alice.send({'type': 'move', 'action': 'resolvePendingAction'});
    final afterResolve = await alice.next('gameState');
    expect(afterResolve['pendingActions'], isEmpty);
    expect(afterResolve['pendingPayments'], isEmpty); // cancelled -> no debt created

    await alice.close();
    await bob.close();
  });
}
