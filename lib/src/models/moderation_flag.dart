class FastRelayModerationFlag {
  const FastRelayModerationFlag({
    required this.id,
    required this.reporterId,
    required this.targetType,
    required this.targetId,
    required this.reason,
    this.description,
    this.status = 'pending',
    this.resolvedBy,
    this.resolvedAt,
    required this.createdAt,
  });

  final String id;
  final String reporterId;
  final String targetType;
  final String targetId;
  final String reason;
  final String? description;
  final String status;
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final DateTime createdAt;

  factory FastRelayModerationFlag.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();

    return FastRelayModerationFlag(
      id: json['id']?.toString() ?? '',
      reporterId: json['reporterId']?.toString() ?? '',
      targetType: json['targetType']?.toString() ?? '',
      targetId: json['targetId']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      description: json['description']?.toString(),
      status: json['status']?.toString() ?? 'pending',
      resolvedBy: json['resolvedBy']?.toString(),
      resolvedAt: _parseDateTime(json['resolvedAt']),
      createdAt: _parseDateTime(json['createdAt']) ?? now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reporterId': reporterId,
      'targetType': targetType,
      'targetId': targetId,
      'reason': reason,
      'description': description,
      'status': status,
      'resolvedBy': resolvedBy,
      'resolvedAt': resolvedAt?.toIso8601String(),
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
