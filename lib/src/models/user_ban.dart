class FastRelayUserBan {
  const FastRelayUserBan({
    required this.id,
    required this.userId,
    required this.type,
    this.reason,
    this.bannedBy,
    this.expiresAt,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String type;
  final String? reason;
  final String? bannedBy;
  final DateTime? expiresAt;
  final DateTime createdAt;

  factory FastRelayUserBan.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();

    return FastRelayUserBan(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      type: json['type']?.toString() ?? 'hard',
      reason: json['reason']?.toString(),
      bannedBy: json['bannedBy']?.toString(),
      expiresAt: _parseDateTime(json['expiresAt']),
      createdAt: _parseDateTime(json['createdAt']) ?? now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'type': type,
      'reason': reason,
      'bannedBy': bannedBy,
      'expiresAt': expiresAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

DateTime? _parseDateTime(dynamic value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
