class FastRelayUserMute {
  const FastRelayUserMute({
    required this.id,
    this.muterId,
    required this.mutedUserId,
    required this.type,
    this.mutedBy,
    this.expiresAt,
    required this.createdAt,
  });

  final String id;
  final String? muterId;
  final String mutedUserId;
  final String type;
  final String? mutedBy;
  final DateTime? expiresAt;
  final DateTime createdAt;

  factory FastRelayUserMute.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();

    return FastRelayUserMute(
      id: json['id']?.toString() ?? '',
      muterId: json['muterId']?.toString(),
      mutedUserId: json['mutedUserId']?.toString() ?? '',
      type: json['type']?.toString() ?? 'personal',
      mutedBy: json['mutedBy']?.toString(),
      expiresAt: _parseDateTime(json['expiresAt']),
      createdAt: _parseDateTime(json['createdAt']) ?? now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'muterId': muterId,
      'mutedUserId': mutedUserId,
      'type': type,
      'mutedBy': mutedBy,
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
