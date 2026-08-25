import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../providers/game_provider.dart';
import '../services/network_service.dart';
import 'player_dashboard.dart';

class HostLobbyScreen extends StatefulWidget {
  final int? loadedSlotIndex;

  const HostLobbyScreen({super.key, this.loadedSlotIndex});

  @override
  State<HostLobbyScreen> createState() => _HostLobbyScreenState();
}

class _HostLobbyScreenState extends State<HostLobbyScreen> {
  bool _isInitializing = false;
  String? _errorMessage;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _balanceController = TextEditingController(
    text: '15000',
  );

  @override
  void initState() {
    super.initState();
    if (widget.loadedSlotIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startRoom(fromLoad: true);
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  String _newRoomCode() {
    return const Uuid().v4().replaceAll('-', '').substring(0, 6).toUpperCase();
  }

  Future<void> _startRoom({bool fromLoad = false}) async {
    final name = _nameController.text.trim();
    final balance = double.tryParse(
      _balanceController.text.replaceAll(',', '.'),
    );

    if (!fromLoad && (name.isEmpty || balance == null || balance <= 0)) {
      setState(() {
        _errorMessage = 'Informe seu nome e um saldo inicial válido.';
      });
      return;
    }

    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    final provider = context.read<GameProvider>();
    if (!fromLoad) provider.initializeGame(name, balance!);

    try {
      await NetworkService.startHost(_newRoomCode(), (message) {
        provider.processCommandLocally(message);
        NetworkService.broadcastMessage(<String, dynamic>{
          'type': 'sync_state',
          'state': provider.getGameStateJson(),
        });
      });

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(builder: (_) => const PlayerDashboard()),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _errorMessage = error
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('TimeoutException: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Criar partida')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _isInitializing
                    ? const _StartingRoom()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Icon(
                            Icons.wifi_tethering_rounded,
                            size: 64,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Você será o anfitrião',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Mantenha esta página aberta durante a partida. '
                            'Os demais jogadores entram pelo QR Code.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 28),
                          TextField(
                            controller: _nameController,
                            textInputAction: TextInputAction.next,
                            maxLength: 30,
                            decoration: const InputDecoration(
                              labelText: 'Seu nome',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _balanceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onSubmitted: (_) => _startRoom(),
                            decoration: const InputDecoration(
                              labelText: 'Saldo inicial de cada jogador',
                              prefixIcon: Icon(Icons.payments_outlined),
                            ),
                          ),
                          if (_errorMessage != null) ...<Widget>[
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _startRoom,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Iniciar partida'),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StartingRoom extends StatelessWidget {
  const _StartingRoom();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: <Widget>[
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text('Preparando a sala na rede local…', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
