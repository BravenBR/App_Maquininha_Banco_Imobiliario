import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/player.dart';
import '../models/game_transaction.dart';
import '../services/network_service.dart';

class GameProvider extends ChangeNotifier {
  final List<Player> _players = [];
  final List<GameTransaction> _transactions = [];

  String? _myPlayerId;
  bool _isHost = false;
  double _startingBalance = 15000;

  List<Player> get players => List<Player>.unmodifiable(_players);
  List<GameTransaction> get transactions =>
      List<GameTransaction>.unmodifiable(_transactions);
  bool get isHost => _isHost;

  Player? get myPlayer {
    try {
      return _players.firstWhere((p) => p.id == _myPlayerId);
    } catch (e) {
      return null;
    }
  }

  Player? get bankPlayer {
    try {
      return _players.firstWhere((p) => p.isBank);
    } catch (e) {
      return null;
    }
  }

  List<Player> get sortedPlayers {
    final list = List<Player>.from(_players);
    final bankIndex = list.indexWhere((p) => p.isBank);
    if (bankIndex == -1) {
      list.sort((a, b) => b.balance.compareTo(a.balance));
      return list;
    }
    final bank = list[bankIndex];
    list.removeWhere((p) => p.isBank);
    list.sort((a, b) => b.balance.compareTo(a.balance));
    return [bank, ...list];
  }

  void initializeGame(String myName, double startingBalance) {
    _isHost = true;
    _startingBalance = startingBalance.isFinite && startingBalance > 0
        ? startingBalance
        : 15000;
    _players.clear();
    _transactions.clear();

    final bank = Player(
      id: 'bank-id-000',
      name: 'Banco Central',
      balance: 999999999,
      isBank: true,
    );
    _players.add(bank);

    final hostId = const Uuid().v4();
    final hostPlayer = Player(
      id: hostId,
      name: myName.trim(),
      balance: _startingBalance,
    );

    _myPlayerId = hostId;
    _players.add(hostPlayer);
    notifyListeners();
  }

  void executeCommand(Map<String, dynamic> command) {
    if (_isHost) {
      processCommandLocally(command);
      NetworkService.broadcastMessage({
        'type': 'sync_state',
        'state': getGameStateJson(),
      });
    } else {
      NetworkService.sendMessageToServer(command);
    }
  }

  void _addSystemLog(String message) {
    _transactions.insert(
      0,
      GameTransaction(
        id: const Uuid().v4(),
        fromPlayerId: 'system',
        fromPlayerName: 'SISTEMA',
        toPlayerId: 'system',
        toPlayerName: message,
        amount: 0,
        timestamp: DateTime.now(),
      ),
    );
  }

  void processCommandLocally(Map<String, dynamic> msg) {
    if (msg['type'] == 'join') {
      final id = msg['id']?.toString() ?? '';
      final name = msg['name']?.toString().trim() ?? '';
      if (id.isEmpty ||
          name.isEmpty ||
          name.length > 30 ||
          _players.any((player) => player.id == id)) {
        return;
      }
      _players.add(Player(id: id, name: name, balance: _startingBalance));
      _addSystemLog('$name entrou na partida.');
    } else if (msg['type'] == 'reconnect') {
      final index = _players.indexWhere(
        (player) => player.id == msg['id'] && !player.isBank,
      );
      if (index != -1) {
        _players[index].status = 'online';
        _addSystemLog('${_players[index].name} retornou à partida.');
      }
    } else if (msg['type'] == 'transfer') {
      final amount = (msg['amount'] as num?)?.toDouble();
      if (amount == null || !amount.isFinite || amount <= 0) return;
      _makeTransaction(
        fromId: msg['fromId']?.toString() ?? '',
        toId: msg['toId']?.toString() ?? '',
        amount: amount,
      );
    } else if (msg['type'] == 'status_change') {
      final status = msg['status']?.toString();
      if (!const <String>{'online', 'offline', 'away'}.contains(status)) return;
      final index = _players.indexWhere(
        (player) => player.id == msg['id'] && !player.isBank,
      );
      if (index != -1) {
        _players[index].status = status!;
        if (status == 'offline') {
          _addSystemLog('${_players[index].name} desconectou.');
        }
      }
    } else if (msg['type'] == 'request_transfer') {
      final amount = (msg['amount'] as num?)?.toDouble();
      final fromId = msg['fromId']?.toString() ?? '';
      final toId = msg['toId']?.toString() ?? '';
      final requester = _players.where((player) => player.id == fromId);
      if (amount == null ||
          !amount.isFinite ||
          amount <= 0 ||
          requester.isEmpty ||
          !_players.any((player) => player.id == toId)) {
        return;
      }
      if (msg['toId'] == 'bank-id-000') {
        _makeTransaction(fromId: 'bank-id-000', toId: fromId, amount: amount);
      } else {
        final requestMsg = {
          'type': 'show_request',
          'fromId': fromId,
          'fromName': requester.first.name,
          'toId': toId,
          'amount': amount,
        };
        NetworkService.broadcastMessage(requestMsg);
        NetworkService.onDialogEvent?.call(requestMsg);
      }
    } else if (msg['type'] == 'get_state') {
      // Comando silencioso: Apenas força o Host a espalhar a atualização no final da função
    }
    notifyListeners();
  }

  bool _makeTransaction({
    required String fromId,
    required String toId,
    required double amount,
  }) {
    if (!amount.isFinite || amount <= 0 || fromId == toId) return false;

    final senderIndex = _players.indexWhere((p) => p.id == fromId);
    final receiverIndex = _players.indexWhere((p) => p.id == toId);

    if (senderIndex == -1 || receiverIndex == -1) return false;

    final sender = _players[senderIndex];
    final receiver = _players[receiverIndex];

    if (!sender.isBank && sender.balance < amount) return false;

    sender.balance -= amount;
    receiver.balance += amount;

    _transactions.insert(
      0,
      GameTransaction(
        id: const Uuid().v4(),
        fromPlayerId: sender.id,
        fromPlayerName: sender.name,
        toPlayerId: receiver.id,
        toPlayerName: receiver.name,
        amount: amount,
        timestamp: DateTime.now(),
      ),
    );
    return true;
  }

  Map<String, dynamic> getGameStateJson() {
    return {
      'players': _players.map((p) => p.toJson()).toList(),
      'transactions': _transactions.map((t) => t.toJson()).toList(),
    };
  }

  void syncGameState(Map<String, dynamic> json) {
    if (json['players'] != null) {
      _players.clear();
      for (var p in json['players']) {
        _players.add(Player.fromJson(p));
      }
    }
    if (json['transactions'] != null) {
      _transactions.clear();
      for (var t in json['transactions']) {
        _transactions.add(GameTransaction.fromJson(t));
      }
    }
    notifyListeners();
  }

  void setMyPlayerId(String id) {
    _myPlayerId = id;
    notifyListeners();
  }

  // ==========================================
  // SISTEMA DE 10 SLOTS DE SAVE
  // ==========================================

  Future<List<String?>> getSaveSlotsInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return List.generate(10, (i) {
      final data = prefs.getString('save_slot_$i');
      if (data == null) return null;
      try {
        final json = jsonDecode(data);
        return json['saveDate'] as String?;
      } catch (e) {
        return "Save Corrompido";
      }
    });
  }

  Future<void> saveGameToSlot(int slotIndex) async {
    final prefs = await SharedPreferences.getInstance();
    final data = getGameStateJson();
    data['hostId'] = _myPlayerId;
    data['startingBalance'] = _startingBalance;

    final now = DateTime.now();
    data['saveDate'] =
        "${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')} às ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    await prefs.setString('save_slot_$slotIndex', jsonEncode(data));
  }

  Future<bool> loadGameFromSlot(int slotIndex) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('save_slot_$slotIndex');

    if (jsonString != null) {
      final data = jsonDecode(jsonString);
      syncGameState(data);

      _myPlayerId = data['hostId'];
      _startingBalance = (data['startingBalance'] as num?)?.toDouble() ?? 15000;
      _isHost = true;

      for (var p in _players) {
        if (!p.isBank && p.id != _myPlayerId) p.status = 'offline';
        if (p.id == _myPlayerId) p.status = 'online';
      }
      notifyListeners();
      return true;
    }
    return false;
  }

  void disconnect() {
    _myPlayerId = null;
    _isHost = false;
    _players.clear();
    _transactions.clear();
    notifyListeners();
  }
}
