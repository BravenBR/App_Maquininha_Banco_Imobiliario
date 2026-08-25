import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Servidor local executado somente pelo aplicativo Android do anfitrião.
class NetworkService {
  static const int _port = 8080;
  static const int _maxClients = 20;
  static const String _webAssetRoot = 'assets/guest_web';

  static HttpServer? _server;
  static final Set<_ClientSession> _clients = <_ClientSession>{};
  static void Function(Map<String, dynamic>)? _onMessageReceived;
  static String? _hostIp;

  static void Function(Map<String, dynamic>)? onDialogEvent;
  static void Function(String)? onConnectionEvent;

  static String? roomCode;

  static bool get isConnected => _server != null;
  static bool get isHostConnection => _server != null;

  static String? get joinUrl {
    final ip = _hostIp;
    final code = roomCode;
    if (ip == null || code == null) return null;
    return 'http://$ip:$_port/?room=$code';
  }

  static Future<void> startHost(
    String code,
    void Function(Map<String, dynamic>) onMessageReceived,
  ) async {
    await disconnect();

    final normalizedCode = code.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(normalizedCode)) {
      throw StateError('Código de sala inválido.');
    }

    final ip = await _findWifiIpv4();
    if (ip == null) {
      throw StateError(
        'Não foi possível localizar o Wi-Fi. Conecte o celular a uma rede local.',
      );
    }

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
    } on SocketException {
      throw StateError(
        'A porta $_port já está em uso. Feche outra partida e tente novamente.',
      );
    }

    _hostIp = ip;
    roomCode = normalizedCode;
    _onMessageReceived = onMessageReceived;
    _server!.autoCompress = true;
    _server!.listen(
      (request) => unawaited(_handleRequest(request)),
      onError: (_) => onConnectionEvent?.call(
        'O servidor local foi interrompido. Reinicie a partida.',
      ),
    );
  }

  static Future<void> connectAsClient(
    String code,
    void Function(Map<String, dynamic>) onMessageReceived,
  ) {
    throw StateError(
      'O aplicativo Android funciona como anfitrião. '
      'Para participar, abra o QR Code no navegador.',
    );
  }

  static void broadcastMessage(Map<String, dynamic> data) {
    final message = jsonEncode(data);
    for (final client in _clients.toList()) {
      _safeSend(client.socket, message);
    }
  }

  static void sendMessageToServer(Map<String, dynamic> data) {
    // O anfitrião processa seus próprios comandos no GameProvider.
    if (_server != null) broadcastMessage(data);
  }

  static Future<void> disconnect() async {
    final server = _server;
    _server = null;
    _onMessageReceived = null;
    _hostIp = null;
    roomCode = null;
    onDialogEvent = null;
    onConnectionEvent = null;

    for (final client in _clients.toList()) {
      client.closedByHost = true;
      await client.socket.close(
        WebSocketStatus.goingAway,
        'Partida encerrada pelo anfitrião.',
      );
    }
    _clients.clear();
    await server?.close(force: true);
  }

  static Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.uri.path == '/ws') {
        if (!WebSocketTransformer.isUpgradeRequest(request)) {
          request.response.statusCode = HttpStatus.upgradeRequired;
          await request.response.close();
          return;
        }
        if (_clients.length >= _maxClients) {
          request.response
            ..statusCode = HttpStatus.serviceUnavailable
            ..write('A sala atingiu o limite de participantes.');
          await request.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        _handleClient(socket);
        return;
      }

      await _serveWebAsset(request);
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {
        // A resposta já foi encerrada.
      }
    }
  }

  static void _handleClient(WebSocket socket) {
    final session = _ClientSession(socket);

    socket.listen(
      (dynamic rawMessage) {
        if (rawMessage is! String || rawMessage.length > 65536) return;

        Map<String, dynamic> message;
        try {
          final decoded = jsonDecode(rawMessage);
          if (decoded is! Map<String, dynamic>) return;
          message = decoded;
        } catch (_) {
          return;
        }

        if (!session.registered) {
          _registerClient(session, message);
          return;
        }
        if (message.containsKey('transport')) return;
        if (!_validateClientCommand(session, message)) return;

        if (message['type'] == 'status_change' &&
            message['status'] == 'offline') {
          session.sentOffline = true;
        }
        _onMessageReceived?.call(message);
      },
      onDone: () => _removeClient(session),
      onError: (_) => _removeClient(session),
      cancelOnError: true,
    );
  }

  static void _registerClient(
    _ClientSession session,
    Map<String, dynamic> message,
  ) {
    final code = message['room']?.toString().trim().toUpperCase();
    if (message['transport'] != 'register' ||
        message['role'] != 'client' ||
        code != roomCode) {
      _sendError(
        session.socket,
        'Sala não encontrada. Confirme o QR Code com o anfitrião.',
      );
      return;
    }

    session.registered = true;
    _clients.add(session);
    _safeSend(
      session.socket,
      jsonEncode(<String, dynamic>{'transport': 'connected', 'room': roomCode}),
    );
  }

  static bool _validateClientCommand(
    _ClientSession session,
    Map<String, dynamic> message,
  ) {
    final type = message['type']?.toString();
    if (type == 'get_state') return true;

    if (type == 'join') {
      if (session.playerId != null) return false;
      final id = message['id']?.toString() ?? '';
      final name = message['name']?.toString().trim() ?? '';
      if (id.isEmpty || name.isEmpty || name.length > 30) return false;
      session.playerId = id;
      return true;
    }

    if (type == 'reconnect') {
      if (session.playerId != null) return false;
      final id = message['id']?.toString() ?? '';
      if (id.isEmpty) return false;
      session.playerId = id;
      return true;
    }

    final playerId = session.playerId;
    if (playerId == null) return false;

    if (type == 'transfer' || type == 'request_transfer') {
      return message['fromId'] == playerId &&
          _isPositiveAmount(message['amount']);
    }
    if (type == 'status_change') {
      return message['id'] == playerId &&
          const <String>{
            'online',
            'offline',
            'away',
          }.contains(message['status']);
    }
    return false;
  }

  static bool _isPositiveAmount(Object? value) {
    if (value is! num) return false;
    final amount = value.toDouble();
    return amount.isFinite && amount > 0;
  }

  static void _removeClient(_ClientSession session) {
    if (!_clients.remove(session) || session.closedByHost) return;
    final playerId = session.playerId;
    if (playerId != null && !session.sentOffline) {
      _onMessageReceived?.call(<String, dynamic>{
        'type': 'status_change',
        'id': playerId,
        'status': 'offline',
      });
    }
  }

  static void _sendError(WebSocket socket, String message) {
    _safeSend(
      socket,
      jsonEncode(<String, dynamic>{'transport': 'error', 'message': message}),
    );
    unawaited(socket.close(WebSocketStatus.policyViolation, message));
  }

  static void _safeSend(WebSocket socket, String message) {
    if (socket.readyState == WebSocket.open) socket.add(message);
  }

  static Future<void> _serveWebAsset(HttpRequest request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await request.response.close();
      return;
    }

    var path = Uri.decodeComponent(request.uri.path);
    if (path == '/' || path.isEmpty) path = '/index.html';
    if (path.contains('..') || path.contains(r'\')) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    Uint8List bytes;
    var fileName = path.substring(1);
    try {
      final data = await rootBundle.load('$_webAssetRoot/$fileName');
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      if (fileName.contains('.')) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      fileName = 'index.html';
      final data = await rootBundle.load('$_webAssetRoot/index.html');
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }

    request.response.headers.contentType = _contentType(fileName);
    request.response.contentLength = bytes.length;
    if (fileName == 'index.html' || fileName == 'flutter_service_worker.js') {
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    } else {
      request.response.headers.set(
        HttpHeaders.cacheControlHeader,
        'public, max-age=86400',
      );
    }
    if (request.method != 'HEAD') request.response.add(bytes);
    await request.response.close();
  }

  static ContentType _contentType(String fileName) {
    final extension = fileName.contains('.')
        ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase()
        : '';
    return switch (extension) {
      'html' => ContentType.html,
      'js' => ContentType('text', 'javascript', charset: 'utf-8'),
      'css' => ContentType('text', 'css', charset: 'utf-8'),
      'json' || 'map' => ContentType.json,
      'png' => ContentType('image', 'png'),
      'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
      'svg' => ContentType('image', 'svg+xml'),
      'ico' => ContentType('image', 'x-icon'),
      'wasm' => ContentType('application', 'wasm'),
      'woff2' => ContentType('font', 'woff2'),
      _ => ContentType.binary,
    };
  }

  static Future<String?> _findWifiIpv4() async {
    try {
      final preferred = <String>[];
      final fallback = <String>[];
      for (final interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      )) {
        for (final address in interface.addresses) {
          if (address.isLoopback) continue;
          if (_isPrivateIpv4(address.address)) {
            if (RegExp(
              r'wlan|wifi|wi-fi',
              caseSensitive: false,
            ).hasMatch(interface.name)) {
              preferred.add(address.address);
            } else {
              fallback.add(address.address);
            }
          }
        }
      }
      if (preferred.isNotEmpty) return preferred.first;
      if (fallback.isNotEmpty) return fallback.first;
    } catch (_) {
      return null;
    }
    return null;
  }

  static bool _isPrivateIpv4(String address) {
    final parts = address.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    final first = parts[0]!;
    final second = parts[1]!;
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }
}

class _ClientSession {
  final WebSocket socket;
  bool registered = false;
  bool sentOffline = false;
  bool closedByHost = false;
  String? playerId;

  _ClientSession(this.socket);
}
