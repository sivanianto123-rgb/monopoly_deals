import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game_client.dart';
import 'connect_screen.dart';
import 'game_table_screen.dart';
import 'lobby_screen.dart';

/// Picks which screen to show from [GameClient]'s current state, instead
/// of pushing routes: the state transitions (not connected -> in lobby ->
/// in game) are strictly linear for this app, so a reactive switch is
/// simpler than managing a Navigator stack for it.
class RootScreen extends StatelessWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final client = context.watch<GameClient>();
    if (client.gameState != null) return const GameTableScreen();
    if (client.roomCode != null) return const LobbyScreen();
    return const ConnectScreen();
  }
}
