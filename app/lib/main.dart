import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/game_client.dart';
import 'src/screens/root_screen.dart';

void main() {
  runApp(const MonopolyDealApp());
}

class MonopolyDealApp extends StatelessWidget {
  const MonopolyDealApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => GameClient(),
      child: MaterialApp(
        title: 'Monopoly Deal',
        theme: ThemeData(colorSchemeSeed: const Color(0xFF1FA858), useMaterial3: true),
        home: const RootScreen(),
      ),
    );
  }
}
