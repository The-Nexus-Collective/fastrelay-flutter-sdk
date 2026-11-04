class FastrelayRateLimit {
  const FastrelayRateLimit({this.limit, this.remaining, this.reset});

  final int? limit;
  final int? remaining;
  final int? reset;
}

class FastrelayApiError implements Exception {
  const FastrelayApiError({
    required this.message,
    required this.status,
    this.code,
    this.details,
    this.hint,
    this.docUrl,
    this.requestId,
    this.path,
    this.method,
    this.rateLimit,
  });

  final String message;
  final int status;
  final String? code;
  final dynamic details;
  final String? hint;
  final String? docUrl;
  final String? requestId;
  final String? path;
  final String? method;
  final FastrelayRateLimit? rateLimit;

  @override
  String toString() {
    return 'FastrelayApiError(status: $status, code: $code, message: $message)';
  }
}
