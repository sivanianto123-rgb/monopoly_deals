import 'cards.dart';
import 'game_state.dart';
import 'pending_action.dart';

/// Thrown when a requested move is illegal given the current [GameState].
/// The server/UI layer is expected to catch this and reject the move
/// rather than let it crash a turn.
class IllegalMoveException implements Exception {
  final String message;
  IllegalMoveException(this.message);
  @override
  String toString() => 'IllegalMoveException: $message';
}

/// Deals a fresh game: shuffles a full deck and gives each player 5 cards.
/// `allCards` is injected so tests/the server can pass `buildFullDeck()`
/// explicitly rather than this function owning deck construction.
GameState startNewGame({
  required List<String> playerNames,
  required List<DealCard> allCards,
  required Random random,
}) {
  if (playerNames.length < 2 || playerNames.length > 5) {
    throw IllegalMoveException('Monopoly Deal supports 2-5 players, got ${playerNames.length}.');
  }
  final deck = [...allCards]..shuffle(random);
  final players = [
    for (var i = 0; i < playerNames.length; i++) Player(id: 'p$i', name: playerNames[i]),
  ];
  final state = GameState(players: players, drawPile: deck);
  for (final p in players) {
    p.hand.addAll(state.drawCards(5, random: random));
  }
  state.phase = TurnPhase.draw;
  return state;
}

/// Turn flow plus every action card's effect.
///
/// Action cards that target another player (Sly Deal, Forced Deal, Deal
/// Breaker, Debt Collector, It's My Birthday, Rent) don't resolve the
/// instant they're played — they become a [PendingAction] that the target
/// can answer with a Just Say No (see [playJustSayNo]) before anyone calls
/// [resolvePendingAction]. Debt Collector/Birthday/Rent, once resolved,
/// turn into a [PendingPayment] that the payer settles with
/// [resolvePayment]. [endTurn] refuses to run while either queue is
/// non-empty, so the caller (server/UI) must drive those to completion
/// before moving on.
class TurnEngine {
  final GameState state;
  final Random random;

  TurnEngine(this.state, {Random? random}) : random = random ?? Random();

  Player get _current => state.currentPlayer;

  List<Player> get _opponents => state.players.where((p) => p.id != _current.id).toList();

  /// Must be called once at the start of a player's turn before any other
  /// move. Draws 2 cards from the draw pile.
  void startTurn() {
    if (state.phase != TurnPhase.draw) {
      throw IllegalMoveException('Turn already started (phase=${state.phase}).');
    }
    _current.hand.addAll(state.drawCards(GameState.cardsDrawnPerTurn, random: random));
    state.actionsPlayedThisTurn = 0;
    state.phase = TurnPhase.play;
  }

  void _requireCardInHand(DealCard card) {
    if (!_current.hand.contains(card)) {
      throw IllegalMoveException('${card.id} is not in ${_current.name}\'s hand.');
    }
  }

  void _requireActionBudget() {
    if (state.actionsPlayedThisTurn >= GameState.maxActionsPerTurn) {
      throw IllegalMoveException('Already played ${GameState.maxActionsPerTurn} cards this turn.');
    }
  }

  /// Common play-a-card-from-hand bookkeeping for action/rent cards: phase
  /// check, hand membership, the 3-card turn budget (a multi-card play like
  /// Rent + Double The Rent passes both cards and consumes 2 slots), moves
  /// the cards to the discard pile, and advances the counter.
  void _beginAction(List<DealCard> cards) {
    if (state.phase != TurnPhase.play) {
      throw IllegalMoveException('Not in the play phase (phase=${state.phase}).');
    }
    for (final c in cards) {
      _requireCardInHand(c);
    }
    final slots = cards.length;
    if (state.actionsPlayedThisTurn + slots > GameState.maxActionsPerTurn) {
      throw IllegalMoveException(
          'Not enough action slots left this turn (need $slots, have ${GameState.maxActionsPerTurn - state.actionsPlayedThisTurn}).');
    }
    for (final c in cards) {
      _current.hand.remove(c);
      state.discardPile.add(c);
    }
    state.actionsPlayedThisTurn += slots;
  }

  /// Plays a money-valued card (a [MoneyCard], or any [ActionCard]/[RentCard]
  /// used purely for its bank value) face-up into the player's bank.
  void playToBank(DealCard card) {
    if (state.phase != TurnPhase.play) {
      throw IllegalMoveException('Not in the play phase (phase=${state.phase}).');
    }
    _requireCardInHand(card);
    _requireActionBudget();
    if (card is PropertyCard || card is PropertyWildCard) {
      throw IllegalMoveException('Property cards cannot be banked; play them to a property set instead.');
    }
    _current.hand.remove(card);
    _current.bank.add(card);
    state.actionsPlayedThisTurn++;
  }

  /// Plays a [PropertyCard] or [PropertyWildCard] face-up as real estate.
  /// [chosenColor] is required for wildcards (and must be one of
  /// [PropertyWildCard.eligibleColors]); it's ignored for plain
  /// [PropertyCard]s, which always go to their own color.
  void playToProperty(DealCard card, {PropertyColor? chosenColor}) {
    if (state.phase != TurnPhase.play) {
      throw IllegalMoveException('Not in the play phase (phase=${state.phase}).');
    }
    _requireCardInHand(card);
    _requireActionBudget();

    final PropertyColor color;
    if (card is PropertyCard) {
      color = card.color;
    } else if (card is PropertyWildCard) {
      if (chosenColor == null || !card.eligibleColors.contains(chosenColor)) {
        throw IllegalMoveException('Must choose a color from ${card.eligibleColors} for this wildcard.');
      }
      color = chosenColor;
    } else {
      throw IllegalMoveException('${card.runtimeType} is not a property card.');
    }

    _current.hand.remove(card);
    _current.properties.putIfAbsent(color, () => PropertySet(color)).cards.add(card);
    state.actionsPlayedThisTurn++;
  }

  /// Re-assigns an in-play wildcard to a different eligible color, as long
  /// as it isn't currently part of a complete set (official rule: you can
  /// move a wildcard between colors freely otherwise). This does not cost
  /// one of the 3 turn actions.
  void moveWildcard(PropertyWildCard card, PropertyColor newColor) {
    if (!card.eligibleColors.contains(newColor)) {
      throw IllegalMoveException('${card.id} cannot be assigned to ${newColor.name}.');
    }
    PropertyColor? currentColor;
    for (final entry in _current.properties.entries) {
      if (entry.value.cards.contains(card)) {
        currentColor = entry.key;
        break;
      }
    }
    if (currentColor == null) {
      throw IllegalMoveException('${card.id} is not currently in play for ${_current.name}.');
    }
    final fromSet = _current.properties[currentColor]!;
    if (fromSet.isComplete) {
      throw IllegalMoveException('Cannot move a wildcard out of a completed set.');
    }
    fromSet.cards.remove(card);
    _current.properties.putIfAbsent(newColor, () => PropertySet(newColor)).cards.add(card);
  }

  // ---------------------------------------------------------------------
  // Instant actions (no target, can't be Just-Say-No'd)
  // ---------------------------------------------------------------------

  void playPassGo(ActionCard card) {
    if (card.type != ActionType.passGo) {
      throw IllegalMoveException('${card.id} is not Pass Go.');
    }
    _beginAction([card]);
    _current.hand.addAll(state.drawCards(2, random: random));
  }

  void playHouse(ActionCard card, PropertyColor onSet) {
    if (card.type != ActionType.house) {
      throw IllegalMoveException('${card.id} is not House.');
    }
    final set = _current.properties[onSet];
    if (set == null || !set.isComplete) {
      throw IllegalMoveException('Need a complete ${onSet.name} set to add a House.');
    }
    if (!set.canHaveBuildings) {
      throw IllegalMoveException('Railroad/Utility sets cannot have buildings.');
    }
    if (set.hasHouse) {
      throw IllegalMoveException('This set already has a House.');
    }
    _beginAction([card]);
    set.hasHouse = true;
  }

  void playHotel(ActionCard card, PropertyColor onSet) {
    if (card.type != ActionType.hotel) {
      throw IllegalMoveException('${card.id} is not Hotel.');
    }
    final set = _current.properties[onSet];
    if (set == null || !set.isComplete) {
      throw IllegalMoveException('Need a complete ${onSet.name} set to add a Hotel.');
    }
    if (!set.hasHouse) {
      throw IllegalMoveException('A Hotel needs a House on this set first.');
    }
    if (set.hasHotel) {
      throw IllegalMoveException('This set already has a Hotel.');
    }
    _beginAction([card]);
    set.hasHotel = true;
  }

  // ---------------------------------------------------------------------
  // Targeted actions: enqueue a PendingAction, resolved later via
  // resolvePendingAction() once Just Say No responses (if any) are done.
  // ---------------------------------------------------------------------

  void playDebtCollector(ActionCard card, {required String targetPlayerId}) {
    if (card.type != ActionType.debtCollector) {
      throw IllegalMoveException('${card.id} is not Debt Collector.');
    }
    if (targetPlayerId == _current.id) {
      throw IllegalMoveException('Cannot target yourself.');
    }
    state.playerById(targetPlayerId);
    _beginAction([card]);
    state.pendingActions.add(PendingAction(
      kind: PendingActionKind.debtCollector,
      sourceCard: card,
      sourcePlayerId: _current.id,
      targetPlayerId: targetPlayerId,
      amountOwed: 5,
    ));
  }

  void playItsMyBirthday(ActionCard card) {
    if (card.type != ActionType.itsMyBirthday) {
      throw IllegalMoveException('${card.id} is not It\'s My Birthday.');
    }
    _beginAction([card]);
    for (final opponent in _opponents) {
      state.pendingActions.add(PendingAction(
        kind: PendingActionKind.itsMyBirthday,
        sourceCard: card,
        sourcePlayerId: _current.id,
        targetPlayerId: opponent.id,
        amountOwed: 2,
      ));
    }
  }

  void playSlyDeal(ActionCard card, {required String targetPlayerId, required DealCard targetProperty}) {
    if (card.type != ActionType.slyDeal) {
      throw IllegalMoveException('${card.id} is not Sly Deal.');
    }
    if (targetPlayerId == _current.id) {
      throw IllegalMoveException('Cannot target yourself.');
    }
    final target = state.playerById(targetPlayerId);
    final owningSet = _findOwningSet(target, targetProperty);
    if (owningSet == null) {
      throw IllegalMoveException('${target.name} does not own ${targetProperty.id}.');
    }
    if (owningSet.isComplete) {
      throw IllegalMoveException('Cannot Sly Deal a property out of a complete set.');
    }

    _beginAction([card]);
    state.pendingActions.add(PendingAction(
      kind: PendingActionKind.slyDeal,
      sourceCard: card,
      sourcePlayerId: _current.id,
      targetPlayerId: targetPlayerId,
      takenProperty: targetProperty,
    ));
  }

  void playForcedDeal(
    ActionCard card, {
    required String targetPlayerId,
    required DealCard myProperty,
    required DealCard theirProperty,
  }) {
    if (card.type != ActionType.forcedDeal) {
      throw IllegalMoveException('${card.id} is not Forced Deal.');
    }
    if (targetPlayerId == _current.id) {
      throw IllegalMoveException('Cannot target yourself.');
    }
    final target = state.playerById(targetPlayerId);

    final mySet = _findOwningSet(_current, myProperty);
    if (mySet == null) {
      throw IllegalMoveException('You do not own ${myProperty.id}.');
    }
    if (mySet.isComplete) {
      throw IllegalMoveException('Cannot offer a property from a complete set.');
    }

    final theirSet = _findOwningSet(target, theirProperty);
    if (theirSet == null) {
      throw IllegalMoveException('${target.name} does not own ${theirProperty.id}.');
    }
    if (theirSet.isComplete) {
      throw IllegalMoveException('Cannot Forced Deal a property out of a complete set.');
    }

    _beginAction([card]);
    state.pendingActions.add(PendingAction(
      kind: PendingActionKind.forcedDeal,
      sourceCard: card,
      sourcePlayerId: _current.id,
      targetPlayerId: targetPlayerId,
      takenProperty: theirProperty,
      givenProperty: myProperty,
    ));
  }

  void playDealBreaker(ActionCard card, {required String targetPlayerId, required PropertyColor targetColor}) {
    if (card.type != ActionType.dealBreaker) {
      throw IllegalMoveException('${card.id} is not Deal Breaker.');
    }
    if (targetPlayerId == _current.id) {
      throw IllegalMoveException('Cannot target yourself.');
    }
    final target = state.playerById(targetPlayerId);
    final set = target.properties[targetColor];
    if (set == null || !set.isComplete) {
      throw IllegalMoveException('${target.name} does not have a complete ${targetColor.name} set.');
    }

    _beginAction([card]);
    state.pendingActions.add(PendingAction(
      kind: PendingActionKind.dealBreaker,
      sourceCard: card,
      sourcePlayerId: _current.id,
      targetPlayerId: targetPlayerId,
      takenSetColor: targetColor,
    ));
  }

  /// Plays a Rent card against every opponent for [colorCharged] (a color
  /// the current player owns at least one property of). Pass
  /// [doubleTheRentCard] to play it together with the rent card and double
  /// the amount — this consumes 2 of the turn's 3 action slots instead of 1.
  void playRent(RentCard card, {required PropertyColor colorCharged, ActionCard? doubleTheRentCard}) {
    if (!card.isWild && !card.colors.contains(colorCharged)) {
      throw IllegalMoveException('${card.id} cannot charge rent for ${colorCharged.name}.');
    }
    final mySet = _current.properties[colorCharged];
    if (mySet == null || mySet.cards.isEmpty) {
      throw IllegalMoveException('You do not own any ${colorCharged.name} properties.');
    }
    if (doubleTheRentCard != null && doubleTheRentCard.type != ActionType.doubleTheRent) {
      throw IllegalMoveException('${doubleTheRentCard.id} is not Double The Rent.');
    }

    _beginAction(doubleTheRentCard == null ? [card] : [card, doubleTheRentCard]);

    final amount = mySet.rent * (doubleTheRentCard != null ? 2 : 1);
    for (final opponent in _opponents) {
      state.pendingActions.add(PendingAction(
        kind: PendingActionKind.rent,
        sourceCard: card,
        sourcePlayerId: _current.id,
        targetPlayerId: opponent.id,
        amountOwed: amount,
      ));
    }
  }

  PropertySet? _findOwningSet(Player player, DealCard card) {
    for (final set in player.properties.values) {
      if (set.cards.contains(card)) return set;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Just Say No responses + resolution
  // ---------------------------------------------------------------------

  /// The pending action currently open for a response (the one at the
  /// front of the queue), or null if there's nothing outstanding.
  PendingAction? get currentPendingAction => state.pendingActions.isEmpty ? null : state.pendingActions.first;

  /// [respondingPlayerId] plays Just Say No against the current pending
  /// action. Must be that player's turn to respond (see
  /// [PendingAction.nextResponderId] — the target responds first, then it
  /// alternates back to the original player if they counter). Does not
  /// consume one of the turn's 3 action slots.
  void playJustSayNo(String respondingPlayerId, ActionCard card) {
    if (card.type != ActionType.justSayNo) {
      throw IllegalMoveException('${card.id} is not Just Say No.');
    }
    final pa = currentPendingAction;
    if (pa == null) {
      throw IllegalMoveException('No pending action to respond to.');
    }
    if (pa.nextResponderId != respondingPlayerId) {
      throw IllegalMoveException('It is not $respondingPlayerId\'s turn to respond.');
    }
    final responder = state.playerById(respondingPlayerId);
    if (!responder.hand.contains(card)) {
      throw IllegalMoveException('${card.id} is not in ${responder.name}\'s hand.');
    }
    responder.hand.remove(card);
    state.discardPile.add(card);
    pa.justSayNoChain.add(card);
  }

  /// Finalizes the pending action at the front of the queue: if the Just
  /// Say No chain currently cancels it, nothing else happens; otherwise its
  /// effect applies (property transfer happens immediately; Debt
  /// Collector/Birthday/Rent instead become a [PendingPayment]). Call this
  /// once whoever's turn it is to respond ([PendingAction.nextResponderId])
  /// has decided not to play another Just Say No.
  void resolvePendingAction() {
    if (state.pendingActions.isEmpty) {
      throw IllegalMoveException('No pending action.');
    }
    final pa = state.pendingActions.removeAt(0);
    if (pa.isCancelled) return;

    switch (pa.kind) {
      case PendingActionKind.slyDeal:
        _applySlyDeal(pa);
      case PendingActionKind.forcedDeal:
        _applyForcedDeal(pa);
      case PendingActionKind.dealBreaker:
        _applyDealBreaker(pa);
      case PendingActionKind.debtCollector:
      case PendingActionKind.itsMyBirthday:
      case PendingActionKind.rent:
        state.pendingPayments.add(PendingPayment(
          payerId: pa.targetPlayerId,
          payeeId: pa.sourcePlayerId,
          amount: pa.amountOwed!,
        ));
    }
  }

  void _applySlyDeal(PendingAction pa) {
    final target = state.playerById(pa.targetPlayerId);
    final source = state.playerById(pa.sourcePlayerId);
    final card = pa.takenProperty!;

    final owningSet = _findOwningSet(target, card);
    if (owningSet == null) return; // defensive: already gone somehow
    owningSet.cards.remove(card);

    final placedColor = card is PropertyCard ? card.color : owningSet.color;
    source.properties.putIfAbsent(placedColor, () => PropertySet(placedColor)).cards.add(card);
  }

  void _applyForcedDeal(PendingAction pa) {
    final target = state.playerById(pa.targetPlayerId);
    final source = state.playerById(pa.sourcePlayerId);
    final fromTarget = pa.takenProperty!;
    final fromSource = pa.givenProperty!;

    final targetOwningSet = _findOwningSet(target, fromTarget);
    final sourceOwningSet = _findOwningSet(source, fromSource);
    if (targetOwningSet == null || sourceOwningSet == null) return;

    targetOwningSet.cards.remove(fromTarget);
    sourceOwningSet.cards.remove(fromSource);

    final placeInSource = fromTarget is PropertyCard ? fromTarget.color : targetOwningSet.color;
    final placeInTarget = fromSource is PropertyCard ? fromSource.color : sourceOwningSet.color;
    source.properties.putIfAbsent(placeInSource, () => PropertySet(placeInSource)).cards.add(fromTarget);
    target.properties.putIfAbsent(placeInTarget, () => PropertySet(placeInTarget)).cards.add(fromSource);
  }

  void _applyDealBreaker(PendingAction pa) {
    final target = state.playerById(pa.targetPlayerId);
    final source = state.playerById(pa.sourcePlayerId);
    final color = pa.takenSetColor!;

    final takenSet = target.properties.remove(color);
    if (takenSet == null) return;

    final existing = source.properties[color];
    if (existing == null) {
      source.properties[color] = takenSet;
    } else {
      existing.cards.addAll(takenSet.cards);
      existing.hasHouse = existing.hasHouse || takenSet.hasHouse;
      existing.hasHotel = existing.hasHotel || takenSet.hasHotel;
    }
  }

  // ---------------------------------------------------------------------
  // Payment resolution
  // ---------------------------------------------------------------------

  /// Settles a [PendingPayment] owed by [payerId]: [cardsGiven] must total
  /// at least the amount owed, UNLESS they add up to everything the payer
  /// owns (bank + every property card, win-condition-breaking sets
  /// included) — matching the official "give what you've got" rule for a
  /// player who can't fully cover a debt. Money/action/rent cards go to the
  /// payee's bank; property cards go straight into the payee's matching
  /// property set (becoming theirs).
  void resolvePayment(String payerId, List<DealCard> cardsGiven) {
    final idx = state.pendingPayments.indexWhere((p) => p.payerId == payerId);
    if (idx == -1) {
      throw IllegalMoveException('$payerId has no pending payment.');
    }
    final payment = state.pendingPayments[idx];
    final payer = state.playerById(payerId);
    final payee = state.playerById(payment.payeeId);

    for (final c in cardsGiven) {
      final owned = payer.bank.contains(c) || _findOwningSet(payer, c) != null;
      if (!owned) {
        throw IllegalMoveException('${c.id} does not belong to ${payer.name}.');
      }
    }

    final allAssets = [
      ...payer.bank,
      for (final set in payer.properties.values) ...set.cards,
    ];
    final offeredTotal = cardsGiven.fold(0, (sum, c) => sum + c.bankValue);

    if (offeredTotal < payment.amount && cardsGiven.length != allAssets.length) {
      final totalAssets = allAssets.fold(0, (sum, c) => sum + c.bankValue);
      throw IllegalMoveException(
          'Must offer at least \$${payment.amount}M, or everything ${payer.name} owns (\$${totalAssets}M) if that\'s less.');
    }

    for (final c in cardsGiven) {
      PropertyColor? fromColor;
      if (!payer.bank.remove(c)) {
        final owningSet = _findOwningSet(payer, c);
        fromColor = owningSet?.color;
        owningSet?.cards.remove(c);
      }

      if (c is MoneyCard || c is ActionCard || c is RentCard) {
        payee.bank.add(c);
      } else if (c is PropertyCard) {
        payee.properties.putIfAbsent(c.color, () => PropertySet(c.color)).cards.add(c);
      } else if (c is PropertyWildCard) {
        final color = fromColor ?? c.eligibleColors.first;
        payee.properties.putIfAbsent(color, () => PropertySet(color)).cards.add(c);
      }
    }

    state.pendingPayments.removeAt(idx);
  }

  /// Ends the current player's turn: discards down to the 7-card hand
  /// limit, advances to the next player, and resets turn-scoped counters.
  /// [discardChoices] picks which excess cards to discard when the hand is
  /// over the limit; if omitted, the engine discards arbitrarily from the
  /// end of the hand. Refuses to run while any pending action or payment is
  /// unresolved.
  void endTurn({List<DealCard>? discardChoices}) {
    if (state.phase != TurnPhase.play) {
      throw IllegalMoveException('Cannot end turn from phase=${state.phase}.');
    }
    if (state.pendingActions.isNotEmpty) {
      throw IllegalMoveException('Cannot end turn with ${state.pendingActions.length} pending action(s) unresolved.');
    }
    if (state.pendingPayments.isNotEmpty) {
      throw IllegalMoveException(
          'Cannot end turn with ${state.pendingPayments.length} pending payment(s) unresolved.');
    }
    state.phase = TurnPhase.discard;

    final excess = _current.hand.length - GameState.maxHandSize;
    if (excess > 0) {
      final toDiscard = discardChoices ?? _current.hand.sublist(_current.hand.length - excess);
      if (toDiscard.length != excess) {
        throw IllegalMoveException('Must discard exactly $excess card(s), got ${toDiscard.length}.');
      }
      for (final c in toDiscard) {
        _requireCardInHand(c);
      }
      for (final c in toDiscard) {
        _current.hand.remove(c);
        state.discardPile.add(c);
      }
    }

    if (state.winner != null) {
      state.phase = TurnPhase.over;
      return;
    }

    state.currentPlayerIndex = (state.currentPlayerIndex + 1) % state.players.length;
    state.phase = TurnPhase.draw;
  }
}
