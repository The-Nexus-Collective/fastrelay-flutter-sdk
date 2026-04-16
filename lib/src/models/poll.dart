class FastRelayPollOption {
  const FastRelayPollOption({
    required this.id,
    required this.text,
    this.voteCount = 0,
  });

  final String id;
  final String text;
  final int voteCount;

  factory FastRelayPollOption.fromJson(Map<String, dynamic> json) {
    return FastRelayPollOption(
      id: json['id']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      voteCount: _readInt(json['voteCount']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'text': text, 'voteCount': voteCount};
  }
}

class FastRelayPoll {
  const FastRelayPoll({
    required this.id,
    required this.question,
    this.options = const [],
    this.totalVotes = 0,
    this.userVote,
    this.expiresAt,
    this.isClosed = false,
  });

  final String id;
  final String question;
  final List<FastRelayPollOption> options;
  final int totalVotes;
  final String? userVote;
  final DateTime? expiresAt;
  final bool isClosed;

  bool get hasVoted => userVote != null && userVote!.isNotEmpty;

  factory FastRelayPoll.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    final options = rawOptions is List
        ? rawOptions
              .whereType<Map>()
              .map(
                (entry) => FastRelayPollOption.fromJson(
                  entry.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .toList()
        : const <FastRelayPollOption>[];

    return FastRelayPoll(
      id: json['id']?.toString() ?? '',
      question: json['question']?.toString() ?? '',
      options: options,
      totalVotes: _readInt(json['totalVotes']) ?? 0,
      userVote: _parseUserVote(json['userVote']),
      expiresAt: _parseDateTime(json['expiresAt']),
      isClosed: _readBool(json['isClosed']) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'question': question,
      'options': options.map((option) => option.toJson()).toList(),
      'totalVotes': totalVotes,
      'userVote': userVote,
      'expiresAt': expiresAt?.toIso8601String(),
      'isClosed': isClosed,
    };
  }
}

String? _parseUserVote(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is Map) {
    final map = value.map((key, item) => MapEntry(key.toString(), item));
    return _parseUserVote(map['optionId'] ?? map['option_id'] ?? map['id']);
  }
  if (value is List && value.isNotEmpty) {
    return _parseUserVote(value.first);
  }
  return null;
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
