/// JSON (de)serialization for the engine's types, so a server can send
/// game state over the wire and a client can send moves back. Deliberately
/// lives in the engine (not the server) since the Flutter client will need
/// the same card (de)serialization to read what the server sends it.
library;

import 'cards.dart';
import 'game_state.dart';
import 'pending_action.dart';

PropertyColor _colorFromName(String name) => PropertyColor.values.byName(name);

Map<String, dynamic> cardToJson(DealCard card) {
  return switch (card) {
    MoneyCard c => {'kind': 'money', 'id': c.id, 'bankValue': c.bankValue},
    PropertyCard c => {
        'kind': 'property',
        'id': c.id,
        'bankValue': c.bankValue,
        'name': c.name,
        'color': c.color.name,
      },
    PropertyWildCard c => {
        'kind': 'propertyWild',
        'id': c.id,
        'bankValue': c.bankValue,
        'eligibleColors': c.eligibleColors.map((e) => e.name).toList(),
      },
    RentCard c => {
        'kind': 'rent',
        'id': c.id,
        'bankValue': c.bankValue,
        'colors': c.colors.map((e) => e.name).toList(),
      },
    ActionCard c => {
        'kind': 'action',
        'id': c.id,
        'bankValue': c.bankValue,
        'actionType': c.type.name,
      },
  };
}

DealCard cardFromJson(Map<String, dynamic> json) {
  final id = json['id'] as String;
  final bankValue = json['bankValue'] as int;
  switch (json['kind']) {
    case 'money':
      return MoneyCard(id: id, bankValue: bankValue);
    case 'property':
      return PropertyCard(
        id: id,
        bankValue: bankValue,
        name: json['name'] as String,
        color: _colorFromName(json['color'] as String),
      );
    case 'propertyWild':
      return PropertyWildCard(
        id: id,
        bankValue: bankValue,
        eligibleColors: (json['eligibleColors'] as List).map((e) => _colorFromName(e as String)).toSet(),
      );
    case 'rent':
      return RentCard(
        id: id,
        bankValue: bankValue,
        colors: (json['colors'] as List).map((e) => _colorFromName(e as String)).toSet(),
      );
    case 'action':
      return ActionCard(
        id: id,
        bankValue: bankValue,
        type: ActionType.values.byName(json['actionType'] as String),
      );
    default:
      throw FormatException('Unknown card kind: ${json['kind']}');
  }
}

Map<String, dynamic> propertySetToJson(PropertySet set) => {
      'color': set.color.name,
      'cards': set.cards.map(cardToJson).toList(),
      'hasHouse': set.hasHouse,
      'hasHotel': set.hasHotel,
      'isComplete': set.isComplete,
      'rent': set.rent,
    };

/// [includeHand] controls whether the full hand contents are serialized —
/// callers should only pass true for the player this JSON is being sent
/// to; everyone else should only see [Player.hand]'s length.
Map<String, dynamic> playerToJson(Player player, {required bool includeHand}) => {
      'id': player.id,
      'name': player.name,
      'handCount': player.hand.length,
      if (includeHand) 'hand': player.hand.map(cardToJson).toList(),
      'bank': player.bank.map(cardToJson).toList(),
      'bankTotal': player.bankTotal,
      'properties': player.properties.values.map(propertySetToJson).toList(),
      'hasWon': player.hasWon,
    };

Map<String, dynamic> pendingActionToJson(PendingAction pa) => {
      'kind': pa.kind.name,
      'sourceCard': cardToJson(pa.sourceCard),
      'sourcePlayerId': pa.sourcePlayerId,
      'targetPlayerId': pa.targetPlayerId,
      if (pa.takenProperty != null) 'takenProperty': cardToJson(pa.takenProperty!),
      if (pa.givenProperty != null) 'givenProperty': cardToJson(pa.givenProperty!),
      if (pa.takenSetColor != null) 'takenSetColor': pa.takenSetColor!.name,
      if (pa.amountOwed != null) 'amountOwed': pa.amountOwed,
      'justSayNoChain': pa.justSayNoChain.map(cardToJson).toList(),
      'isCancelled': pa.isCancelled,
      'nextResponderId': pa.nextResponderId,
    };

Map<String, dynamic> pendingPaymentToJson(PendingPayment p) => {
      'payerId': p.payerId,
      'payeeId': p.payeeId,
      'amount': p.amount,
    };

/// A snapshot of [state] as [viewerId] should see it: their own hand in
/// full, every other player's hand as a count only. Everything else
/// (properties, banks, pending actions/payments) is public knowledge in
/// Monopoly Deal, same as the physical cards on the table.
Map<String, dynamic> gameStateToJson(GameState state, {required String viewerId}) => {
      'players': state.players.map((p) => playerToJson(p, includeHand: p.id == viewerId)).toList(),
      'currentPlayerId': state.currentPlayer.id,
      'phase': state.phase.name,
      'drawPileCount': state.drawPile.length,
      'discardTop': state.discardPile.isEmpty ? null : cardToJson(state.discardPile.last),
      'discardCount': state.discardPile.length,
      'actionsPlayedThisTurn': state.actionsPlayedThisTurn,
      'pendingActions': state.pendingActions.map(pendingActionToJson).toList(),
      'pendingPayments': state.pendingPayments.map(pendingPaymentToJson).toList(),
      'winnerId': state.winner?.id,
    };
