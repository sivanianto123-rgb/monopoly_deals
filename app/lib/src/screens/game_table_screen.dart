import 'package:flutter/material.dart';
import 'package:monopoly_deal_engine/monopoly_deal_engine.dart';
import 'package:provider/provider.dart';

import '../game_client.dart';
import '../models/client_view.dart';
import '../theme/property_colors.dart';
import '../widgets/card_view.dart';
import '../widgets/pickers.dart';

class GameTableScreen extends StatelessWidget {
  const GameTableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final client = context.watch<GameClient>();
    final state = client.gameState!;
    final myId = client.myPlayerId!;
    final me = state.playerById(myId);
    final opponents = state.players.where((p) => p.id != myId).toList();
    final isMyTurn = state.currentPlayerId == myId;

    return Scaffold(
      appBar: AppBar(
        title: Text('Room ${client.roomCode}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              state.winnerId != null
                  ? '${state.playerById(state.winnerId!).name} won!'
                  : isMyTurn
                      ? 'Your turn — ${state.phase} phase (${state.actionsPlayedThisTurn}/3 played)'
                      : "${state.playerById(state.currentPlayerId).name}'s turn",
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (state.pendingActions.isNotEmpty) _PendingActionBanner(state: state, myId: myId, client: client),
          for (final payment in state.pendingPayments.where((p) => p.payerId == myId))
            _PendingPaymentBanner(state: state, payment: payment, me: me, client: client),
          if (client.lastError != null) _ErrorBanner(message: client.lastError!, onDismiss: client.clearError),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [for (final o in opponents) _OpponentCard(player: o, isCurrent: o.id == state.currentPlayerId)],
              ),
            ),
          ),
          const Divider(height: 1),
          _DrawDiscardRow(state: state),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: _PropertiesArea(player: me),
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: CardView.height + 16,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: [
                for (final c in me.hand ?? const [])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: CardView(
                      card: c,
                      onTap: isMyTurn && state.phase == 'play'
                          ? () => _onCardTapped(context, client, state, me, opponents, c)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: _TurnControls(state: state, isMyTurn: isMyTurn, client: client, me: me),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      backgroundColor: Colors.red.shade50,
      content: Text(message),
      actions: [TextButton(onPressed: onDismiss, child: const Text('Dismiss'))],
    );
  }
}

class _TurnControls extends StatelessWidget {
  final ClientGameState state;
  final bool isMyTurn;
  final GameClient client;
  final ClientPlayerView me;
  const _TurnControls({required this.state, required this.isMyTurn, required this.client, required this.me});

  @override
  Widget build(BuildContext context) {
    if (state.winnerId != null) return const SizedBox.shrink();
    if (!isMyTurn) return const Text('Waiting for your turn...', textAlign: TextAlign.center);
    if (state.phase == 'draw') {
      return FilledButton.icon(
        onPressed: () => client.move('startTurn'),
        icon: const Icon(Icons.style),
        label: const Text('Draw 2 cards'),
      );
    }
    final overLimit = (me.hand?.length ?? 0) - GameState.maxHandSize;
    return FilledButton.icon(
      onPressed: state.pendingActions.isEmpty && state.pendingPayments.isEmpty
          ? () => overLimit > 0 ? _endTurnWithDiscard(context, client, me, overLimit) : client.move('endTurn')
          : null,
      icon: const Icon(Icons.check),
      label: Text(overLimit > 0 ? 'Discard $overLimit & end turn' : 'End turn'),
    );
  }
}

Future<void> _endTurnWithDiscard(BuildContext context, GameClient client, ClientPlayerView me, int overLimit) async {
  final toDiscard = <DealCard>{};
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Choose $overLimit card(s) to discard'),
        content: SizedBox(
          width: double.maxFinite,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in me.hand ?? const <DealCard>[])
                CardView(
                  card: c,
                  selected: toDiscard.contains(c),
                  onTap: () => setState(() => toDiscard.contains(c) ? toDiscard.remove(c) : toDiscard.add(c)),
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: toDiscard.length == overLimit
                ? () {
                    client.move('endTurn', {'discardCardIds': toDiscard.map((c) => c.id).toList()});
                    Navigator.of(context).pop();
                  }
                : null,
            child: const Text('Discard & end turn'),
          ),
        ],
      ),
    ),
  );
}

class _OpponentCard extends StatelessWidget {
  final ClientPlayerView player;
  final bool isCurrent;
  const _OpponentCard({required this.player, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: isCurrent ? Colors.amber.shade700 : Colors.black12, width: isCurrent ? 2 : 1),
        borderRadius: BorderRadius.circular(8),
        color: isCurrent ? Colors.amber.shade50 : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(player.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('${player.handCount} cards · \$${player.bankTotal}M', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          Text('${player.properties.where((s) => s.isComplete).length} sets', maxLines: 1, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _DrawDiscardRow extends StatelessWidget {
  final ClientGameState state;
  const _DrawDiscardRow({required this.state});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(children: [const Icon(Icons.layers), Text('Draw pile: ${state.drawPileCount}')]),
          Column(children: [
            const Icon(Icons.delete_outline),
            Text('Discard: ${state.discardCount}${state.discardTop != null ? " (top: ${_shortCardLabel(state.discardTop!)})" : ""}'),
          ]),
        ],
      ),
    );
  }
}

String _shortCardLabel(DealCard card) => switch (card) {
      MoneyCard c => '\$${c.bankValue}M',
      PropertyCard c => c.name,
      PropertyWildCard _ => 'Wild',
      RentCard _ => 'Rent',
      ActionCard c => actionTypeLabel(c.type),
    };

class _PropertiesArea extends StatelessWidget {
  final ClientPlayerView player;
  const _PropertiesArea({required this.player});

  @override
  Widget build(BuildContext context) {
    if (player.properties.isEmpty) {
      return const Padding(padding: EdgeInsets.all(16), child: Text('No properties yet.'));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final set in player.properties) _PropertySetChip(set: set)],
    );
  }
}

class _PropertySetChip extends StatelessWidget {
  final ClientPropertySet set;
  const _PropertySetChip({required this.set});

  @override
  Widget build(BuildContext context) {
    final fg = propertyForegroundFor(set.color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: propertySwatch[set.color], borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${propertyColorLabel(set.color)} ${set.cards.length}/${set.isComplete ? set.cards.length.clamp(0, 99) : propertySetInfo[set.color]!.setSize}',
            style: TextStyle(color: fg, fontWeight: FontWeight.w600),
          ),
          if (set.isComplete) Icon(Icons.check_circle, size: 16, color: fg),
          if (set.hasHouse) Icon(Icons.home, size: 16, color: fg),
          if (set.hasHotel) Icon(Icons.apartment, size: 16, color: fg),
          Text(' \$${set.rent}M rent', style: TextStyle(color: fg, fontSize: 12)),
        ],
      ),
    );
  }
}

class _PendingActionBanner extends StatelessWidget {
  final ClientGameState state;
  final String myId;
  final GameClient client;
  const _PendingActionBanner({required this.state, required this.myId, required this.client});

  @override
  Widget build(BuildContext context) {
    final pa = state.pendingActions.first;
    final source = state.playerById(pa.sourcePlayerId).name;
    final description = switch (pa.kind) {
      PendingActionKind.slyDeal => '$source wants to steal one of your properties.',
      PendingActionKind.forcedDeal => '$source wants to swap properties with you.',
      PendingActionKind.dealBreaker =>
        '$source wants to steal your complete ${pa.takenSetColor != null ? propertyColorLabel(pa.takenSetColor!) : ''} set.',
      PendingActionKind.debtCollector => '$source wants you to pay \$${pa.amountOwed}M.',
      PendingActionKind.itsMyBirthday => "$source wants \$${pa.amountOwed}M for their birthday.",
      PendingActionKind.rent => '$source is charging \$${pa.amountOwed}M rent.',
    };

    if (pa.nextResponderId != myId) {
      return Container(
        width: double.infinity,
        color: Colors.amber.shade50,
        padding: const EdgeInsets.all(12),
        child: Text('$description Waiting for ${state.playerById(pa.nextResponderId).name}...'),
      );
    }

    final myJustSayNo = state.playerById(myId).hand?.whereType<ActionCard>().where((a) => a.type == ActionType.justSayNo);
    final jsnCard = (myJustSayNo?.isNotEmpty ?? false) ? myJustSayNo!.first : null;

    return MaterialBanner(
      backgroundColor: Colors.amber.shade50,
      content: Text(description),
      actions: [
        if (jsnCard != null)
          TextButton(
            onPressed: () => client.move('playJustSayNo', {'cardId': jsnCard.id}),
            child: const Text('Just Say No!'),
          ),
        FilledButton(onPressed: () => client.move('resolvePendingAction'), child: const Text('Accept')),
      ],
    );
  }
}

class _PendingPaymentBanner extends StatelessWidget {
  final ClientGameState state;
  final ClientPendingPayment payment;
  final ClientPlayerView me;
  final GameClient client;
  const _PendingPaymentBanner({required this.state, required this.payment, required this.me, required this.client});

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      backgroundColor: Colors.red.shade50,
      content: Text('You owe ${state.playerById(payment.payeeId).name} \$${payment.amount}M.'),
      actions: [
        FilledButton(
          onPressed: () => _showPaymentPicker(context, client, me, payment),
          child: const Text('Pay'),
        ),
      ],
    );
  }
}

Future<void> _showPaymentPicker(BuildContext context, GameClient client, ClientPlayerView me, ClientPendingPayment payment) async {
  final allAssets = [...me.bank, for (final s in me.properties) ...s.cards];
  final selected = <DealCard>{};
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final total = selected.fold<int>(0, (sum, c) => sum + c.bankValue);
        final canConfirm = total >= payment.amount || (selected.length == allAssets.length && allAssets.isNotEmpty);
        return AlertDialog(
          title: Text('Pay \$${payment.amount}M — selected \$${total}M'),
          content: SizedBox(
            width: double.maxFinite,
            child: allAssets.isEmpty
                ? const Text("You don't have anything to pay with.")
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in allAssets)
                        CardView(
                          card: c,
                          selected: selected.contains(c),
                          onTap: () => setState(() => selected.contains(c) ? selected.remove(c) : selected.add(c)),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => setState(() {
                selected
                  ..clear()
                  ..addAll(allAssets);
              }),
              child: const Text('Give everything'),
            ),
            FilledButton(
              onPressed: canConfirm
                  ? () {
                      client.move('resolvePayment', {'cardIds': selected.map((c) => c.id).toList()});
                      Navigator.of(context).pop();
                    }
                  : null,
              child: const Text('Pay'),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> _onCardTapped(
  BuildContext context,
  GameClient client,
  ClientGameState state,
  ClientPlayerView me,
  List<ClientPlayerView> opponents,
  DealCard card,
) async {
  switch (card) {
    case MoneyCard _:
      client.move('playToBank', {'cardId': card.id});
    case PropertyCard _:
      client.move('playToProperty', {'cardId': card.id});
    case PropertyWildCard c:
      final color = await pickColor(context, c.isAnyColor ? PropertyColor.values.toList() : c.eligibleColors.toList());
      if (color == null) return;
      client.move('playToProperty', {'cardId': card.id, 'chosenColor': color.name});
    case RentCard c:
      await _handleRent(context, client, me, c);
    case ActionCard c:
      await _handleAction(context, client, state, me, opponents, c);
  }
}

Future<void> _handleRent(BuildContext context, GameClient client, ClientPlayerView me, RentCard card) async {
  final eligibleColors = (card.isWild ? PropertyColor.values.toList() : card.colors.toList())
      .where((c) => (me.propertySet(c)?.cards.isNotEmpty ?? false))
      .toList();
  final bankOption = Option<String>('Play to bank (\$${card.bankValue}M)', 'bank');
  final choice = await pickOption(context, 'Rent', [bankOption, if (eligibleColors.isNotEmpty) Option('Charge rent', 'rent')]);
  if (choice == null) return;
  if (choice == 'bank') {
    client.move('playToBank', {'cardId': card.id});
    return;
  }
  if (!context.mounted) return;
  final color = await pickColor(context, eligibleColors, title: 'Charge rent for which color?');
  if (color == null) return;

  final doubleCards = (me.hand ?? const []).whereType<ActionCard>().where((a) => a.type == ActionType.doubleTheRent).toList();
  String? doubleId;
  if (doubleCards.isNotEmpty && context.mounted) {
    final useDouble = await confirm(
      context,
      'Double The Rent?',
      'You have a Double The Rent card — play it with this Rent card to double the amount?',
      confirmLabel: 'Double it',
    );
    if (useDouble) doubleId = doubleCards.first.id;
  }

  client.move('playRent', {
    'cardId': card.id,
    'colorCharged': color.name,
    'doubleTheRentCardId': ?doubleId,
  });
}

Future<void> _handleAction(
  BuildContext context,
  GameClient client,
  ClientGameState state,
  ClientPlayerView me,
  List<ClientPlayerView> opponents,
  ActionCard card,
) async {
  final bankOption = Option<String>('Play to bank (\$${card.bankValue}M)', 'bank');

  switch (card.type) {
    case ActionType.passGo:
      final choice = await pickOption(context, actionTypeLabel(card.type), [bankOption, Option('Draw 2 cards', 'play')]);
      if (choice == 'play') client.move('playPassGo', {'cardId': card.id});
      if (choice == 'bank') client.move('playToBank', {'cardId': card.id});

    case ActionType.itsMyBirthday:
      final choice = await pickOption(context, actionTypeLabel(card.type), [bankOption, Option('Collect \$2M from everyone', 'play')]);
      if (choice == 'play') client.move('playItsMyBirthday', {'cardId': card.id});
      if (choice == 'bank') client.move('playToBank', {'cardId': card.id});

    case ActionType.debtCollector:
      final choice = await pickOption(context, actionTypeLabel(card.type), [bankOption, Option('Collect \$5M from a player', 'play')]);
      if (choice == null) return;
      if (choice == 'bank') {
        client.move('playToBank', {'cardId': card.id});
        return;
      }
      if (!context.mounted) return;
      final targetId = await pickOpponent(context, opponents);
      if (targetId == null) return;
      client.move('playDebtCollector', {'cardId': card.id, 'targetPlayerId': targetId});

    case ActionType.house:
    case ActionType.hotel:
      final eligible = me.properties
          .where((s) =>
              s.isComplete &&
              s.color != PropertyColor.railroad &&
              s.color != PropertyColor.utility &&
              (card.type == ActionType.house ? !s.hasHouse : (s.hasHouse && !s.hasHotel)))
          .map((s) => s.color)
          .toList();
      final choice = await pickOption(context, actionTypeLabel(card.type), [bankOption, if (eligible.isNotEmpty) Option('Add to a set', 'play')]);
      if (choice == null) return;
      if (choice == 'bank') {
        client.move('playToBank', {'cardId': card.id});
        return;
      }
      if (!context.mounted) return;
      final color = await pickColor(context, eligible, title: 'Add to which set?');
      if (color == null) return;
      client.move(card.type == ActionType.house ? 'playHouse' : 'playHotel', {'cardId': card.id, 'onColor': color.name});

    case ActionType.slyDeal:
      final choice = await pickOption(context, actionTypeLabel(card.type), [bankOption, Option('Steal a property', 'play')]);
      if (choice == null) return;
      if (choice == 'bank') {
        client.move('playToBank', {'cardId': card.id});
        return;
      }
      if (!context.mounted) return;
      final targetId = await pickOpponent(context, opponents);
      if (targetId == null) return;
      final target = state.playerById(targetId);
      final stealable = [for (final s in target.properties) if (!s.isComplete) ...s.cards];
      if (stealable.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That player has no stealable properties.')));
        }
        return;
      }
      if (!context.mounted) return;
      final prop = await pickCard(context, stealable, title: 'Steal which property?');
      if (prop == null) return;
      client.move('playSlyDeal', {'cardId': card.id, 'targetPlayerId': targetId, 'targetPropertyId': prop.id});

    case ActionType.forcedDeal:
      final myOffers = [for (final s in me.properties) if (!s.isComplete) ...s.cards];
      final choice = await pickOption(context, actionTypeLabel(card.type), [bankOption, if (myOffers.isNotEmpty) Option('Swap a property', 'play')]);
      if (choice == null) return;
      if (choice == 'bank') {
        client.move('playToBank', {'cardId': card.id});
        return;
      }
      if (!context.mounted) return;
      final targetId = await pickOpponent(context, opponents);
      if (targetId == null) return;
      final target = state.playerById(targetId);
      final theirs = [for (final s in target.properties) if (!s.isComplete) ...s.cards];
      if (theirs.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That player has no swappable properties.')));
        }
        return;
      }
      if (!context.mounted) return;
      final theirProp = await pickCard(context, theirs, title: 'Take which of their properties?');
      if (theirProp == null) return;
      if (!context.mounted) return;
      final myProp = await pickCard(context, myOffers, title: 'Give which of your properties?');
      if (myProp == null) return;
      client.move('playForcedDeal', {
        'cardId': card.id,
        'targetPlayerId': targetId,
        'myPropertyId': myProp.id,
        'theirPropertyId': theirProp.id,
      });

    case ActionType.dealBreaker:
      final choice = await pickOption(context, actionTypeLabel(card.type), [bankOption, Option('Steal a complete set', 'play')]);
      if (choice == null) return;
      if (choice == 'bank') {
        client.move('playToBank', {'cardId': card.id});
        return;
      }
      if (!context.mounted) return;
      final targetId = await pickOpponent(context, opponents);
      if (targetId == null) return;
      final target = state.playerById(targetId);
      final completeColors = target.properties.where((s) => s.isComplete).map((s) => s.color).toList();
      if (completeColors.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That player has no complete sets.')));
        }
        return;
      }
      if (!context.mounted) return;
      final color = await pickColor(context, completeColors, title: 'Take which complete set?');
      if (color == null) return;
      client.move('playDealBreaker', {'cardId': card.id, 'targetPlayerId': targetId, 'targetColor': color.name});

    case ActionType.justSayNo:
    case ActionType.doubleTheRent:
      final choice = await pickOption(context, '${actionTypeLabel(card.type)} can only be played as a response', [bankOption]);
      if (choice == 'bank') client.move('playToBank', {'cardId': card.id});
  }
}
