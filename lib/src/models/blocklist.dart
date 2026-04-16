class FastRelayBlocklist {
  const FastRelayBlocklist({
    required this.id,
    required this.name,
    this.words = const [],
    this.behavior = 'flag',
    this.active = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final List<String> words;
  final String behavior;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory FastRelayBlocklist.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();

    return FastRelayBlocklist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      words: _asStringList(json['words']),
      behavior: json['behavior']?.toString() ?? 'flag',
      active: _readBool(json['active']) ?? true,
      createdAt: _parseDateTime(json['createdAt']) ?? now,
      updatedAt: _parseDateTime(json['updatedAt']) ?? now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'words': words,
      'behavior': behavior,
      'active': active,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

List<String> _asStringList(dynamic value) {
  final entries = value is List ? value : const [];
  return entries.map((entry) => entry.toString()).toList();
}

bool? _readBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final normalized = value.toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
  }
  return null;
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
