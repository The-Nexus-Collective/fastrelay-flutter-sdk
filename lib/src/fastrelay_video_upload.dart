import 'dart:async';

import 'package:http/http.dart' as http;

import 'fastrelay_client.dart';

class FastRelayVideoUploadProgress {
  const FastRelayVideoUploadProgress({
    required this.bytesUploaded,
    required this.totalBytes,
  });

  final int bytesUploaded;
  final int totalBytes;

  double get fraction =>
      totalBytes <= 0 ? 0 : (bytesUploaded / totalBytes).clamp(0.0, 1.0);
}

class FastRelayVideoUploadResult {
  const FastRelayVideoUploadResult({
    required this.videoId,
    required this.uploadUrl,
    required this.bytesUploaded,
  });

  final String videoId;
  final String uploadUrl;
  final int bytesUploaded;
}

class FastRelayVideoUploadException implements Exception {
  FastRelayVideoUploadException(this.message, {this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() =>
      'FastRelayVideoUploadException(${statusCode ?? ''}): $message';
}

/// Drives a tus 1.0.0 upload of [bytes] to [uploadUrl].
///
/// The upload URL is the one returned by [FastRelayClient.createVideoUploadUrl],
/// which is Cloudflare Stream's tus endpoint pre-authorized by the backend.
/// Emits [onProgress] after each PATCH chunk and returns when the full payload
/// has been accepted.
Future<int> tusUploadBytes({
  required String uploadUrl,
  required List<int> bytes,
  int chunkSize = 50 * 1024 * 1024,
  void Function(FastRelayVideoUploadProgress progress)? onProgress,
  http.Client? httpClient,
}) async {
  if (uploadUrl.trim().isEmpty) {
    throw ArgumentError('uploadUrl must not be empty.');
  }
  if (chunkSize <= 0) {
    throw ArgumentError('chunkSize must be positive.');
  }

  final client = httpClient ?? http.Client();
  final ownsClient = httpClient == null;
  final total = bytes.length;
  final uri = Uri.parse(uploadUrl);

  try {
    int offset = 0;
    onProgress?.call(
      FastRelayVideoUploadProgress(bytesUploaded: 0, totalBytes: total),
    );

    while (offset < total) {
      final end = (offset + chunkSize).clamp(0, total);
      final chunk = bytes.sublist(offset, end);

      final response = await client.patch(
        uri,
        headers: {
          'tus-resumable': '1.0.0',
          'upload-offset': '$offset',
          'content-type': 'application/offset+octet-stream',
        },
        body: chunk,
      );

      if (response.statusCode != 204 && response.statusCode != 200) {
        throw FastRelayVideoUploadException(
          'tus PATCH failed: ${response.statusCode} ${response.reasonPhrase ?? ''} ${response.body}'
              .trim(),
          statusCode: response.statusCode,
        );
      }

      final reportedOffsetText = _readHeader(response.headers, 'upload-offset');
      final reportedOffset =
          int.tryParse(reportedOffsetText ?? '') ?? (offset + chunk.length);
      offset = reportedOffset;

      onProgress?.call(
        FastRelayVideoUploadProgress(
          bytesUploaded: offset,
          totalBytes: total,
        ),
      );
    }

    return offset;
  } finally {
    if (ownsClient) {
      client.close();
    }
  }
}

/// High-level helper: mints a tus upload URL via the backend, then uploads
/// [bytes] directly to Cloudflare Stream via tus PATCH. Returns the
/// [FastRelayVideoUploadResult]; the caller subscribes to `video.ready` over
/// the realtime channel (or polls [FastRelayClient.getVideo]) for the final
/// `ready` state.
Future<FastRelayVideoUploadResult> uploadVideoBytes(
  FastRelayClient client, {
  required List<int> bytes,
  required String filename,
  required String mimeType,
  int chunkSize = 50 * 1024 * 1024,
  void Function(FastRelayVideoUploadProgress progress)? onProgress,
  http.Client? httpClient,
}) async {
  if (bytes.isEmpty) {
    throw ArgumentError('uploadVideoBytes requires non-empty bytes.');
  }
  if (filename.trim().isEmpty) {
    throw ArgumentError('uploadVideoBytes requires a non-empty filename.');
  }
  if (!mimeType.trim().toLowerCase().startsWith('video/')) {
    throw ArgumentError(
      'uploadVideoBytes requires a video/* mimeType (got "$mimeType").',
    );
  }

  final mint = await client.createVideoUploadUrl(
    filename: filename,
    sizeBytes: bytes.length,
    mimeType: mimeType,
  );

  final uploaded = await tusUploadBytes(
    uploadUrl: mint.uploadUrl,
    bytes: bytes,
    chunkSize: chunkSize,
    onProgress: onProgress,
    httpClient: httpClient,
  );

  return FastRelayVideoUploadResult(
    videoId: mint.videoId,
    uploadUrl: mint.uploadUrl,
    bytesUploaded: uploaded,
  );
}

String? _readHeader(Map<String, String> headers, String name) {
  final target = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == target) {
      return entry.value;
    }
  }
  return null;
}
