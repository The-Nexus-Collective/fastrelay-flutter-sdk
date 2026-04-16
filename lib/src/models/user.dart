class FastRelayUser {
  const FastRelayUser({
    required this.id,
    this.displayName,
    this.profileData,
    this.role,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? displayName;
  final Map<String, dynamic>? profileData;
  final String? role;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get initials {
    final label = (displayName == null || displayName!.trim().isEmpty)
        ? id
        : displayName!.trim();

    if (label.isEmpty) {
      return '?';
    }

    final parts = label
        .split(RegExp(r'\s+'))
        .where((value) => value.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  factory FastRelayUser.fromJson(Map<String, dynamic> json) {
    final profileData = _asMap(json['profileData']);
    final now = DateTime.now().toUtc();

    return FastRelayUser(
      id: json['id']?.toString() ?? '',
      displayName: json['displayName']?.toString(),
      profileData: profileData.isEmpty ? null : profileData,
      role: json['role']?.toString(),
      createdAt: _parseDateTime(json['createdAt']) ?? now,
      updatedAt: _parseDateTime(json['updatedAt']) ?? now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'profileData': profileData,
      'role': role,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
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
