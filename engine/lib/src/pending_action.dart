import 'cards.dart';

/// The kinds of action cards that target another player and can therefore
/// be answered with a Just Say No.
enum PendingActionKind {
  slyDeal,
  forcedDeal,
  dealBreaker,
  debtCollector,
  itsMyBirthday,
  rent,
}

/// An action card that has been played against [targetPlayerId] but hasn't
/// resolved yet — the target gets a chance to play Just Say No first (and
/// the original player can counter with their own Just Say No, and so on).
///
/// [justSayNoChain] records that back-and-forth in order. An odd number of
/// Just Say No cards means the action is currently cancelled; an even
/// number (including zero) means it currently goes through.
class PendingAction {
  final PendingActionKind kind;

  /// The card that created this pending action — an [ActionCard] for
  /// everything except Rent, where it's the [RentCard] played.
  final DealCard sourceCard;
  final String sourcePlayerId;
  final String targetPlayerId;

  /// Sly Deal: the single property being taken from the target.
  /// Forced Deal: the property the target gives up (in exchange for
  /// [givenProperty]).
  final DealCard? takenProperty;

  /// Forced Deal only: the property the source gives to the target.
  final DealCard? givenProperty;

  /// Deal Breaker only: which of the target's complete sets is taken.
  final PropertyColor? takenSetColor;

  /// Debt Collector / It's My Birthday / Rent: how much the target will
  /// owe once this resolves.
  final int? amountOwed;

  final List<ActionCard> justSayNoChain = [];

  PendingAction({
    required this.kind,
    required this.sourceCard,
    required this.sourcePlayerId,
    required this.targetPlayerId,
    this.takenProperty,
    this.givenProperty,
    this.takenSetColor,
    this.amountOwed,
  });

  bool get isCancelled => justSayNoChain.length.isOdd;

  /// Whose turn it is to respond with a Just Say No right now: the target
  /// responds first (chain length 0, 2, 4, ...), then it alternates back
  /// to the original player (chain length 1, 3, 5, ...).
  String get nextResponderId => justSayNoChain.length.isEven ? targetPlayerId : sourcePlayerId;
}

/// A resolved, uncancelled debt: [payerId] owes [payeeId] [amount] (in $M),
/// to be settled with [TurnEngine.resolvePayment].
class PendingPayment {
  final String payerId;
  final String payeeId;
  final int amount;

  PendingPayment({required this.payerId, required this.payeeId, required this.amount});
}
