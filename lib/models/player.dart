class Player {
  final String id;
  final String name;
  double balance;
  final bool isBank;
  String status; // 'online', 'offline', 'away'

  Player({
    required this.id,
    required this.name,
    required this.balance,
    this.isBank = false,
    this.status = 'online',
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'],
      name: json['name'],
      balance: (json['balance'] as num).toDouble(),
      isBank: json['isBank'] ?? false,
      status: json['status'] ?? 'online',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'balance': balance,
      'isBank': isBank,
      'status': status,
    };
  }
}
