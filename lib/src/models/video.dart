class FastRelayVideo {
  const FastRelayVideo({
    required this.id,
    required this.mimeType,
    required this.sizeBytes,
    required this.status,
    required this.provider,
    required this.createdAt,
    this.hlsUrl,
    this.thumbnailUrl,
    this.durationSeconds,
    this.width,
    this.height,
    this.errorCode,
    this.errorMessage,
  });

  final String id;
  final String mimeType;
  final int sizeBytes;
  final String status;
  final String provider;
  final DateTime createdAt;
  final String? hlsUrl;
  final String? thumbnailUrl;
  final int? durationSeconds;
  final int? width;
  final int? height;
  final String? errorCode;
  final String? errorMessage;

  bool get isReady => status == 'ready';
  bool get isFailed => status == 'failed';
  bool get isProcessing => status == 'uploading' || status == 'processing';

  factory FastRelayVideo.fromJson(Map<String, dynamic> json) {
    return FastRelayVideo(
      id: json['id']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? 'video/mp4',
      sizeBytes: _readInt(json['sizeBytes']) ?? 0,
      status: json['status']?.toString() ?? 'uploading',
      provider: json['provider']?.toString() ?? 'cloudflare-stream',
      createdAt:
          _parseDateTime(json['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      hlsUrl: _readNullableString(json['hlsUrl']),
      thumbnailUrl: _readNullableString(json['thumbnailUrl']),
      durationSeconds: _readInt(json['durationSeconds']),
      width: _readInt(json['width']),
      height: _readInt(json['height']),
      errorCode: _readNullableString(json['errorCode']),
      errorMessage: _readNullableString(json['errorMessage']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mimeType': mimeType,
      'sizeBytes': sizeBytes,
      'status': status,
      'provider': provider,
      'createdAt': createdAt.toIso8601String(),
      if (hlsUrl != null) 'hlsUrl': hlsUrl,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      if (durationSeconds != null) 'durationSeconds': durationSeconds,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (errorCode != null) 'errorCode': errorCode,
      if (errorMessage != null) 'errorMessage': errorMessage,
    };
  }
}

class FastRelayVideoUploadUrl {
  const FastRelayVideoUploadUrl({
    required this.videoId,
    required this.uploadUrl,
    this.protocol = 'tus',
  });

  final String videoId;
  final String uploadUrl;
  final String protocol;

  factory FastRelayVideoUploadUrl.fromJson(Map<String, dynamic> json) {
    return FastRelayVideoUploadUrl(
      videoId: json['videoId']?.toString() ?? '',
      uploadUrl: json['uploadUrl']?.toString() ?? '',
      protocol: json['protocol']?.toString() ?? 'tus',
    );
  }
}

class FastRelayVideoStatusEvent {
  const FastRelayVideoStatusEvent({
    required this.type,
    required this.videoId,
    this.video,
    this.errorCode,
    this.errorMessage,
  });

  final String type;
  final String videoId;
  final FastRelayVideo? video;
  final String? errorCode;
  final String? errorMessage;

  bool get isReady => type == 'video.ready';
  bool get isFailed => type == 'video.failed';

  factory FastRelayVideoStatusEvent.fromJson(Map<String, dynamic> json) {
    final videoPayload = json['video'];
    return FastRelayVideoStatusEvent(
      type: json['type']?.toString() ?? '',
      videoId: json['videoId']?.toString() ?? '',
      video: videoPayload is Map<String, dynamic>
          ? FastRelayVideo.fromJson(videoPayload)
          : videoPayload is Map
          ? FastRelayVideo.fromJson(
              videoPayload.map((k, v) => MapEntry(k.toString(), v)),
            )
          : null,
      errorCode: _readNullableString(json['errorCode']),
      errorMessage: _readNullableString(json['errorMessage']),
    );
  }
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

String? _readNullableString(dynamic value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
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
