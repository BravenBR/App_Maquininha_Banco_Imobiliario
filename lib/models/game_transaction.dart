class GameTransaction {
  final String id;
  final String fromPlayerId;
  final String fromPlayerName;
  final String toPlayerId;
  final String toPlayerName;
  final double amount;
  final DateTime timestamp;

  GameTransaction({
    required this.id,
    required this.fromPlayerId,
    required this.fromPlayerName,
    required this.toPlayerId,
    required this.toPlayerName,
    required this.amount,
    required this.timestamp,
  });

  factory GameTransaction.fromJson(Map<String, dynamic> json) {
    return GameTransaction(
      id: json['id'],
      fromPlayerId: json['fromPlayerId'],
      fromPlayerName: json['fromPlayerName'],
      toPlayerId: json['toPlayerId'],
      toPlayerName: json['toPlayerName'],
      amount: (json['amount'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fromPlayerId': fromPlayerId,
      'fromPlayerName': fromPlayerName,
      'toPlayerId': toPlayerId,
      'toPlayerName': toPlayerName,
      'amount': amount,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
