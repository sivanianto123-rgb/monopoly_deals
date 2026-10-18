import 'package:flutter/material.dart';
import 'package:monopoly_deal_engine/monopoly_deal_engine.dart';

import '../models/client_view.dart';
import '../theme/property_colors.dart';
import 'card_view.dart';

/// Small reusable "pick one of N" dialogs/sheets used to gather the extra
/// parameters most action cards need (an opponent, a color, a specific
/// card) before sending a `move` message. Each returns null if the user
/// backs out, so callers can just bail on null at every step.
class Option<T> {
  final String label;
  final T value;
  final IconData? icon;
  Option(this.label, this.value, {this.icon});
}

Future<T?> pickOption<T>(BuildContext context, String title, List<Option<T>> options) {
  return showModalBottomSheet<T>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          for (final o in options)
            ListTile(
              leading: o.icon != null ? Icon(o.icon) : null,
              title: Text(o.label),
              onTap: () => Navigator.of(context).pop(o.value),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<String?> pickOpponent(BuildContext context, List<ClientPlayerView> opponents, {String title = 'Choose a player'}) {
  return pickOption(
    context,
    title,
    [for (final p in opponents) Option('${p.name} (${p.handCount} cards)', p.id, icon: Icons.person)],
  );
}

Future<PropertyColor?> pickColor(BuildContext context, List<PropertyColor> colors, {String title = 'Choose a color'}) {
  return showDialog<PropertyColor>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in colors)
            ActionChip(
              label: Text(propertyColorLabel(c), style: TextStyle(color: propertyForegroundFor(c))),
              backgroundColor: propertySwatch[c],
              onPressed: () => Navigator.of(context).pop(c),
            ),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
    ),
  );
}

Future<DealCard?> pickCard(BuildContext context, List<DealCard> cards, {String title = 'Choose a card'}) {
  return showDialog<DealCard>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final c in cards) CardView(card: c, onTap: () => Navigator.of(context).pop(c))],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String message, {String confirmLabel = 'Confirm'}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(confirmLabel)),
      ],
    ),
  );
  return result ?? false;
}
