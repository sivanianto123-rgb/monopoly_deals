import 'package:flutter/material.dart';
import 'package:monopoly_deal_engine/monopoly_deal_engine.dart';

import '../theme/property_colors.dart';

/// Renders any [DealCard] as a small playing-card-shaped widget, styled
/// distinctly per card kind so a hand reads correctly at a glance, same as
/// the physical cards.
class CardView extends StatelessWidget {
  final DealCard card;
  final bool selected;
  final VoidCallback? onTap;
  static const double width = 92;
  static const double height = 130;

  const CardView({super.key, required this.card, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: width,
        height: height,
        transform: selected ? (Matrix4.identity()..translateByDouble(0.0, -10.0, 0.0, 1.0)) : Matrix4.identity(),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? Colors.amber.shade700 : Colors.black26, width: selected ? 2.5 : 1),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: selected ? 8 : 3, offset: const Offset(1, 2)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return switch (card) {
      MoneyCard c => _MoneyFace(card: c),
      PropertyCard c => _PropertyFace(name: c.name, colors: [c.color], value: c.bankValue),
      PropertyWildCard c => _PropertyFace(
          name: c.isAnyColor ? 'Wild Property' : 'Wild Property',
          colors: c.isAnyColor ? PropertyColor.values : c.eligibleColors.toList(),
          value: c.bankValue,
          isWild: true,
        ),
      RentCard c => _RentFace(card: c),
      ActionCard c => _ActionFace(card: c),
    };
  }
}

Widget _cornerValue(int value, {Color color = Colors.black87}) => Text(
      '\$${value}M',
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
    );

class _MoneyFace extends StatelessWidget {
  final MoneyCard card;
  const _MoneyFace({required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE9F6E9),
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.attach_money, color: Colors.green.shade800, size: 28),
          Text(
            '\$${card.bankValue}M',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green.shade900),
          ),
        ],
      ),
    );
  }
}

class _PropertyFace extends StatelessWidget {
  final String name;
  final List<PropertyColor> colors;
  final int value;
  final bool isWild;

  const _PropertyFace({required this.name, required this.colors, required this.value, this.isWild = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 34,
          child: colors.length == 1
              ? Container(color: propertySwatch[colors.single])
              : Row(children: [for (final c in colors) Expanded(child: Container(color: propertySwatch[c]))]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isWild)
                  Icon(Icons.swap_horiz, size: 16, color: Colors.grey.shade700)
                else
                  const SizedBox.shrink(),
                Text(
                  isWild ? (colors.length == PropertyColor.values.length ? 'Any color' : 'Wild') : name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (value > 0) _cornerValue(value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RentFace extends StatelessWidget {
  final RentCard card;
  const _RentFace({required this.card});

  @override
  Widget build(BuildContext context) {
    final colors = card.isWild ? PropertyColor.values.toList() : card.colors.toList();
    return Container(
      color: const Color(0xFFF3ECD9),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(alignment: Alignment.topRight, child: _cornerValue(card.bankValue)),
          const Spacer(),
          const Center(child: Text('RENT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 3,
            children: [
              for (final c in colors) Container(width: 10, height: 10, decoration: BoxDecoration(color: propertySwatch[c], shape: BoxShape.circle)),
            ],
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _ActionFace extends StatelessWidget {
  final ActionCard card;
  const _ActionFace({required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEDE7F6),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(alignment: Alignment.topRight, child: _cornerValue(card.bankValue)),
          const SizedBox(height: 4),
          Expanded(
            child: Center(
              child: Text(
                actionTypeLabel(card.type),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
