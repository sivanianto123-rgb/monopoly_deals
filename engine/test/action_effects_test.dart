import 'package:monopoly_deal_engine/monopoly_deal_engine.dart';
import 'package:test/test.dart';

/// Builds a 2-player game with empty hands/banks/properties so each test
/// can inject exactly the cards it needs, and starts player 0's turn.
(GameState, TurnEngine) freshGame() {
  final state = startNewGame(playerNames: ['Alice', 'Bob'], allCards: buildFullDeck(), random: Random(1));
  for (final p in state.players) {
    p.hand.clear();
  }
  final engine = TurnEngine(state, random: Random(1));
  engine.startTurn();
  state.currentPlayer.hand.clear(); // drop the 2 cards drawn by startTurn too
  return (state, engine);
}

PropertyCard brownCard(String id) =>
    PropertyCard(id: id, bankValue: 1, name: 'Brown $id', color: PropertyColor.brown);

PropertyCard greenCard(String id) =>
    PropertyCard(id: id, bankValue: 4, name: 'Green $id', color: PropertyColor.green);

void completeBrownSet(Player player) {
  player.properties[PropertyColor.brown] = PropertySet(PropertyColor.brown)
    ..cards.addAll([brownCard('b1'), brownCard('b2')]);
}

void main() {
  group('Instant actions', () {
    test('Pass Go draws 2 extra cards and uses 1 action slot', () {
      final (state, engine) = freshGame();
      final card = ActionCard(id: 'pg1', bankValue: 1, type: ActionType.passGo);
      state.currentPlayer.hand.add(card);

      engine.playPassGo(card);

      expect(state.currentPlayer.hand.length, 2);
      expect(state.actionsPlayedThisTurn, 1);
      expect(state.discardPile, contains(card));
    });

    test('House requires a complete, non-railroad/utility set', () {
      final (state, engine) = freshGame();
      final player = state.currentPlayer;
      final house = ActionCard(id: 'h1', bankValue: 3, type: ActionType.house);
      player.hand.add(house);

      expect(() => engine.playHouse(house, PropertyColor.brown), throwsA(isA<IllegalMoveException>()));

      completeBrownSet(player);
      engine.playHouse(house, PropertyColor.brown);
      expect(player.properties[PropertyColor.brown]!.hasHouse, isTrue);
      expect(player.properties[PropertyColor.brown]!.rent, 2 + 3); // full-set rent + house bonus
    });

    test('Hotel requires a House already on the set', () {
      final (state, engine) = freshGame();
      final player = state.currentPlayer;
      completeBrownSet(player);
      final hotel = ActionCard(id: 'ho1', bankValue: 4, type: ActionType.hotel);
      player.hand.add(hotel);

      expect(() => engine.playHotel(hotel, PropertyColor.brown), throwsA(isA<IllegalMoveException>()));

      player.properties[PropertyColor.brown]!.hasHouse = true;
      engine.playHotel(hotel, PropertyColor.brown);
      expect(player.properties[PropertyColor.brown]!.hasHotel, isTrue);
      expect(player.properties[PropertyColor.brown]!.rent, 2 + 3 + 4);
    });

    test('House/Hotel cannot go on railroad or utility sets', () {
      final (state, engine) = freshGame();
      final player = state.currentPlayer;
      player.properties[PropertyColor.utility] = PropertySet(PropertyColor.utility)
        ..cards.addAll([
          PropertyCard(id: 'u1', bankValue: 2, name: 'Electric Company', color: PropertyColor.utility),
          PropertyCard(id: 'u2', bankValue: 2, name: 'Water Works', color: PropertyColor.utility),
        ]);
      final house = ActionCard(id: 'h1', bankValue: 3, type: ActionType.house);
      player.hand.add(house);

      expect(() => engine.playHouse(house, PropertyColor.utility), throwsA(isA<IllegalMoveException>()));
    });
  });

  group('Debt Collector', () {
    test('forces the target to pay \$5M, cash from the bank', () {
      final (state, engine) = freshGame();
      final alice = state.players[0];
      final bob = state.players[1];
      final card = ActionCard(id: 'dc1', bankValue: 3, type: ActionType.debtCollector);
      alice.hand.add(card);
      bob.bank.addAll([MoneyCard(id: 'm1', bankValue: 5)]);

      engine.playDebtCollector(card, targetPlayerId: bob.id);
      expect(engine.currentPendingAction, isNotNull);

      engine.resolvePendingAction();
      expect(state.pendingPayments, hasLength(1));
      expect(state.pendingPayments.first.amount, 5);

      engine.resolvePayment(bob.id, [bob.bank.first]);
      expect(bob.bank, isEmpty);
      expect(alice.bank.map((c) => c.id), contains('m1'));
      expect(state.pendingPayments, isEmpty);
    });

    test('Just Say No cancels Debt Collector', () {
      final (state, engine) = freshGame();
      final alice = state.players[0];
      final bob = state.players[1];
      final card = ActionCard(id: 'dc1', bankValue: 3, type: ActionType.debtCollector);
      final jsn = ActionCard(id: 'jsn1', bankValue: 4, type: ActionType.justSayNo);
      alice.hand.add(card);
      bob.hand.add(jsn);

      engine.playDebtCollector(card, targetPlayerId: bob.id);
      expect(engine.currentPendingAction!.nextResponderId, bob.id);

      engine.playJustSayNo(bob.id, jsn);
      expect(engine.currentPendingAction!.isCancelled, isTrue);

      engine.resolvePendingAction();
      expect(state.pendingPayments, isEmpty);
      expect(state.pendingActions, isEmpty);
      expect(state.discardPile, containsAll([card, jsn]));
    });

    test('a countered Just Say No lets the action go through again', () {
      final (state, engine) = freshGame();
      final alice = state.players[0];
      final bob = state.players[1];
      final dc = ActionCard(id: 'dc1', bankValue: 3, type: ActionType.debtCollector);
      final bobJsn = ActionCard(id: 'jsn-bob', bankValue: 4, type: ActionType.justSayNo);
      final aliceJsn = ActionCard(id: 'jsn-alice', bankValue: 4, type: ActionType.justSayNo);
      alice.hand.addAll([dc, aliceJsn]);
      bob.hand.add(bobJsn);

      engine.playDebtCollector(dc, targetPlayerId: bob.id);
      engine.playJustSayNo(bob.id, bobJsn);
      expect(engine.currentPendingAction!.isCancelled, isTrue);
      expect(engine.currentPendingAction!.nextResponderId, alice.id);

      engine.playJustSayNo(alice.id, aliceJsn);
      expect(engine.currentPendingAction!.isCancelled, isFalse);

      engine.resolvePendingAction();
      expect(state.pendingPayments, hasLength(1)); // goes through: even number of JSNs
    });
  });

  group("It's My Birthday", () {
    test('every opponent independently owes \$2M', () {
      final state = startNewGame(playerNames: ['Alice', 'Bob', 'Cara'], allCards: buildFullDeck(), random: Random(2));
      for (final p in state.players) {
        p.hand.clear();
      }
      final engine = TurnEngine(state, random: Random(2));
      engine.startTurn();
      final alice = state.players[0];
      alice.hand.clear();
      final card = ActionCard(id: 'bday1', bankValue: 2, type: ActionType.itsMyBirthday);
      alice.hand.add(card);

      engine.playItsMyBirthday(card);
      expect(state.pendingActions, hasLength(2)); // Bob and Cara

      engine.resolvePendingAction();
      engine.resolvePendingAction();
      expect(state.pendingPayments, hasLength(2));
      expect(state.pendingPayments.every((p) => p.amount == 2 && p.payeeId == alice.id), isTrue);
    });
  });

  group('Sly Deal', () {
    test('steals a single property not part of a complete set', () {
      final (state, engine) = freshGame();
      final alice = state.players[0];
      final bob = state.players[1];
      final card = ActionCard(id: 'sd1', bankValue: 3, type: ActionType.slyDeal);
      alice.hand.add(card);
      final stolen = greenCard('g1');
      bob.properties[PropertyColor.green] = PropertySet(PropertyColor.green)..cards.add(stolen);

      engine.playSlyDeal(card, targetPlayerId: bob.id, targetProperty: stolen);
      engine.resolvePendingAction();

      expect(bob.properties[PropertyColor.green]!.cards, isEmpty);
      expect(alice.properties[PropertyColor.green]!.cards, contains(stolen));
    });

    test('cannot steal from a complete set', () {
      final (state, engine) = freshGame();
      final alice = state.players[0];
      final bob = state.players[1];
      completeBrownSet(bob);
      final card = ActionCard(id: 'sd1', bankValue: 3, type: ActionType.slyDeal);
      alice.hand.add(card);

      expect(
        () => engine.playSlyDeal(card, targetPlayerId: bob.id, targetProperty: bob.properties[PropertyColor.brown]!.cards.first),
        throwsA(isA<IllegalMoveException>()),
      );
    });
  });

  group('Forced Deal', () {
    test('swaps one property each way', () {
      final (state, engine) = freshGame();
      final alice = state.players[0];
      final bob = state.players[1];
      final card = ActionCard(id: 'fd1', bankValue: 3, type: ActionType.forcedDeal);
      alice.hand.add(card);
      final mine = greenCard('mine');
      final theirs = greenCard('theirs');
      alice.properties[PropertyColor.green] = PropertySet(PropertyColor.green)..cards.add(mine);
      bob.properties[PropertyColor.green] = PropertySet(PropertyColor.green)..cards.add(theirs);

      engine.playForcedDeal(card, targetPlayerId: bob.id, myProperty: mine, theirProperty: theirs);
      engine.resolvePendingAction();

      expect(alice.properties[PropertyColor.green]!.cards, contains(theirs));
      expect(alice.properties[PropertyColor.green]!.cards, isNot(contains(mine)));
      expect(bob.properties[PropertyColor.green]!.cards, contains(mine));
      expect(bob.properties[PropertyColor.green]!.cards, isNot(contains(theirs)));
    });
  });

  group('Deal Breaker', () {
    test('steals a complete set including its House/Hotel', () {
      final (state, engine) = freshGame();
      final alice = state.players[0];
      final bob = state.players[1];
      completeBrownSet(bob);
      bob.properties[PropertyColor.brown]!.hasHouse = true;
      final card = ActionCard(id: 'db1', bankValue: 5, type: ActionType.dealBreaker);
      alice.hand.add(card);

      engine.playDealBreaker(card, targetPlayerId: bob.id, targetColor: PropertyColor.brown);
      engine.resolvePendingAction();

      expect(bob.properties.containsKey(PropertyColor.brown), isFalse);
      expect(alice.properties[PropertyColor.brown]!.isComplete, isTrue);
      expect(alice.properties[PropertyColor.brown]!.hasHouse, isTrue);
      expect(alice.hasWon, isFalse); // just 1 set, not 3
    });

    test('cannot steal an incomplete set', () {
      final (state, engine) = freshGame();
      final alice = state.players[0];
      final bob = state.players[1];
      bob.properties[PropertyColor.brown] = PropertySet(PropertyColor.brown)..cards.add(brownCard('b1'));
      final card = ActionCard(id: 'db1', bankValue: 5, type: ActionType.dealBreaker);
      alice.hand.add(card);

      expect(
        () => engine.playDealBreaker(card, targetPlayerId: bob.id, targetColor: PropertyColor.brown),
        throwsA(isA<IllegalMoveException>()),
      );
    });
  });

  group('Rent', () {
    test('charges every opponent the set\'s current rent value', () {
      final state = startNewGame(playerNames: ['Alice', 'Bob', 'Cara'], allCards: buildFullDeck(), random: Random(3));
      for (final p in state.players) {
        p.hand.clear();
      }
      final engine = TurnEngine(state, random: Random(3));
      engine.startTurn();
      final alice = state.players[0];
      alice.hand.clear();
      completeBrownSet(alice); // full-set rent = $2M
      final rent = RentCard(id: 'r1', bankValue: 1, colors: {PropertyColor.brown, PropertyColor.lightBlue});
      alice.hand.add(rent);

      engine.playRent(rent, colorCharged: PropertyColor.brown);

      expect(state.pendingActions, hasLength(2));
      for (final pa in state.pendingActions) {
        expect(pa.amountOwed, 2);
      }
    });

    test('Double The Rent doubles the amount and uses 2 action slots', () {
      final (state, engine) = freshGame();
      final alice = state.players[0];
      completeBrownSet(alice);
      final rent = RentCard(id: 'r1', bankValue: 1, colors: {PropertyColor.brown, PropertyColor.lightBlue});
      final dtr = ActionCard(id: 'dtr1', bankValue: 1, type: ActionType.doubleTheRent);
      alice.hand.addAll([rent, dtr]);

      engine.playRent(rent, colorCharged: PropertyColor.brown, doubleTheRentCard: dtr);

      expect(state.actionsPlayedThisTurn, 2);
      expect(state.pendingActions.single.amountOwed, 4); // 2M x2
    });

    test('rejects charging for a color you do not own', () {
      final (state, engine) = freshGame();
      final alice = state.players[0];
      final rent = RentCard(id: 'r1', bankValue: 1, colors: {PropertyColor.brown, PropertyColor.lightBlue});
      alice.hand.add(rent);

      expect(() => engine.playRent(rent, colorCharged: PropertyColor.brown), throwsA(isA<IllegalMoveException>()));
    });
  });

  group('resolvePayment', () {
    test('accepts bank cards covering the full amount', () {
      final (state, engine) = freshGame();
      final alice = state.players[0];
      final bob = state.players[1];
      bob.bank.addAll([MoneyCard(id: 'm10', bankValue: 10)]);
      final dc = ActionCard(id: 'dc1', bankValue: 3, type: ActionType.debtCollector);
      alice.hand.add(dc);
      engine.playDebtCollector(dc, targetPlayerId: bob.id);
      engine.resolvePendingAction();

      engine.resolvePayment(bob.id, [bob.bank.first]);
      expect(alice.bank.map((c) => c.id), contains('m10'));
    });

    test('rejects an offer below the amount owed unless it is everything the payer has', () {
      final (state, engine) = freshGame();
      final alice = state.players[0];
      final bob = state.players[1];
      bob.bank.addAll([MoneyCard(id: 'm1', bankValue: 1), MoneyCard(id: 'm2', bankValue: 1)]);
      final dc = ActionCard(id: 'dc1', bankValue: 3, type: ActionType.debtCollector);
      alice.hand.add(dc);
      engine.playDebtCollector(dc, targetPlayerId: bob.id);
      engine.resolvePendingAction();

      // Owes $5M, offers only $1M while holding $2M total -> rejected (not everything).
      expect(() => engine.resolvePayment(bob.id, [bob.bank.first]), throwsA(isA<IllegalMoveException>()));

      // Offering everything they have ($2M, still short of $5M) is accepted.
      engine.resolvePayment(bob.id, [...bob.bank]);
      expect(bob.bank, isEmpty);
      expect(alice.bank, hasLength(2));
    });

    test('property cards given as payment move into the payee\'s matching set', () {
      final (state, engine) = freshGame();
      final alice = state.players[0];
      final bob = state.players[1];
      final prop = greenCard('g1');
      bob.properties[PropertyColor.green] = PropertySet(PropertyColor.green)..cards.add(prop); // worth $4M
      final dc = ActionCard(id: 'dc1', bankValue: 3, type: ActionType.debtCollector);
      alice.hand.add(dc);
      engine.playDebtCollector(dc, targetPlayerId: bob.id);
      engine.resolvePendingAction();

      engine.resolvePayment(bob.id, [prop]);

      expect(bob.properties[PropertyColor.green]!.cards, isEmpty);
      expect(alice.properties[PropertyColor.green]!.cards, contains(prop));
    });
  });

  group('endTurn guards', () {
    test('cannot end turn with an unresolved pending action or payment', () {
      final (state, engine) = freshGame();
      final alice = state.players[0];
      final bob = state.players[1];
      final dc = ActionCard(id: 'dc1', bankValue: 3, type: ActionType.debtCollector);
      alice.hand.add(dc);

      engine.playDebtCollector(dc, targetPlayerId: bob.id);
      expect(() => engine.endTurn(), throwsA(isA<IllegalMoveException>()));

      engine.resolvePendingAction();
      expect(() => engine.endTurn(), throwsA(isA<IllegalMoveException>())); // now a pending payment

      bob.bank.add(MoneyCard(id: 'm5', bankValue: 5));
      engine.resolvePayment(bob.id, [bob.bank.first]);
      engine.endTurn(); // no exception now
      expect(state.currentPlayerIndex, 1);
    });
  });
}
