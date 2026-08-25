import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../providers/game_provider.dart';
import '../models/player.dart';
import '../services/network_service.dart';

class PlayerDashboard extends StatefulWidget {
  const PlayerDashboard({super.key});

  @override
  State<PlayerDashboard> createState() => _PlayerDashboardState();
}

class _PlayerDashboardState extends State<PlayerDashboard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    NetworkService.onDialogEvent = (mensagem) {
      final myId = context.read<GameProvider>().myPlayer?.id;
      if (mensagem['toId'] == myId) {
        _showIncomingRequestDialog(
          mensagem['fromId'],
          mensagem['fromName'],
          (mensagem['amount'] as num).toDouble(),
        );
      }
    };
    NetworkService.onConnectionEvent = (message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
      );
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NetworkService.onDialogEvent = null;
    NetworkService.onConnectionEvent = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final gameData = context.read<GameProvider>();
    final myPlayer = gameData.myPlayer;
    if (myPlayer == null || myPlayer.isBank) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      gameData.executeCommand({
        'type': 'status_change',
        'id': myPlayer.id,
        'status': 'away',
      });
    } else if (state == AppLifecycleState.resumed) {
      gameData.executeCommand({
        'type': 'status_change',
        'id': myPlayer.id,
        'status': 'online',
      });
      NetworkService.sendMessageToServer({'type': 'get_state'});
    }
  }

  // DIALOGO DE 10 SLOTS PARA SALVAR
  void _showSaveDialog(BuildContext context) async {
    final provider = context.read<GameProvider>();
    final slots = await provider.getSaveSlotsInfo();

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Salvar Jogo'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: 10,
              itemBuilder: (context, index) {
                final slotDate = slots[index];
                final isEmpty = slotDate == null;

                return Card(
                  color: isEmpty ? Colors.grey.shade100 : Colors.indigo.shade50,
                  child: ListTile(
                    leading: Icon(
                      isEmpty ? Icons.save_outlined : Icons.save,
                      color: isEmpty ? Colors.grey : Colors.indigo,
                    ),
                    title: Text('Slot ${index + 1}'),
                    subtitle: Text(
                      isEmpty ? 'Vazio' : 'Sobrescrever: $slotDate',
                    ),
                    onTap: () async {
                      void performSave() async {
                        await provider.saveGameToSlot(index);
                        if (context.mounted) {
                          Navigator.pop(
                            context,
                          ); // Fecha Dialog (se for confirmação)
                          Navigator.pop(context); // Fecha Dialog Principal
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Jogo salvo no Slot ${index + 1}!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      }

                      if (!isEmpty) {
                        showDialog(
                          context: context,
                          builder: (ctxConfirm) => AlertDialog(
                            title: const Text('Atenção'),
                            content: const Text(
                              'Tem certeza que deseja substituir o jogo salvo neste slot?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctxConfirm),
                                child: const Text('Cancelar'),
                              ),
                              ElevatedButton(
                                onPressed: performSave,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                child: const Text(
                                  'Substituir',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        );
                      } else {
                        performSave();
                      }
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  void _showIncomingRequestDialog(
    String fromId,
    String fromName,
    double amount,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pedido de Dinheiro!'),
          content: Text(
            '$fromName está pedindo \$${amount.toStringAsFixed(0)}.\nVocê aceita transferir?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Recusar', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: () {
                final gameData = context.read<GameProvider>();
                if (gameData.myPlayer != null &&
                    gameData.myPlayer!.balance >= amount) {
                  gameData.executeCommand({
                    'type': 'transfer',
                    'fromId': gameData.myPlayer!.id,
                    'toId': fromId,
                    'amount': amount,
                  });
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Saldo Insuficiente!')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text(
                'Aceitar e Pagar',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showActionDialog(
    BuildContext context,
    Player myPlayer,
    List<Player> otherPlayers,
    bool isReceiving,
  ) {
    Player? selectedPlayer;
    final TextEditingController amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                isReceiving ? 'Cobrar / Receber de:' : 'Transferir para:',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Player>(
                    decoration: const InputDecoration(
                      labelText: 'Jogador alvo',
                    ),
                    items: otherPlayers
                        .map(
                          (p) =>
                              DropdownMenuItem(value: p, child: Text(p.name)),
                        )
                        .toList(),
                    onChanged: (val) => setState(() => selectedPlayer = val),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Valor (\$)',
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (selectedPlayer != null &&
                        amountController.text.isNotEmpty) {
                      final amount =
                          double.tryParse(amountController.text) ?? 0;
                      if (amount > 0) {
                        final gameData = context.read<GameProvider>();
                        if (isReceiving) {
                          gameData.executeCommand({
                            'type': 'request_transfer',
                            'fromId': myPlayer.id,
                            'fromName': myPlayer.name,
                            'toId': selectedPlayer!.id,
                            'amount': amount,
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Pedido enviado para ${selectedPlayer!.name}',
                              ),
                            ),
                          );
                        } else {
                          if (myPlayer.balance >= amount) {
                            gameData.executeCommand({
                              'type': 'transfer',
                              'fromId': myPlayer.id,
                              'toId': selectedPlayer!.id,
                              'amount': amount,
                            });
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Saldo Insuficiente!'),
                              ),
                            );
                          }
                        }
                        Navigator.pop(context);
                      }
                    }
                  },
                  child: Text(isReceiving ? 'Pedir Dinheiro' : 'Transferir'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    if (status == 'online') return Colors.green;
    if (status == 'away') return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final gameData = context.watch<GameProvider>();
    final myPlayer = gameData.myPlayer;

    if (myPlayer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final otherPlayers = gameData.players
        .where((p) => p.id != myPlayer.id)
        .toList();
    final isHost = gameData.isHost;
    final joinUrl = NetworkService.joinUrl;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(isHost ? 'Sua Conta (Anfitrião)' : 'Sua Conta'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      drawer: Drawer(
        child: Column(
          children: [
            // CABEÇALHO DA ÁREA VERDE/INDIGO COM O BOTÃO DE SALVAR DENTRO
            Container(
              width: double.infinity,
              color: Colors.green.shade700,
              // Usa o padding seguro do topo do celular para não encostar na barra de bateria/relógio
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                right: 16,
                bottom: 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // O BOTÃO DE SALVAR AGORA FICA AQUI, DESTACADO!
                  ElevatedButton.icon(
                    onPressed: () {
                      if (isHost) {
                        _showSaveDialog(context);
                      } else {
                        Navigator.pop(
                          context,
                        ); // Fecha o drawer antes de dar o aviso
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Apenas o Anfitrião (Host) pode salvar a partida!',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    icon: Icon(Icons.save, color: Colors.green.shade700),
                    label: Text(
                      'Salvar Jogo',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Menu da Partida',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (joinUrl != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                      child: Column(
                        children: [
                          const Text(
                            'Entrada da partida',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          QrImageView(
                            data: joinUrl,
                            version: QrVersions.auto,
                            size: 140.0,
                            backgroundColor: Colors.white,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Código: ${NetworkService.roomCode}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: joinUrl),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Link copiado.')),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('Copiar link'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(thickness: 1),
                  ],

                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(Icons.leaderboard, color: Colors.black54),
                        SizedBox(width: 8),
                        Text(
                          'Ranking',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),

                  ...gameData.sortedPlayers.map(
                    (p) => ListTile(
                      leading: Icon(
                        Icons.circle,
                        size: 16,
                        color: _getStatusColor(p.status),
                      ),
                      title: Text(
                        p.name,
                        style: TextStyle(
                          fontWeight: p.id == myPlayer.id
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        p.status == 'online'
                            ? 'Online'
                            : (p.status == 'away' ? 'Ausente' : 'Offline'),
                      ),
                      trailing: Text(
                        p.isBank ? '∞' : '\$${p.balance.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SafeArea(
              bottom: true,
              child: Container(
                color: Colors.red.shade50,
                child: ListTile(
                  leading: const Icon(Icons.exit_to_app, color: Colors.red),
                  title: const Text(
                    'Sair',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () {
                    gameData.executeCommand({
                      'type': 'status_change',
                      'id': myPlayer.id,
                      'status': 'offline',
                    });
                    NetworkService.disconnect();
                    gameData.disconnect();
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            color: Colors.green.shade700,
            width: double.infinity,
            child: Column(
              children: [
                Text(
                  myPlayer.name,
                  style: const TextStyle(color: Colors.white70, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  '\$ ${myPlayer.balance.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showActionDialog(
                      context,
                      myPlayer,
                      otherPlayers,
                      true,
                    ),
                    icon: const Icon(Icons.download),
                    label: const Text('COBRAR'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      backgroundColor: Colors.amber.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showActionDialog(
                      context,
                      myPlayer,
                      otherPlayers,
                      false,
                    ),
                    icon: const Icon(Icons.send),
                    label: const Text('TRANSFERIR'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(thickness: 2),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              'Extrato Público',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: gameData.transactions.length,
              itemBuilder: (context, index) {
                final tx = gameData.transactions[index];
                final horaTransacao =
                    '${tx.timestamp.hour.toString().padLeft(2, '0')}:${tx.timestamp.minute.toString().padLeft(2, '0')}';

                if (tx.fromPlayerId == 'system') {
                  return ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.blueGrey,
                      child: Icon(Icons.info_outline, color: Colors.white),
                    ),
                    title: Text(
                      tx.toPlayerName,
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.black87,
                      ),
                    ),
                    subtitle: Text(
                      horaTransacao,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  );
                }

                final isMe = tx.fromPlayerId == myPlayer.id;
                final isForMe = tx.toPlayerId == myPlayer.id;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isMe
                        ? Colors.red.shade100
                        : (isForMe
                              ? Colors.green.shade100
                              : Colors.grey.shade300),
                    child: Icon(
                      isMe
                          ? Icons.arrow_upward
                          : (isForMe ? Icons.arrow_downward : Icons.swap_horiz),
                      color: isMe
                          ? Colors.red
                          : (isForMe ? Colors.green : Colors.grey),
                    ),
                  ),
                  title: Text('${tx.fromPlayerName} ➡️ ${tx.toPlayerName}'),
                  subtitle: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '\$ ${tx.amount.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isMe
                              ? Colors.red
                              : (isForMe ? Colors.green : Colors.black87),
                        ),
                      ),
                      Text(
                        horaTransacao,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
