import 'dart:convert';

typedef JsonMap = Map<String, dynamic>;

String toSnakeKey(String key) {
  return key.replaceAllMapped(
    RegExp(r'([A-Z])'),
    (match) => '_${match.group(1)!.toLowerCase()}',
  );
}

String toCamelKey(String key) {
  return key.replaceAllMapped(
    RegExp(r'_([a-z])'),
    (match) => match.group(1)!.toUpperCase(),
  );
}

dynamic toSnakeCaseDeep(dynamic value) {
  if (value is DateTime) {
    return value.toIso8601String();
  }
  if (value is List) {
    return value.map(toSnakeCaseDeep).toList();
  }
  if (value is Map) {
    final output = <String, dynamic>{};
    for (final entry in value.entries) {
      output[toSnakeKey(entry.key.toString())] = toSnakeCaseDeep(entry.value);
    }
    return output;
  }
  return value;
}

dynamic toCamelCaseDeep(dynamic value) {
  if (value is List) {
    return value.map(toCamelCaseDeep).toList();
  }
  if (value is Map) {
    final output = <String, dynamic>{};
    for (final entry in value.entries) {
      output[toCamelKey(entry.key.toString())] = toCamelCaseDeep(entry.value);
    }
    return output;
  }
  return value;
}

Uri toAbsoluteUrl(String baseUrl, String path, [Map<String, dynamic>? query]) {
  final normalizedBase = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
  final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
  final uri = Uri.parse(normalizedBase).resolve(normalizedPath);

  if (query == null || query.isEmpty) {
    return uri;
  }

  final parts = <String>[];
  for (final entry in query.entries) {
    final value = entry.value;
    if (value == null) {
      continue;
    }

    if (value is Iterable && value is! String) {
      for (final item in value) {
        if (item != null) {
          parts.add(
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent('$item')}',
          );
        }
      }
      continue;
    }

    parts.add(
      '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent('$value')}',
    );
  }

  if (parts.isEmpty) {
    return uri;
  }

  final separator = uri.hasQuery ? '&' : '?';
  return Uri.parse('${uri.toString()}$separator${parts.join('&')}');
}

Map<String, dynamic> buildFeedActivityQuery([Map<String, dynamic>? options]) {
  if (options == null || options.isEmpty) {
    return const {};
  }

  final query = <String, dynamic>{};

  if (options.containsKey('limit')) {
    query['limit'] = options['limit'];
  }
  if (options.containsKey('cursor')) {
    query['cursor'] = options['cursor'];
  }
  if (options.containsKey('view')) {
    query['view'] = options['view'];
  }
  if (options.containsKey('markSeen')) {
    query['mark_seen'] = options['markSeen'];
  }

  if (options.containsKey('markRead')) {
    final markRead = options['markRead'];
    if (markRead is Iterable && markRead is! String) {
      query['mark_read'] = markRead.join(',');
    } else {
      query['mark_read'] = markRead;
    }
  }

  final filter = options['filter'];
  if (filter is Map) {
    for (final entry in filter.entries) {
      query['filter[${entry.key}]'] = entry.value;
    }
  }

  return query;
}

String encodeBasicAuth(String username, String password) {
  return base64Encode(utf8.encode('$username:$password'));
}

String resolveFeedTarget(Object? target) {
  if (target is String && target.isNotEmpty) {
    return target;
  }

  if (target is Map) {
    final group = target['group'];
    final id = target['id'];
    if (group is String && group.isNotEmpty && id is String && id.isNotEmpty) {
      return '$group:$id';
    }
  }

  throw ArgumentError(
    "target must be a feed string like 'user:john' or {group, id}.",
  );
}

(String group, String id) splitFeedId(String feedId) {
  final separatorIndex = feedId.indexOf(':');
  if (separatorIndex <= 0 || separatorIndex == feedId.length - 1) {
    throw ArgumentError(
      "Invalid feed id '$feedId'. Expected format '{group}:{id}'.",
    );
  }

  return (
    feedId.substring(0, separatorIndex),
    feedId.substring(separatorIndex + 1),
  );
}

dynamic parseJsonSafely(String responseBody) {
  if (responseBody.trim().isEmpty) {
    return null;
  }
  try {
    return jsonDecode(responseBody);
  } catch (_) {
    return responseBody;
  }
}
