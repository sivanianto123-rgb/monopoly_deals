import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monopoly_deal_engine/monopoly_deal_engine.dart';
import 'package:monopoly_deal_app/src/widgets/card_view.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('renders a money card', (tester) async {
    await tester.pumpWidget(wrap(const CardView(card: MoneyCard(id: 'm1', bankValue: 5))));
    expect(find.text('\$5M'), findsOneWidget);
  });

  testWidgets('renders a property card with its name', (tester) async {
    await tester.pumpWidget(wrap(const CardView(
      card: PropertyCard(id: 'p1', bankValue: 1, name: 'Baltic Avenue', color: PropertyColor.brown),
    )));
    expect(find.text('Baltic Avenue'), findsOneWidget);
  });

  testWidgets('renders an action card with its label', (tester) async {
    await tester.pumpWidget(wrap(const CardView(
      card: ActionCard(id: 'a1', bankValue: 5, type: ActionType.dealBreaker),
    )));
    expect(find.text('Deal Breaker'), findsOneWidget);
  });

  testWidgets('tap triggers onTap callback', (tester) async {
    var tapped = false;
    await tester.pumpWidget(wrap(CardView(
      card: const MoneyCard(id: 'm1', bankValue: 1),
      onTap: () => tapped = true,
    )));
    await tester.tap(find.byType(CardView));
    expect(tapped, isTrue);
  });
}
