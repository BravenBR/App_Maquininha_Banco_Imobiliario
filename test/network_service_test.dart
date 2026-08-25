import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:banco_imobiliario_app/services/network_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('o anfitrião recebe um convidado por WebSocket', () async {
    final receivedCommand = Completer<Map<String, dynamic>>();

    await NetworkService.startHost('ABC123', (message) {
      if (!receivedCommand.isCompleted) receivedCommand.complete(message);
    });
    addTearDown(NetworkService.disconnect);

    expect(NetworkService.joinUrl, contains('?room=ABC123'));

    expect(File('assets/guest_web/index.html').existsSync(), isTrue);

    final socket = await WebSocket.connect('ws://127.0.0.1:8080/ws');
    final messages = StreamIterator<dynamic>(socket);
    addTearDown(() => socket.close());

    socket.add(
      jsonEncode(<String, dynamic>{
        'transport': 'register',
        'role': 'client',
        'room': 'ABC123',
      }),
    );
    expect(await messages.moveNext(), isTrue);
    final connected = jsonDecode(messages.current as String);
    expect(connected['transport'], 'connected');

    socket.add(
      jsonEncode(<String, dynamic>{
        'type': 'join',
        'id': 'convidado-1',
        'name': 'Convidado',
      }),
    );

    final command = await receivedCommand.future.timeout(
      const Duration(seconds: 2),
    );
    expect(command['type'], 'join');
    expect(command['id'], 'convidado-1');
  });
}
