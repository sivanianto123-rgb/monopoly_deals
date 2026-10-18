import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game_client.dart';

/// First screen: pick a server to connect to, then your name, then create
/// or join a room. Kept as one screen since it's a short, linear form.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _serverController = TextEditingController(text: 'localhost:8080');
  final _nameController = TextEditingController();
  final _roomCodeController = TextEditingController();
  bool _connected = false;

  @override
  void dispose() {
    _serverController.dispose();
    _nameController.dispose();
    _roomCodeController.dispose();
    super.dispose();
  }

  Future<void> _connect(GameClient client) async {
    final address = _serverController.text.trim();
    if (address.isEmpty) return;
    await client.connect(Uri.parse('ws://$address'));
    if (client.status == ConnectionStatus.connected) {
      setState(() => _connected = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = context.watch<GameClient>();

    return Scaffold(
      appBar: AppBar(title: const Text('Monopoly Deal')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_connected) ...[
                  TextField(
                    controller: _serverController,
                    decoration: const InputDecoration(labelText: 'Server address', hintText: 'host:port'),
                  ),
                  const SizedBox(height: 16),
                  if (client.status == ConnectionStatus.failed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text('Could not connect: ${client.connectError}', style: const TextStyle(color: Colors.red)),
                    ),
                  FilledButton(
                    onPressed: client.status == ConnectionStatus.connecting ? null : () => _connect(client),
                    child: client.status == ConnectionStatus.connecting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Connect'),
                  ),
                ] else ...[
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Your name'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  if (client.lastError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(client.lastError!, style: const TextStyle(color: Colors.red)),
                    ),
                  FilledButton(
                    onPressed: () {
                      final name = _nameController.text.trim();
                      if (name.isEmpty) return;
                      client.clearError();
                      client.createRoom(name);
                    },
                    child: const Text('Create room'),
                  ),
                  const SizedBox(height: 24),
                  const Row(children: [
                    Expanded(child: Divider()),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('or')),
                    Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _roomCodeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Room code'),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () {
                      final name = _nameController.text.trim();
                      final code = _roomCodeController.text.trim();
                      if (name.isEmpty || code.isEmpty) return;
                      client.clearError();
                      client.joinRoom(code, name);
                    },
                    child: const Text('Join room'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
