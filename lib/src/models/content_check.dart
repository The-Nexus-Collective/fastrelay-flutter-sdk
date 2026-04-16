class FastRelayContentCheck {
  const FastRelayContentCheck({required this.action, this.matches = const []});

  final String action;
  final List<FastRelayFilterMatch> matches;

  factory FastRelayContentCheck.fromJson(Map<String, dynamic> json) {
    final rawMatches = json['matches'];
    final entries = rawMatches is List ? rawMatches : const [];

    return FastRelayContentCheck(
      action: json['action']?.toString() ?? 'pass',
      matches: entries
          .whereType<Map>()
          .map(
            (entry) => FastRelayFilterMatch.fromJson(
              entry.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'action': action,
      'matches': matches.map((match) => match.toJson()).toList(),
    };
  }
}

class FastRelayFilterMatch {
  const FastRelayFilterMatch({
    required this.ruleType,
    required this.ruleId,
    required this.ruleName,
    required this.behavior,
  });

  final String ruleType;
  final String ruleId;
  final String ruleName;
  final String behavior;

  factory FastRelayFilterMatch.fromJson(Map<String, dynamic> json) {
    return FastRelayFilterMatch(
      ruleType: json['ruleType']?.toString() ?? '',
      ruleId: json['ruleId']?.toString() ?? '',
      ruleName: json['ruleName']?.toString() ?? '',
      behavior: json['behavior']?.toString() ?? 'flag',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ruleType': ruleType,
      'ruleId': ruleId,
      'ruleName': ruleName,
      'behavior': behavior,
    };
  }
}
