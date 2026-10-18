import 'package:flutter_test/flutter_test.dart';
import 'package:monopoly_deal_engine/monopoly_deal_engine.dart';
import 'package:monopoly_deal_app/src/models/client_view.dart';

void main() {
  test('ClientGameState.fromJson parses a real server-shaped gameStateToJson payload', () {
    final state = startNewGame(playerNames: ['Alice', 'Bob'], allCards: buildFullDeck(), random: Random(1));
    final alice = state.players[0];
    final bob = state.players[1];

    final json = gameStateToJson(state, viewerId: alice.id);
    final parsed = ClientGameState.fromJson(json);

    expect(parsed.players, hasLength(2));
    expect(parsed.currentPlayerId, state.currentPlayer.id);
    expect(parsed.phase, 'draw');

    final aliceView = parsed.playerById(alice.id);
    expect(aliceView.hand, isNotNull);
    expect(aliceView.hand, hasLength(5));

    final bobView = parsed.playerById(bob.id);
    expect(bobView.hand, isNull);
    expect(bobView.handCount, 5);
  });

  test('ClientPropertySet.fromJson reconstructs cards via the engine deserializer', () {
    final set = PropertySet(PropertyColor.brown)
      ..cards.add(const PropertyCard(id: 'b1', bankValue: 1, name: 'Baltic Avenue', color: PropertyColor.brown))
      ..hasHouse = true;

    final parsed = ClientPropertySet.fromJson(propertySetToJson(set));

    expect(parsed.color, PropertyColor.brown);
    expect(parsed.cards, hasLength(1));
    expect((parsed.cards.single as PropertyCard).name, 'Baltic Avenue');
    expect(parsed.hasHouse, isTrue);
  });
}
