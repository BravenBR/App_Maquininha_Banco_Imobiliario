import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Cliente usado por Android e iPhone quando abrem a partida no navegador.
class NetworkService {
  static WebSocketChannel? _channel;
  static StreamSubscription<dynamic>? _subscription;

  static void Function(Map<String, dynamic>)? onDialogEvent;
  static void Function(String)? onConnectionEvent;

  static String? roomCode;

  static bool get isConnected => _channel != null;
  static bool get isHostConnection => false;
  static String? get joinUrl => null;

  static Uri get _socketUri {
    final page = Uri.base;
    return page.replace(
      scheme: page.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws',
      query: null,
      fragment: null,
    );
  }

  static Future<void> startHost(
    String code,
    void Function(Map<String, dynamic>) onMessageReceived,
  ) {
    throw StateError(
      'Para criar uma partida, use o aplicativo do anfitrião no Android.',
    );
  }

  static Future<void> connectAsClient(
    String code,
    void Function(Map<String, dynamic>) onMessageReceived,
  ) async {
    await disconnect();

    final normalizedCode = code.trim().toUpperCase();
    final connected = Completer<void>();
    roomCode = normalizedCode;

    try {
      final channel = WebSocketChannel.connect(_socketUri);
      _channel = channel;
      _subscription = channel.stream.listen(
        (dynamic rawMessage) {
          try {
            final decoded = jsonDecode(rawMessage as String);
            if (decoded is! Map<String, dynamic>) return;

            final transport = decoded['transport'];
            if (transport == 'connected') {
              if (!connected.isCompleted) connected.complete();
              return;
            }
            if (transport == 'error') {
              final message =
                  decoded['message']?.toString() ??
                  'Não foi possível entrar na sala.';
              if (!connected.isCompleted) {
                connected.completeError(StateError(message));
              } else {
                onConnectionEvent?.call(message);
              }
              return;
            }
            if (transport == 'host_disconnected') {
              onConnectionEvent?.call(
                'O anfitrião saiu. A partida foi encerrada.',
              );
              return;
            }

            if (decoded['type'] == 'show_request') {
              onDialogEvent?.call(decoded);
            } else {
              onMessageReceived(decoded);
            }
          } catch (_) {
            // Uma mensagem inválida não pode derrubar a partida.
          }
        },
        onError: (Object error) {
          const message =
              'A conexão com a partida foi perdida. Verifique o Wi-Fi.';
          if (!connected.isCompleted) {
            connected.completeError(StateError(message));
          } else {
            onConnectionEvent?.call(message);
          }
        },
        onDone: () {
          if (!connected.isCompleted) {
            connected.completeError(
              StateError('O anfitrião encerrou a conexão.'),
            );
          }
          _channel = null;
        },
        cancelOnError: false,
      );

      await channel.ready.timeout(const Duration(seconds: 8));
      channel.sink.add(
        jsonEncode(<String, dynamic>{
          'transport': 'register',
          'role': 'client',
          'room': normalizedCode,
        }),
      );
      await connected.future.timeout(const Duration(seconds: 8));
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  static void broadcastMessage(Map<String, dynamic> data) {
    sendMessageToServer(data);
  }

  static void sendMessageToServer(Map<String, dynamic> data) {
    _channel?.sink.add(jsonEncode(data));
  }

  static Future<void> disconnect() async {
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    onDialogEvent = null;
    onConnectionEvent = null;
    await subscription?.cancel();
    await channel?.sink.close();
  }
}
