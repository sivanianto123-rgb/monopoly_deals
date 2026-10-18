/// Client-side view models for the `gameState` JSON the server broadcasts
/// (see `gameStateToJson` in the engine, and server/README.md's protocol
/// table). These mirror that JSON shape directly rather than trying to
/// reconstruct the engine's own `GameState` — the client only ever sees a
/// partial, per-viewer view (other players' hands are just a count), so a
/// real `GameState` couldn't be rebuilt from it anyway. Individual cards
/// reuse the engine's own [DealCard] subtypes via [cardFromJson], since
/// those are always sent in full wherever they appear.
library;

import 'package:monopoly_deal_engine/monopoly_deal_engine.dart';

class ClientPropertySet {
  final PropertyColor color;
  final List<DealCard> cards;
  final bool hasHouse;
  final bool hasHotel;
  final bool isComplete;
  final int rent;

  ClientPropertySet({
    required this.color,
    required this.cards,
    required this.hasHouse,
    required this.hasHotel,
    required this.isComplete,
    required this.rent,
  });

  factory ClientPropertySet.fromJson(Map<String, dynamic> json) => ClientPropertySet(
        color: PropertyColor.values.byName(json['color'] as String),
        cards: (json['cards'] as List).map((c) => cardFromJson(c as Map<String, dynamic>)).toList(),
        hasHouse: json['hasHouse'] as bool,
        hasHotel: json['hasHotel'] as bool,
        isComplete: json['isComplete'] as bool,
        rent: json['rent'] as int,
      );
}

class ClientPlayerView {
  final String id;
  final String name;
  final int handCount;

  /// Only non-null for the viewer themself — other players' hand contents
  /// are never sent over the wire.
  final List<DealCard>? hand;

  final List<DealCard> bank;
  final int bankTotal;
  final List<ClientPropertySet> properties;
  final bool hasWon;

  ClientPlayerView({
    required this.id,
    required this.name,
    required this.handCount,
    required this.hand,
    required this.bank,
    required this.bankTotal,
    required this.properties,
    required this.hasWon,
  });

  factory ClientPlayerView.fromJson(Map<String, dynamic> json) => ClientPlayerView(
        id: json['id'] as String,
        name: json['name'] as String,
        handCount: json['handCount'] as int,
        hand: json.containsKey('hand')
            ? (json['hand'] as List).map((c) => cardFromJson(c as Map<String, dynamic>)).toList()
            : null,
        bank: (json['bank'] as List).map((c) => cardFromJson(c as Map<String, dynamic>)).toList(),
        bankTotal: json['bankTotal'] as int,
        properties: (json['properties'] as List)
            .map((s) => ClientPropertySet.fromJson(s as Map<String, dynamic>))
            .toList(),
        hasWon: json['hasWon'] as bool,
      );

  ClientPropertySet? propertySet(PropertyColor color) {
    for (final s in properties) {
      if (s.color == color) return s;
    }
    return null;
  }
}

class ClientPendingAction {
  final PendingActionKind kind;
  final DealCard sourceCard;
  final String sourcePlayerId;
  final String targetPlayerId;
  final DealCard? takenProperty;
  final DealCard? givenProperty;
  final PropertyColor? takenSetColor;
  final int? amountOwed;
  final List<DealCard> justSayNoChain;
  final bool isCancelled;
  final String nextResponderId;

  ClientPendingAction({
    required this.kind,
    required this.sourceCard,
    required this.sourcePlayerId,
    required this.targetPlayerId,
    required this.takenProperty,
    required this.givenProperty,
    required this.takenSetColor,
    required this.amountOwed,
    required this.justSayNoChain,
    required this.isCancelled,
    required this.nextResponderId,
  });

  factory ClientPendingAction.fromJson(Map<String, dynamic> json) => ClientPendingAction(
        kind: PendingActionKind.values.byName(json['kind'] as String),
        sourceCard: cardFromJson(json['sourceCard'] as Map<String, dynamic>),
        sourcePlayerId: json['sourcePlayerId'] as String,
        targetPlayerId: json['targetPlayerId'] as String,
        takenProperty:
            json['takenProperty'] == null ? null : cardFromJson(json['takenProperty'] as Map<String, dynamic>),
        givenProperty:
            json['givenProperty'] == null ? null : cardFromJson(json['givenProperty'] as Map<String, dynamic>),
        takenSetColor:
            json['takenSetColor'] == null ? null : PropertyColor.values.byName(json['takenSetColor'] as String),
        amountOwed: json['amountOwed'] as int?,
        justSayNoChain:
            (json['justSayNoChain'] as List).map((c) => cardFromJson(c as Map<String, dynamic>)).toList(),
        isCancelled: json['isCancelled'] as bool,
        nextResponderId: json['nextResponderId'] as String,
      );
}

class ClientPendingPayment {
  final String payerId;
  final String payeeId;
  final int amount;

  ClientPendingPayment({required this.payerId, required this.payeeId, required this.amount});

  factory ClientPendingPayment.fromJson(Map<String, dynamic> json) => ClientPendingPayment(
        payerId: json['payerId'] as String,
        payeeId: json['payeeId'] as String,
        amount: json['amount'] as int,
      );
}

class ClientGameState {
  final List<ClientPlayerView> players;
  final String currentPlayerId;
  final String phase; // "draw" | "play" | "discard" | "over"
  final int drawPileCount;
  final DealCard? discardTop;
  final int discardCount;
  final int actionsPlayedThisTurn;
  final List<ClientPendingAction> pendingActions;
  final List<ClientPendingPayment> pendingPayments;
  final String? winnerId;

  ClientGameState({
    required this.players,
    required this.currentPlayerId,
    required this.phase,
    required this.drawPileCount,
    required this.discardTop,
    required this.discardCount,
    required this.actionsPlayedThisTurn,
    required this.pendingActions,
    required this.pendingPayments,
    required this.winnerId,
  });

  factory ClientGameState.fromJson(Map<String, dynamic> json) => ClientGameState(
        players: (json['players'] as List).map((p) => ClientPlayerView.fromJson(p as Map<String, dynamic>)).toList(),
        currentPlayerId: json['currentPlayerId'] as String,
        phase: json['phase'] as String,
        drawPileCount: json['drawPileCount'] as int,
        discardTop: json['discardTop'] == null ? null : cardFromJson(json['discardTop'] as Map<String, dynamic>),
        discardCount: json['discardCount'] as int,
        actionsPlayedThisTurn: json['actionsPlayedThisTurn'] as int,
        pendingActions:
            (json['pendingActions'] as List).map((p) => ClientPendingAction.fromJson(p as Map<String, dynamic>)).toList(),
        pendingPayments: (json['pendingPayments'] as List)
            .map((p) => ClientPendingPayment.fromJson(p as Map<String, dynamic>))
            .toList(),
        winnerId: json['winnerId'] as String?,
      );

  ClientPlayerView playerById(String id) => players.firstWhere((p) => p.id == id);
}

class LobbyPlayer {
  final String id;
  final String name;
  LobbyPlayer({required this.id, required this.name});

  factory LobbyPlayer.fromJson(Map<String, dynamic> json) =>
      LobbyPlayer(id: json['id'] as String, name: json['name'] as String);
}
