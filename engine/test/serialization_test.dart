import 'dart:convert';

import 'package:monopoly_deal_engine/monopoly_deal_engine.dart';
import 'package:test/test.dart';

void main() {
  group('card round-trip', () {
    test('every card kind in a full deck survives toJson -> fromJson -> toJson unchanged', () {
      for (final card in buildFullDeck()) {
        final json = cardToJson(card);
        // Must be JSON-encodable (no stray Dart objects).
        final reencoded = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
        final roundTripped = cardFromJson(reencoded);
        expect(cardToJson(roundTripped), json, reason: 'mismatch for ${card.id}');
      }
    });
  });

  group('gameStateToJson', () {
    test('hides other players\' hand contents but not the viewer\'s own', () {
      final state = startNewGame(playerNames: ['Alice', 'Bob'], allCards: buildFullDeck(), random: Random(5));
      final alice = state.players[0];
      final bob = state.players[1];

      final aliceView = gameStateToJson(state, viewerId: alice.id);
      final players = aliceView['players'] as List;
      final aliceJson = players.firstWhere((p) => p['id'] == alice.id) as Map;
      final bobJson = players.firstWhere((p) => p['id'] == bob.id) as Map;

      expect(aliceJson.containsKey('hand'), isTrue);
      expect((aliceJson['hand'] as List).length, alice.hand.length);
      expect(bobJson.containsKey('hand'), isFalse);
      expect(bobJson['handCount'], bob.hand.length);
    });

    test('is fully JSON-encodable', () {
      final state = startNewGame(playerNames: ['Alice', 'Bob'], allCards: buildFullDeck(), random: Random(6));
      final json = gameStateToJson(state, viewerId: state.players[0].id);
      expect(() => jsonEncode(json), returnsNormally);
    });
  });
}
