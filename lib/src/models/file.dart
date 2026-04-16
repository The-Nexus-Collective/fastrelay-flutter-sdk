class FastRelayFile {
  const FastRelayFile({
    required this.id,
    required this.url,
    required this.type,
    required this.mimeType,
    required this.size,
    this.metadata = const {},
    required this.createdAt,
  });

  final String id;
  final String url;
  final String type;
  final String mimeType;
  final int size;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  factory FastRelayFile.fromJson(Map<String, dynamic> json) {
    final metadata = _asMap(json['metadata']);
    return FastRelayFile(
      id: json['id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      type: json['type']?.toString() ?? 'file',
      mimeType: json['mimeType']?.toString() ?? 'application/octet-stream',
      size: _readInt(json['size']) ?? 0,
      metadata: metadata,
      createdAt:
          _parseDateTime(json['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'type': type,
      'mimeType': mimeType,
      'size': size,
      'metadata': metadata,
      'createdAt': createdAt.toIso8601String(),
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

int? _readInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
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
