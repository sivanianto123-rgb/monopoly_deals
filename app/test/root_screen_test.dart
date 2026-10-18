import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:monopoly_deal_engine/monopoly_deal_engine.dart';
import 'package:monopoly_deal_app/src/game_client.dart';
import 'package:monopoly_deal_app/src/models/client_view.dart';
import 'package:monopoly_deal_app/src/screens/connect_screen.dart';
import 'package:monopoly_deal_app/src/screens/game_table_screen.dart';
import 'package:monopoly_deal_app/src/screens/lobby_screen.dart';
import 'package:monopoly_deal_app/src/screens/root_screen.dart';

Widget wrap(GameClient client) => ChangeNotifierProvider.value(
      value: client,
      child: const MaterialApp(home: RootScreen()),
    );

void main() {
  testWidgets('shows ConnectScreen before any room is joined', (tester) async {
    await tester.pumpWidget(wrap(GameClient()));
    expect(find.byType(ConnectScreen), findsOneWidget);
    expect(find.byType(LobbyScreen), findsNothing);
    expect(find.byType(GameTableScreen), findsNothing);
  });

  testWidgets('shows LobbyScreen once a room code is set but the game has not started', (tester) async {
    final client = GameClient()
      ..roomCode = 'ABCDE'
      ..myPlayerId = 'p0'
      ..lobbyPlayers = [LobbyPlayer(id: 'p0', name: 'Alice')];
    await tester.pumpWidget(wrap(client));
    expect(find.byType(LobbyScreen), findsOneWidget);
    expect(find.text('ABCDE'), findsOneWidget);
    expect(find.byType(GameTableScreen), findsNothing);
  });

  testWidgets('shows GameTableScreen once gameState arrives', (tester) async {
    final state = startNewGame(playerNames: ['Alice', 'Bob'], allCards: buildFullDeck(), random: Random(2));
    final alice = state.players[0];
    final client = GameClient()
      ..roomCode = 'ABCDE'
      ..myPlayerId = alice.id
      ..gameState = ClientGameState.fromJson(gameStateToJson(state, viewerId: alice.id));

    await tester.pumpWidget(wrap(client));
    expect(find.byType(GameTableScreen), findsOneWidget);
    expect(find.textContaining('Room ABCDE'), findsOneWidget);
  });
}
