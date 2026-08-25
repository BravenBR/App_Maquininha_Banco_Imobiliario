import 'package:banco_imobiliario_app/main.dart';
import 'package:banco_imobiliario_app/providers/game_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('exibe a entrada do aplicativo anfitrião', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<GameProvider>(
        create: (_) => GameProvider(),
        child: const BancoImobiliarioApp(),
      ),
    );

    expect(find.text('Banco de Mesa'), findsOneWidget);
    expect(find.text('Criar partida'), findsOneWidget);
  });

  test('valida e executa transferências no anfitrião', () {
    final provider = GameProvider()..initializeGame('Anfitrião', 15000);
    final hostId = provider.myPlayer!.id;

    provider.processCommandLocally(<String, dynamic>{
      'type': 'join',
      'id': 'jogador-2',
      'name': 'Convidado',
    });
    provider.processCommandLocally(<String, dynamic>{
      'type': 'transfer',
      'fromId': hostId,
      'toId': 'jogador-2',
      'amount': 500,
    });

    expect(provider.myPlayer!.balance, 14500);
    expect(
      provider.players.firstWhere((player) => player.id == 'jogador-2').balance,
      15500,
    );
    expect(provider.transactions.length, 2);

    provider.processCommandLocally(<String, dynamic>{
      'type': 'transfer',
      'fromId': hostId,
      'toId': 'jogador-2',
      'amount': -100,
    });

    expect(provider.myPlayer!.balance, 14500);
    expect(provider.transactions.length, 2);
  });
}
