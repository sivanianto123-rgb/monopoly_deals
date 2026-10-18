import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game_client.dart';

/// Shown once a room has been created/joined but the game hasn't started.
class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final client = context.watch<GameClient>();
    final canStart = client.lobbyPlayers.length >= 2 && client.lobbyPlayers.length <= 5;

    return Scaffold(
      appBar: AppBar(title: Text('Room ${client.roomCode}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(
                  client.roomCode ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 4),
                ),
                const SizedBox(height: 4),
                const Text('Share this code with the other players', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final p in client.lobbyPlayers)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.person),
                            title: Text(p.name),
                            trailing: p.id == client.myPlayerId ? const Text('(you)') : null,
                          ),
                        if (client.lobbyPlayers.isEmpty)
                          const Padding(padding: EdgeInsets.all(16), child: Text('Waiting for players...')),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (client.lastError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(client.lastError!, style: const TextStyle(color: Colors.red)),
                  ),
                FilledButton(
                  onPressed: canStart ? client.startGame : null,
                  child: Text(canStart ? 'Start game' : 'Need 2-5 players'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
