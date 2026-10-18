import 'package:monopoly_deal_engine/monopoly_deal_engine.dart';

typedef Sender = void Function(Map<String, dynamic> message);

class RoomPlayerConnection {
  final String playerId;
  final String name;
  final Sender send;

  RoomPlayerConnection({required this.playerId, required this.name, required this.send});
}

/// One game lobby/table. Authoritative: holds the real [GameState] and
/// [TurnEngine] once started, and is the only thing that mutates them —
/// clients only ever send moves and receive broadcasts.
class Room {
  final String code;
  final List<RoomPlayerConnection> connections = [];
  GameState? state;
  TurnEngine? engine;
  final Random _random;
  int _nextPlayerNum = 0;

  static const maxPlayers = 5;

  Room(this.code, {Random? random}) : _random = random ?? Random();

  bool get isStarted => state != null;

  /// Assigns a stable id in join order ("p0", "p1", ...). This matches
  /// exactly how [startNewGame] numbers players from the same
  /// (name-ordered) list, so the ids handed out here before the game
  /// starts are the same ones [GameState] uses afterward — see the
  /// assertion in [start].
  String addPlayer(String name, Sender send) {
    final id = 'p${_nextPlayerNum++}';
    connections.add(RoomPlayerConnection(playerId: id, name: name, send: send));
    return id;
  }

  void removeConnection(String? playerId) {
    if (playerId == null) return;
    connections.removeWhere((c) => c.playerId == playerId);
  }

  RoomPlayerConnection? _connection(String playerId) {
    for (final c in connections) {
      if (c.playerId == playerId) return c;
    }
    return null;
  }

  void broadcastLobby() {
    final players = connections.map((c) => {'id': c.playerId, 'name': c.name}).toList();
    for (final c in connections) {
      c.send({'type': 'lobby', 'roomCode': code, 'players': players});
    }
  }

  void start() {
    if (isStarted) {
      sendError(connections.last.playerId, 'Game already started.');
      return;
    }
    if (connections.length < 2 || connections.length > maxPlayers) {
      for (final c in connections) {
        sendError(c.playerId, 'Need 2-$maxPlayers players to start (have ${connections.length}).');
      }
      return;
    }

    final names = connections.map((c) => c.name).toList();
    final newState = startNewGame(playerNames: names, allCards: buildFullDeck(), random: _random);
    for (var i = 0; i < connections.length; i++) {
      assert(connections[i].playerId == newState.players[i].id,
          'Room/engine player id mismatch — join-order numbering invariant broke.');
    }

    state = newState;
    engine = TurnEngine(newState, random: _random);
    broadcastState();
  }

  DealCard? _findCardById(String id) {
    for (final p in state!.players) {
      for (final c in p.hand) {
        if (c.id == id) return c;
      }
      for (final c in p.bank) {
        if (c.id == id) return c;
      }
      for (final set in p.properties.values) {
        for (final c in set.cards) {
          if (c.id == id) return c;
        }
      }
    }
    return null;
  }

  DealCard _card(Object? id) {
    final card = _findCardById(id as String);
    if (card == null) throw IllegalMoveException('No such card in play: $id');
    return card;
  }

  PropertyColor _color(Object? name) => PropertyColor.values.byName(name as String);

  PropertyColor? _colorOrNull(Object? name) => name == null ? null : _color(name);

  void _requireCurrentPlayer(String playerId) {
    if (state!.currentPlayer.id != playerId) {
      throw IllegalMoveException('It is not your turn.');
    }
  }

  /// Dispatches one client move (the body of a `{"type": "move", ...}`
  /// message) to the matching [TurnEngine] call. Any [IllegalMoveException]
  /// (or malformed-payload error) is sent back to just [playerId]; a
  /// successful move broadcasts the new state to the whole room.
  void handleMove(String playerId, Map<String, dynamic> msg) {
    if (!isStarted) {
      sendError(playerId, 'Game has not started.');
      return;
    }
    final action = msg['action'] as String?;
    try {
      switch (action) {
        case 'startTurn':
          _requireCurrentPlayer(playerId);
          engine!.startTurn();
        case 'playToBank':
          _requireCurrentPlayer(playerId);
          engine!.playToBank(_card(msg['cardId']));
        case 'playToProperty':
          _requireCurrentPlayer(playerId);
          engine!.playToProperty(_card(msg['cardId']), chosenColor: _colorOrNull(msg['chosenColor']));
        case 'moveWildcard':
          _requireCurrentPlayer(playerId);
          engine!.moveWildcard(_card(msg['cardId']) as PropertyWildCard, _color(msg['newColor']));
        case 'playPassGo':
          _requireCurrentPlayer(playerId);
          engine!.playPassGo(_card(msg['cardId']) as ActionCard);
        case 'playHouse':
          _requireCurrentPlayer(playerId);
          engine!.playHouse(_card(msg['cardId']) as ActionCard, _color(msg['onColor']));
        case 'playHotel':
          _requireCurrentPlayer(playerId);
          engine!.playHotel(_card(msg['cardId']) as ActionCard, _color(msg['onColor']));
        case 'playDebtCollector':
          _requireCurrentPlayer(playerId);
          engine!.playDebtCollector(_card(msg['cardId']) as ActionCard, targetPlayerId: msg['targetPlayerId'] as String);
        case 'playItsMyBirthday':
          _requireCurrentPlayer(playerId);
          engine!.playItsMyBirthday(_card(msg['cardId']) as ActionCard);
        case 'playSlyDeal':
          _requireCurrentPlayer(playerId);
          engine!.playSlyDeal(
            _card(msg['cardId']) as ActionCard,
            targetPlayerId: msg['targetPlayerId'] as String,
            targetProperty: _card(msg['targetPropertyId']),
          );
        case 'playForcedDeal':
          _requireCurrentPlayer(playerId);
          engine!.playForcedDeal(
            _card(msg['cardId']) as ActionCard,
            targetPlayerId: msg['targetPlayerId'] as String,
            myProperty: _card(msg['myPropertyId']),
            theirProperty: _card(msg['theirPropertyId']),
          );
        case 'playDealBreaker':
          _requireCurrentPlayer(playerId);
          engine!.playDealBreaker(
            _card(msg['cardId']) as ActionCard,
            targetPlayerId: msg['targetPlayerId'] as String,
            targetColor: _color(msg['targetColor']),
          );
        case 'playRent':
          _requireCurrentPlayer(playerId);
          final doubleTheRentCardId = msg['doubleTheRentCardId'] as String?;
          engine!.playRent(
            _card(msg['cardId']) as RentCard,
            colorCharged: _color(msg['colorCharged']),
            doubleTheRentCard: doubleTheRentCardId == null ? null : _card(doubleTheRentCardId) as ActionCard,
          );
        case 'playJustSayNo':
          engine!.playJustSayNo(playerId, _card(msg['cardId']) as ActionCard);
        case 'resolvePendingAction':
          final pa = engine!.currentPendingAction;
          if (pa == null) {
            sendError(playerId, 'No pending action to resolve.');
            return;
          }
          if (pa.nextResponderId != playerId) {
            sendError(playerId, 'It is not your turn to respond.');
            return;
          }
          engine!.resolvePendingAction();
        case 'resolvePayment':
          final cardIds = (msg['cardIds'] as List).cast<String>();
          engine!.resolvePayment(playerId, cardIds.map(_card).toList());
        case 'endTurn':
          _requireCurrentPlayer(playerId);
          final discardIds = (msg['discardCardIds'] as List?)?.cast<String>();
          engine!.endTurn(discardChoices: discardIds?.map(_card).toList());
        default:
          sendError(playerId, 'Unknown move action: $action');
          return;
      }
      broadcastState();
    } on IllegalMoveException catch (e) {
      sendError(playerId, e.message);
    } catch (e) {
      sendError(playerId, 'Invalid move: $e');
    }
  }

  void sendError(String playerId, String message) {
    _connection(playerId)?.send({'type': 'error', 'message': message});
  }

  void broadcastState() {
    if (state == null) return;
    for (final c in connections) {
      c.send({'type': 'gameState', ...gameStateToJson(state!, viewerId: c.playerId)});
    }
  }
}
