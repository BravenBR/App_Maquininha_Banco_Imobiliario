import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../providers/game_provider.dart';
import '../services/network_service.dart';
import 'player_dashboard.dart';

class ClientJoinScreen extends StatefulWidget {
  final String? initialRoomCode;

  const ClientJoinScreen({super.key, this.initialRoomCode});

  @override
  State<ClientJoinScreen> createState() => _ClientJoinScreenState();
}

class _ClientJoinScreenState extends State<ClientJoinScreen> {
  late final TextEditingController _roomController;
  final TextEditingController _nameController = TextEditingController();

  bool _isConnected = false;
  bool _isConnecting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _roomController = TextEditingController(
      text: widget.initialRoomCode?.trim().toUpperCase() ?? '',
    );
    if (_roomController.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _connectToRoom());
    }
  }

  @override
  void dispose() {
    _roomController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _connectToRoom() async {
    final room = _roomController.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(room)) {
      setState(() => _errorMessage = 'Digite o código de 6 caracteres.');
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    final provider = context.read<GameProvider>();
    try {
      await NetworkService.connectAsClient(room, (message) {
        if (message['type'] == 'sync_state') {
          final state = message['state'];
          if (state is Map<String, dynamic>) provider.syncGameState(state);
        }
      });
      NetworkService.sendMessageToServer(<String, dynamic>{
        'type': 'get_state',
      });
      if (mounted) {
        setState(() {
          _isConnected = true;
          _isConnecting = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _errorMessage = error
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('TimeoutException: ', '');
      });
    }
  }

  void _joinAsNewPlayer() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Digite seu nome para entrar.');
      return;
    }

    final playerId = const Uuid().v4();
    context.read<GameProvider>().setMyPlayerId(playerId);
    NetworkService.sendMessageToServer(<String, dynamic>{
      'type': 'join',
      'id': playerId,
      'name': name,
    });
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(builder: (_) => const PlayerDashboard()),
    );
  }

  void _reconnectPlayer(String id) {
    context.read<GameProvider>().setMyPlayerId(id);
    NetworkService.sendMessageToServer(<String, dynamic>{
      'type': 'reconnect',
      'id': id,
    });
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(builder: (_) => const PlayerDashboard()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar na partida')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _isConnected
                    ? _buildPlayerSelection()
                    : _buildRoomConnection(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoomConnection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Icon(
          Icons.meeting_room_outlined,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Entre com o código da sala',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Se você abriu o link do QR Code, o código já está preenchido.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _roomController,
          autofocus: widget.initialRoomCode == null,
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _connectToRoom(),
          decoration: const InputDecoration(
            labelText: 'Código da sala',
            hintText: 'ABC123',
            prefixIcon: Icon(Icons.tag_rounded),
          ),
        ),
        if (_errorMessage != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _isConnecting ? null : _connectToRoom,
          icon: _isConnecting
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.login_rounded),
          label: Text(_isConnecting ? 'Conectando…' : 'Localizar partida'),
        ),
      ],
    );
  }

  Widget _buildPlayerSelection() {
    final offlinePlayers = context
        .watch<GameProvider>()
        .players
        .where((player) => player.status == 'offline' && !player.isBank)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Icon(
          Icons.check_circle_rounded,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text(
          'Sala encontrada',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (offlinePlayers.isNotEmpty) ...<Widget>[
          const SizedBox(height: 24),
          const Text('Reconectar um jogador:'),
          const SizedBox(height: 8),
          ...offlinePlayers.map(
            (player) => Card.outlined(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(player.name),
                subtitle: Text('\$ ${player.balance.toStringAsFixed(0)}'),
                trailing: const Icon(Icons.login_rounded),
                onTap: () => _reconnectPlayer(player.id),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: <Widget>[
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('OU'),
                ),
                Expanded(child: Divider()),
              ],
            ),
          ),
        ] else
          const SizedBox(height: 24),
        TextField(
          controller: _nameController,
          autofocus: true,
          maxLength: 30,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _joinAsNewPlayer(),
          decoration: const InputDecoration(
            labelText: 'Seu nome',
            prefixIcon: Icon(Icons.person_add_alt_1_outlined),
          ),
        ),
        if (_errorMessage != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _joinAsNewPlayer,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('Entrar como novo jogador'),
        ),
      ],
    );
  }
}
