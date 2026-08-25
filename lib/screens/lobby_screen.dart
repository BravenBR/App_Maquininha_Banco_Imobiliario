import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../providers/game_provider.dart';
import 'client_join_screen.dart';
import 'host_lobby_screen.dart';

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key});

  Future<void> _showLoadDialog(BuildContext context) async {
    final provider = context.read<GameProvider>();
    final slots = await provider.getSaveSlotsInfo();
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Carregar partida'),
        content: SizedBox(
          width: 480,
          height: 420,
          child: ListView.separated(
            itemCount: slots.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final saveDate = slots[index];
              return Card.outlined(
                child: ListTile(
                  enabled: saveDate != null,
                  leading: Icon(
                    saveDate == null
                        ? Icons.inventory_2_outlined
                        : Icons.history_rounded,
                  ),
                  title: Text('Espaço ${index + 1}'),
                  subtitle: Text(saveDate ?? 'Vazio'),
                  onTap: saveDate == null
                      ? null
                      : () async {
                          final loaded = await provider.loadGameFromSlot(index);
                          if (!dialogContext.mounted || !loaded) return;
                          Navigator.pop(dialogContext);
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  HostLobbyScreen(loadedSlotIndex: index),
                            ),
                          );
                        },
                ),
              );
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: <Widget>[
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x330B6B3A),
                          blurRadius: 24,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.account_balance_rounded,
                      size: 52,
                      color: colors.onPrimary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Banco de Mesa',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Dinheiro do jogo sincronizado entre Android e iPhone, '
                    'direto pelo navegador.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 36),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 620;
                      final actions = <Widget>[
                        if (!kIsWeb)
                          _LobbyAction(
                            icon: Icons.add_circle_outline_rounded,
                            title: 'Criar partida',
                            subtitle: 'Hospede no Android e mostre o QR Code',
                            filled: true,
                            onTap: () => Navigator.push<void>(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => const HostLobbyScreen(),
                              ),
                            ),
                          )
                        else
                          _LobbyAction(
                            icon: Icons.login_rounded,
                            title: 'Entrar na partida',
                            subtitle: 'Use o link ou código do anfitrião',
                            filled: true,
                            onTap: () => Navigator.push<void>(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => const ClientJoinScreen(),
                              ),
                            ),
                          ),
                      ];

                      return compact || actions.length == 1
                          ? Column(children: <Widget>[actions[0]])
                          : Row(
                              children: <Widget>[
                                Expanded(child: actions[0]),
                                const SizedBox(width: 16),
                                Expanded(child: actions[1]),
                              ],
                            );
                    },
                  ),
                  const SizedBox(height: 16),
                  if (!kIsWeb)
                    TextButton.icon(
                      onPressed: () => _showLoadDialog(context),
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('Carregar uma partida salva'),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        Icons.wifi_rounded,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          kIsWeb
                              ? 'Use o QR Code exibido pelo anfitrião Android'
                              : 'Os participantes devem estar no mesmo Wi-Fi',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LobbyAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool filled;
  final VoidCallback onTap;

  const _LobbyAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: filled ? colors.primary : colors.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 164,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: filled ? null : Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                icon,
                size: 34,
                color: filled ? colors.onPrimary : colors.primary,
              ),
              const Spacer(),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: filled ? colors.onPrimary : colors.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: filled
                      ? colors.onPrimary.withValues(alpha: 0.8)
                      : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
