import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'fastrelay_api_error.dart';
import 'fastrelay_feed.dart';
import 'fastrelay_realtime.dart';
import 'models/models.dart';
import 'utils.dart';

enum FastRelayAuthMode { auto, user, server, none }

class FastRelayRequestOptions {
  const FastRelayRequestOptions({
    this.auth = FastRelayAuthMode.auto,
    this.idempotencyKey,
    this.headers = const {},
  });

  final FastRelayAuthMode auth;
  final String? idempotencyKey;
  final Map<String, String> headers;
}

class FastRelayClient {
  FastRelayClient({
    required this.apiKey,
    this.baseUrl = 'http://localhost:8080',
    this.token,
    Map<String, dynamic>? user,
    http.Client? httpClient,
    FastRelayRealtimeFactory? realtimeFactory,
  }) : user = user == null ? null : Map<String, dynamic>.from(user),
       _httpClient = httpClient ?? http.Client(),
       _realtimeFactory = realtimeFactory ?? FastRelayRealtime.new {
    capabilities = FastRelayCapabilitiesApi(this);
    activities = FastRelayActivitiesApi(this);
    reactions = FastRelayReactionsApi(this);
    comments = FastRelayCommentsApi(this);
    bookmarks = FastRelayBookmarksApi(this);
    polls = FastRelayPollsApi(this);
    files = FastRelayFilesApi(this);
    videos = FastRelayVideosApi(this);
    feedback = FastRelayFeedbackApi(this);
    moderation = FastRelayModerationApi(this);
  }

  final http.Client _httpClient;
  final FastRelayRealtimeFactory _realtimeFactory;

  String apiKey;
  String baseUrl;
  String? token;
  Map<String, dynamic>? user;
  FastRelayRealtime? realtime;

  late final FastRelayCapabilitiesApi capabilities;
  late final FastRelayActivitiesApi activities;
  late final FastRelayReactionsApi reactions;
  late final FastRelayCommentsApi comments;
  late final FastRelayBookmarksApi bookmarks;
  late final FastRelayPollsApi polls;
  late final FastRelayFilesApi files;
  late final FastRelayVideosApi videos;
  late final FastRelayFeedbackApi feedback;
  late final FastRelayModerationApi moderation;

  FastRelayFeed feed(String group, String id) => FastRelayFeed(this, group, id);

  Future<FastRelayClient> connectUser(
    Map<String, dynamic> user,
    String token, {
    bool upsertUser = false,
    bool realtime = false,
    FastRelayTokenProvider? tokenProvider,
    bool maintainBackgroundConnection = false,
  }) async {
    final userId = user['id'];
    if (userId == null || userId.toString().isEmpty) {
      throw ArgumentError('connectUser requires a user object with an id.');
    }
    if (token.trim().isEmpty) {
      throw ArgumentError('connectUser requires a JWT token string.');
    }

    this.user = Map<String, dynamic>.from(user);
    this.token = token;

    if (upsertUser) {
      await _request(
        method: 'POST',
        path: '/v1/users',
        body: {
          'id': userId,
          'displayName': user['displayName'] ?? user['name'],
          'profileData': user['profileData'] ?? user['data'],
          if (user['role'] != null) 'role': user['role'],
        },
        options: const FastRelayRequestOptions(),
      );
    }

    final existingRealtime = this.realtime;
    if (existingRealtime != null) {
      await existingRealtime.dispose();
      this.realtime = null;
    }

    if (realtime) {
      final realtimeClient = _realtimeFactory(
        client: this,
        token: token,
        tokenProvider: tokenProvider,
        maintainBackgroundConnection: maintainBackgroundConnection,
      );
      this.realtime = realtimeClient;
      await realtimeClient.connect();
    }

    return this;
  }

  FastRelayClient disconnectUser() {
    final existingRealtime = realtime;
    if (existingRealtime != null) {
      unawaited(existingRealtime.dispose());
      realtime = null;
    }

    user = null;
    token = null;
    return this;
  }

  FastRelayClient setToken(String token) {
    this.token = token;
    realtime?.updateToken(token);
    return this;
  }

  FastRelayClient setBaseUrl(String baseUrl) {
    this.baseUrl = baseUrl;
    realtime?.onBaseUrlChanged();
    return this;
  }

  void close() {
    final existingRealtime = realtime;
    if (existingRealtime != null) {
      unawaited(existingRealtime.dispose());
      realtime = null;
    }
    _httpClient.close();
  }

  Future<dynamic> getCapabilities({
    Map<String, dynamic> query = const {},
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _request(
      method: 'GET',
      path: '/v1/me/capabilities',
      query: {'feed': query['feed']},
      options: options,
    );
  }

  Future<dynamic> getUser(
    String id, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _request(
      method: 'GET',
      path: '/v1/users/${Uri.encodeComponent(id)}',
      options: options,
    );
  }

  Future<dynamic> updateUser(
    String id,
    Map<String, dynamic> request, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _request(
      method: 'PATCH',
      path: '/v1/users/${Uri.encodeComponent(id)}',
      body: request,
      options: options,
    );
  }

  Future<dynamic> getOrCreateFeed(
    String group,
    String id, {
    Map<String, dynamic> request = const {},
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _request(
      method: 'POST',
      path:
          '/v1/feeds/${Uri.encodeComponent(group)}/${Uri.encodeComponent(id)}',
      body: request,
      options: options,
    );
  }

  Future<dynamic> getFeedActivities(
    String group,
    String id, {
    Map<String, dynamic>? query,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _request(
      method: 'GET',
      path:
          '/v1/feeds/${Uri.encodeComponent(group)}/${Uri.encodeComponent(id)}/activities',
      query: buildFeedActivityQuery(query),
      options: options,
    );
  }

  Future<dynamic> deleteFeed(
    String group,
    String id, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _request(
      method: 'DELETE',
      path:
          '/v1/feeds/${Uri.encodeComponent(group)}/${Uri.encodeComponent(id)}',
      options: options,
    );
  }

  Future<dynamic> setFeedVisibility(
    String group,
    String id,
    String level, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _request(
      method: 'PUT',
      path:
          '/v1/feeds/${Uri.encodeComponent(group)}/${Uri.encodeComponent(id)}/visibility',
      body: {'level': level},
      options: options,
    );
  }

  Future<dynamic> updateFeedSettings(
    String group,
    String id,
    Map<String, dynamic> request, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _request(
      method: 'PUT',
      path:
          '/v1/feeds/${Uri.encodeComponent(group)}/${Uri.encodeComponent(id)}/settings',
      body: request,
      options: options,
    );
  }

  Future<dynamic> addFeedMember(
    String group,
    String id,
    Map<String, dynamic> request, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _request(
      method: 'POST',
      path:
          '/v1/feeds/${Uri.encodeComponent(group)}/${Uri.encodeComponent(id)}/members',
      body: request,
      options: options,
    );
  }

  Future<dynamic> removeFeedMember(
    String group,
    String id,
    String userId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _request(
      method: 'DELETE',
      path:
          '/v1/feeds/${Uri.encodeComponent(group)}/${Uri.encodeComponent(id)}/members/${Uri.encodeComponent(userId)}',
      options: options,
    );
  }

  Future<dynamic> listFeedMembers(
    String group,
    String id, {
    Map<String, dynamic>? query,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _request(
      method: 'GET',
      path:
          '/v1/feeds/${Uri.encodeComponent(group)}/${Uri.encodeComponent(id)}/members',
      query: {'limit': query?['limit'], 'cursor': query?['cursor']},
      options: options,
    );
  }

  Future<dynamic> followFeed(
    String group,
    String id,
    Map<String, dynamic> request, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    final payload = <String, dynamic>{
      ...request,
      'target': resolveFeedTarget(request['target']),
    };

    return _request(
      method: 'POST',
      path:
          '/v1/feeds/${Uri.encodeComponent(group)}/${Uri.encodeComponent(id)}/follows',
      body: payload,
      options: options,
    );
  }

  Future<dynamic> batchFollowFeed(
    String group,
    String id,
    Map<String, dynamic> request, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    final targets = <String>[
      for (final target in (request['targets'] as Iterable? ?? const []))
        resolveFeedTarget(target),
    ];

    return _request(
      method: 'POST',
      path:
          '/v1/feeds/${Uri.encodeComponent(group)}/${Uri.encodeComponent(id)}/follows/batch',
      body: {
        if (request['activityCopyLimit'] != null)
          'activityCopyLimit': request['activityCopyLimit'],
        'targets': targets,
      },
      options: options,
    );
  }

  Future<dynamic> unfollowFeed(
    String group,
    String id,
    Object target, {
    bool? keepHistory,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    final targetFeed = resolveFeedTarget(target);
    final (targetGroup, targetId) = splitFeedId(targetFeed);

    return _request(
      method: 'DELETE',
      path:
          '/v1/feeds/${Uri.encodeComponent(group)}/${Uri.encodeComponent(id)}/follows/${Uri.encodeComponent(targetGroup)}:${Uri.encodeComponent(targetId)}',
      query: {'keepHistory': keepHistory},
      options: options,
    );
  }

  Future<dynamic> listFollowers(
    String group,
    String id, {
    Map<String, dynamic>? query,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _request(
      method: 'GET',
      path:
          '/v1/feeds/${Uri.encodeComponent(group)}/${Uri.encodeComponent(id)}/followers',
      query: {'limit': query?['limit'], 'cursor': query?['cursor']},
      options: options,
    );
  }

  Future<dynamic> listFollowing(
    String group,
    String id, {
    Map<String, dynamic>? query,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _request(
      method: 'GET',
      path:
          '/v1/feeds/${Uri.encodeComponent(group)}/${Uri.encodeComponent(id)}/following',
      query: {'limit': query?['limit'], 'cursor': query?['cursor']},
      options: options,
    );
  }

  Future<dynamic> listFollowRequests(
    String group,
    String id, {
    Map<String, dynamic>? query,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _request(
      method: 'GET',
      path:
          '/v1/feeds/${Uri.encodeComponent(group)}/${Uri.encodeComponent(id)}/follow-requests',
      query: {'status': query?['status']},
      options: options,
    );
  }

  Future<dynamic> approveFollowRequest(
    String group,
    String id,
    String requestId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _request(
      method: 'POST',
      path:
          '/v1/feeds/${Uri.encodeComponent(group)}/${Uri.encodeComponent(id)}/follow-requests/${Uri.encodeComponent(requestId)}/approve',
      options: options,
    );
  }

  Future<dynamic> rejectFollowRequest(
    String group,
    String id,
    String requestId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _request(
      method: 'POST',
      path:
          '/v1/feeds/${Uri.encodeComponent(group)}/${Uri.encodeComponent(id)}/follow-requests/${Uri.encodeComponent(requestId)}/reject',
      options: options,
    );
  }

  Future<dynamic> addActivity(
    Map<String, dynamic> request, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _request(
      method: 'POST',
      path: '/v1/activities',
      body: request,
      options: options,
    );
  }

  Future<dynamic> getActivity(
    String id, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _request(
      method: 'GET',
      path: '/v1/activities/${Uri.encodeComponent(id)}',
      options: options,
    );
  }

  Future<dynamic> updateActivity(
    String id,
    Map<String, dynamic> request, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _request(
      method: 'PATCH',
      path: '/v1/activities/${Uri.encodeComponent(id)}',
      body: request,
      options: options,
    );
  }

  Future<dynamic> deleteActivity(
    String id, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _request(
      method: 'DELETE',
      path: '/v1/activities/${Uri.encodeComponent(id)}',
      options: options,
    );
  }

  Future<dynamic> batchGetActivities(
    Object requestOrIds, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    final body = requestOrIds is List ? {'ids': requestOrIds} : requestOrIds;
    return _request(
      method: 'POST',
      path: '/v1/activities/batch',
      body: body,
      options: options,
    );
  }

  Future<CursorPage<FastRelayActivity>> getFeedActivityList(
    String group,
    String id, {
    Map<String, dynamic>? query,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await getFeedActivities(
      group,
      id,
      query: query,
      options: options,
    );
    return CursorPage<FastRelayActivity>.fromJson(
      _asMap(response),
      FastRelayActivity.fromJson,
    );
  }

  Future<NotificationPage<FastRelayActivity>> getNotificationFeedActivities(
    String group,
    String id, {
    Map<String, dynamic>? query,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await getFeedActivities(
      group,
      id,
      query: query,
      options: options,
    );
    return NotificationPage<FastRelayActivity>.fromJson(
      _asMap(response),
      FastRelayActivity.fromJson,
    );
  }

  Future<FastRelayReaction> addReaction(
    String activityId, {
    required String type,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/activities/${Uri.encodeComponent(activityId)}/reactions',
      body: {'type': type},
      options: options,
    );
    return FastRelayReaction.fromJson(_asMap(response));
  }

  Future<void> removeReaction(
    String activityId,
    String reactionId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path:
          '/v1/activities/${Uri.encodeComponent(activityId)}/reactions/${Uri.encodeComponent(reactionId)}',
      options: options,
    );
  }

  Future<CursorPage<FastRelayReaction>> listReactions(
    String activityId, {
    String? type,
    int? limit,
    String? cursor,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/activities/${Uri.encodeComponent(activityId)}/reactions',
      query: {'type': type, 'limit': limit, 'cursor': cursor},
      options: options,
    );
    return CursorPage<FastRelayReaction>.fromJson(
      _asMap(response),
      FastRelayReaction.fromJson,
    );
  }

  Future<FastRelayComment> addComment(
    String activityId, {
    required String text,
    String? parentId,
    List<String>? mentionedUsers,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/activities/${Uri.encodeComponent(activityId)}/comments',
      body: {
        'text': text,
        if (parentId != null) 'parentId': parentId,
        if (mentionedUsers != null) 'mentionedUsers': mentionedUsers,
      },
      options: options,
    );
    return FastRelayComment.fromJson(_asMap(response));
  }

  Future<FastRelayComment> updateComment(
    String commentId, {
    required String text,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'PATCH',
      path: '/v1/comments/${Uri.encodeComponent(commentId)}',
      body: {'text': text},
      options: options,
    );
    return FastRelayComment.fromJson(_asMap(response));
  }

  Future<void> deleteComment(
    String commentId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/comments/${Uri.encodeComponent(commentId)}',
      options: options,
    );
  }

  Future<CursorPage<FastRelayComment>> listComments(
    String activityId, {
    String? sort,
    int? limit,
    String? cursor,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/activities/${Uri.encodeComponent(activityId)}/comments',
      query: {'sort': sort, 'limit': limit, 'cursor': cursor},
      options: options,
    );
    return CursorPage<FastRelayComment>.fromJson(
      _asMap(response),
      FastRelayComment.fromJson,
    );
  }

  Future<CursorPage<FastRelayComment>> listReplies(
    String commentId, {
    int? limit,
    String? cursor,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/comments/${Uri.encodeComponent(commentId)}/replies',
      query: {'limit': limit, 'cursor': cursor},
      options: options,
    );
    return CursorPage<FastRelayComment>.fromJson(
      _asMap(response),
      FastRelayComment.fromJson,
    );
  }

  Future<FastRelayCommentReaction> addCommentReaction(
    String commentId, {
    required String type,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/comments/${Uri.encodeComponent(commentId)}/reactions',
      body: {'type': type},
      options: options,
    );
    return FastRelayCommentReaction.fromJson(_asMap(response));
  }

  Future<void> removeCommentReaction(
    String commentId,
    String reactionId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path:
          '/v1/comments/${Uri.encodeComponent(commentId)}/reactions/${Uri.encodeComponent(reactionId)}',
      options: options,
    );
  }

  Future<FastRelayBookmark> addBookmark(
    String activityId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/activities/${Uri.encodeComponent(activityId)}/bookmarks',
      options: options,
    );
    return FastRelayBookmark.fromJson(_asMap(response));
  }

  Future<void> removeBookmark(
    String activityId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/activities/${Uri.encodeComponent(activityId)}/bookmarks',
      options: options,
    );
  }

  Future<FastRelayFeedActivityPin> pinActivity(
    String group,
    String id,
    String activityId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path:
          '/v1/feeds/${Uri.encodeComponent(group)}/${Uri.encodeComponent(id)}/activities/${Uri.encodeComponent(activityId)}/pin',
      options: options,
    );
    return FastRelayFeedActivityPin.fromJson(_asMap(response));
  }

  Future<void> unpinActivity(
    String group,
    String id,
    String activityId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path:
          '/v1/feeds/${Uri.encodeComponent(group)}/${Uri.encodeComponent(id)}/activities/${Uri.encodeComponent(activityId)}/pin',
      options: options,
    );
  }

  Future<CursorPage<FastRelayBookmark>> listBookmarks({
    int? limit,
    String? cursor,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/me/bookmarks',
      query: {'limit': limit, 'cursor': cursor},
      options: options,
    );
    return CursorPage<FastRelayBookmark>.fromJson(
      _asMap(response),
      FastRelayBookmark.fromJson,
    );
  }

  Future<FastRelayPoll> createPoll(
    String activityId, {
    required String question,
    required List<Map<String, String>> choices,
    int maxVotesPerUser = 1,
    bool anonymous = false,
    DateTime? expiresAt,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/activities/${Uri.encodeComponent(activityId)}/polls',
      body: {
        'question': question,
        'options': choices,
        'maxVotesPerUser': maxVotesPerUser,
        'anonymous': anonymous,
        if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
      },
      options: options,
    );
    return FastRelayPoll.fromJson(_asMap(response));
  }

  Future<FastRelayPoll> getPollForActivity(
    String activityId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/activities/${Uri.encodeComponent(activityId)}/polls',
      options: options,
    );
    return FastRelayPoll.fromJson(_asMap(response));
  }

  Future<FastRelayPoll> getPoll(
    String pollId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/polls/${Uri.encodeComponent(pollId)}',
      options: options,
    );
    return FastRelayPoll.fromJson(_asMap(response));
  }

  Future<FastRelayPoll> vote(
    String pollId, {
    required String optionId,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/polls/${Uri.encodeComponent(pollId)}/votes',
      body: {'optionId': optionId},
      options: options,
    );
    return FastRelayPoll.fromJson(_asMap(response));
  }

  Future<void> removeVote(
    String pollId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/polls/${Uri.encodeComponent(pollId)}/votes',
      options: options,
    );
  }

  Future<FastRelayFile> uploadFile(
    List<int> bytes,
    String filename, {
    String? type,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    if (bytes.isEmpty) {
      throw ArgumentError('uploadFile requires non-empty bytes.');
    }
    if (filename.trim().isEmpty) {
      throw ArgumentError('uploadFile requires a non-empty filename.');
    }

    final response = await _multipartRequest(
      method: 'POST',
      path: '/v1/files',
      bytes: bytes,
      filename: filename,
      fields: {if (type != null && type.trim().isNotEmpty) 'type': type.trim()},
      options: options,
    );

    return FastRelayFile.fromJson(_asMap(response));
  }

  Future<void> deleteFile(
    String fileId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/files/${Uri.encodeComponent(fileId)}',
      options: options,
    );
  }

  Future<FastRelayVideoUploadUrl> createVideoUploadUrl({
    required String filename,
    required int sizeBytes,
    required String mimeType,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/videos/upload-url',
      body: {
        'filename': filename,
        'sizeBytes': sizeBytes,
        'mimeType': mimeType,
      },
      options: options,
    );
    return FastRelayVideoUploadUrl.fromJson(_asMap(response));
  }

  Future<FastRelayVideo> getVideo(
    String videoId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/videos/${Uri.encodeComponent(videoId)}',
      options: options,
    );
    return FastRelayVideo.fromJson(_asMap(response));
  }

  Future<void> deleteVideo(
    String videoId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/videos/${Uri.encodeComponent(videoId)}',
      options: options,
    );
  }

  Future<FastRelayFeedback> submitFeedback(
    String activityId, {
    required String type,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    if (type != 'show_more' && type != 'show_less') {
      throw ArgumentError("Feedback type must be 'show_more' or 'show_less'.");
    }

    final response = await _request(
      method: 'POST',
      path: '/v1/activities/${Uri.encodeComponent(activityId)}/feedback',
      body: {'type': type},
      options: options,
    );
    return FastRelayFeedback.fromJson(_asMap(response));
  }

  Future<FastRelayModerationFlag> createFlag(
    String targetType,
    String targetId, {
    required String reason,
    String? description,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/moderation/flags',
      body: {
        'targetType': targetType,
        'targetId': targetId,
        'reason': reason,
        if (description != null) 'description': description,
      },
      options: options,
    );
    return FastRelayModerationFlag.fromJson(_asMap(response));
  }

  Future<void> deleteFlag(
    String flagId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/moderation/flags/${Uri.encodeComponent(flagId)}',
      options: options,
    );
  }

  Future<FastRelayUserMute> createMute(
    String userId, {
    String type = 'personal',
    DateTime? expiresAt,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/moderation/mutes',
      body: {
        'userId': userId,
        'type': type,
        if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
      },
      options: options,
    );
    return FastRelayUserMute.fromJson(_asMap(response));
  }

  Future<void> removeMute(
    String userId, {
    String type = 'personal',
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/moderation/mutes/${Uri.encodeComponent(userId)}',
      query: {'type': type},
      options: options,
    );
  }

  Future<CursorPage<FastRelayUserMute>> listMutes({
    String type = 'personal',
    int? limit,
    String? cursor,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/moderation/mutes',
      query: {'type': type, 'limit': limit, 'cursor': cursor},
      options: options,
    );
    return CursorPage<FastRelayUserMute>.fromJson(
      _asMap(response),
      FastRelayUserMute.fromJson,
    );
  }

  Future<CursorPage<FastRelayUserMute>> getMutedUsers({
    String type = 'personal',
    int? limit,
    String? cursor,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return listMutes(
      type: type,
      limit: limit,
      cursor: cursor,
      options: options,
    );
  }

  Future<dynamic> _multipartRequest({
    required String method,
    required String path,
    required List<int> bytes,
    required String filename,
    Map<String, String> fields = const {},
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final authorization = _buildAuthorization(options.auth);
    final uri = toAbsoluteUrl(baseUrl, path);
    final request = http.MultipartRequest(method, uri);

    request.headers['accept'] = 'application/json';
    if (authorization != null) {
      request.headers['authorization'] = authorization;
    }
    if (options.idempotencyKey != null && options.idempotencyKey!.isNotEmpty) {
      request.headers['idempotency-key'] = options.idempotencyKey!;
    }
    request.headers.addAll(options.headers);

    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    request.fields.addAll(fields);

    final streamedResponse = await _httpClient.send(request);
    final responseBody = await streamedResponse.stream.bytesToString();
    final parsedBody = parseJsonSafely(responseBody);

    final rateLimit = _getRateLimit(streamedResponse.headers);
    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      final parsedMap = parsedBody is Map ? parsedBody : null;
      final errorPayload = parsedMap?['error'];
      final errorMap = errorPayload is Map ? errorPayload : null;
      final fallbackMessage =
          'FastRelay API request failed (${streamedResponse.statusCode} ${streamedResponse.reasonPhrase ?? ''}).'
              .trim();

      throw FastRelayApiError(
        message:
            (errorMap?['message'] ??
                    parsedMap?['message'] ??
                    fallbackMessage)
                .toString(),
        status: streamedResponse.statusCode,
        code: errorMap?['code']?.toString(),
        details: errorMap?['details'],
        hint: errorMap?['hint']?.toString(),
        docUrl: errorMap?['docUrl']?.toString(),
        requestId: parsedMap?['requestId']?.toString(),
        path: path,
        method: method,
        rateLimit: rateLimit,
      );
    }

    if (parsedBody == null || parsedBody == '') {
      return null;
    }
    return parsedBody;
  }

  Future<dynamic> _request({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Object? body,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) async {
    final authorization = _buildAuthorization(options.auth);
    final uri = toAbsoluteUrl(baseUrl, path, query);
    final request = http.Request(method, uri);

    request.headers['accept'] = 'application/json';
    if (authorization != null) {
      request.headers['authorization'] = authorization;
    }
    if (options.idempotencyKey != null && options.idempotencyKey!.isNotEmpty) {
      request.headers['idempotency-key'] = options.idempotencyKey!;
    }
    request.headers.addAll(options.headers);

    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final streamedResponse = await _httpClient.send(request);
    final responseBody = await streamedResponse.stream.bytesToString();
    final parsedBody = parseJsonSafely(responseBody);

    final rateLimit = _getRateLimit(streamedResponse.headers);
    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      final parsedMap = parsedBody is Map ? parsedBody : null;
      final errorPayload = parsedMap?['error'];
      final errorMap = errorPayload is Map ? errorPayload : null;
      final fallbackMessage =
          'FastRelay API request failed (${streamedResponse.statusCode} ${streamedResponse.reasonPhrase ?? ''}).'
              .trim();

      throw FastRelayApiError(
        message:
            (errorMap?['message'] ??
                    parsedMap?['message'] ??
                    fallbackMessage)
                .toString(),
        status: streamedResponse.statusCode,
        code: errorMap?['code']?.toString(),
        details: errorMap?['details'],
        hint: errorMap?['hint']?.toString(),
        docUrl: errorMap?['docUrl']?.toString(),
        requestId: parsedMap?['requestId']?.toString(),
        path: path,
        method: method,
        rateLimit: rateLimit,
      );
    }

    if (parsedBody == null || parsedBody == '') {
      return null;
    }
    return parsedBody;
  }

  FastRelayRateLimit? _getRateLimit(Map<String, String> headers) {
    String? readHeader(String key) {
      for (final entry in headers.entries) {
        if (entry.key.toLowerCase() == key.toLowerCase()) {
          return entry.value;
        }
      }
      return null;
    }

    final limitText = readHeader('x-ratelimit-limit');
    final remainingText = readHeader('x-ratelimit-remaining');
    final resetText = readHeader('x-ratelimit-reset');

    if (limitText == null && remainingText == null && resetText == null) {
      return null;
    }

    return FastRelayRateLimit(
      limit: int.tryParse(limitText ?? ''),
      remaining: int.tryParse(remainingText ?? ''),
      reset: int.tryParse(resetText ?? ''),
    );
  }

  String? _buildAuthorization(FastRelayAuthMode auth) {
    switch (auth) {
      case FastRelayAuthMode.none:
        return null;
      case FastRelayAuthMode.server:
        throw StateError(
          'Server auth is not supported: this SDK is client-only. '
          'Call server endpoints from your backend.',
        );
      case FastRelayAuthMode.user:
        if (token == null || token!.isEmpty) {
          throw StateError(
            'This request requires a user token. Call connectUser() or setToken().',
          );
        }
        return 'Bearer $token';
      case FastRelayAuthMode.auto:
        if (token != null && token!.isNotEmpty) {
          return 'Bearer $token';
        }
        return null;
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
}

class FastRelayCapabilitiesApi {
  const FastRelayCapabilitiesApi(this._client);

  final FastRelayClient _client;

  Future<dynamic> get(
    Map<String, dynamic> query, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.getCapabilities(query: query, options: options);
  }
}

class FastRelayActivitiesApi {
  const FastRelayActivitiesApi(this._client);

  final FastRelayClient _client;

  Future<dynamic> add(
    Map<String, dynamic> request, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.addActivity(request, options: options);
  }

  Future<dynamic> get(
    String id, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.getActivity(id, options: options);
  }

  Future<dynamic> update(
    String id,
    Map<String, dynamic> request, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.updateActivity(id, request, options: options);
  }

  Future<dynamic> delete(
    String id, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.deleteActivity(id, options: options);
  }

  Future<dynamic> batchGet(
    Object requestOrIds, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.batchGetActivities(requestOrIds, options: options);
  }
}

class FastRelayReactionsApi {
  const FastRelayReactionsApi(this._client);

  final FastRelayClient _client;

  Future<FastRelayReaction> add(
    String activityId, {
    required String type,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.addReaction(activityId, type: type, options: options);
  }

  Future<void> remove(
    String activityId,
    String reactionId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.removeReaction(activityId, reactionId, options: options);
  }

  Future<CursorPage<FastRelayReaction>> list(
    String activityId, {
    String? type,
    int? limit,
    String? cursor,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.listReactions(
      activityId,
      type: type,
      limit: limit,
      cursor: cursor,
      options: options,
    );
  }
}

class FastRelayCommentsApi {
  const FastRelayCommentsApi(this._client);

  final FastRelayClient _client;

  Future<FastRelayComment> add(
    String activityId, {
    required String text,
    String? parentId,
    List<String>? mentionedUsers,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.addComment(
      activityId,
      text: text,
      parentId: parentId,
      mentionedUsers: mentionedUsers,
      options: options,
    );
  }

  Future<FastRelayComment> update(
    String commentId, {
    required String text,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.updateComment(commentId, text: text, options: options);
  }

  Future<void> delete(
    String commentId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.deleteComment(commentId, options: options);
  }

  Future<CursorPage<FastRelayComment>> list(
    String activityId, {
    String? sort,
    int? limit,
    String? cursor,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.listComments(
      activityId,
      sort: sort,
      limit: limit,
      cursor: cursor,
      options: options,
    );
  }

  Future<CursorPage<FastRelayComment>> listReplies(
    String commentId, {
    int? limit,
    String? cursor,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.listReplies(
      commentId,
      limit: limit,
      cursor: cursor,
      options: options,
    );
  }

  Future<FastRelayCommentReaction> addReaction(
    String commentId, {
    required String type,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.addCommentReaction(commentId, type: type, options: options);
  }

  Future<void> removeReaction(
    String commentId,
    String reactionId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.removeCommentReaction(
      commentId,
      reactionId,
      options: options,
    );
  }
}

class FastRelayBookmarksApi {
  const FastRelayBookmarksApi(this._client);

  final FastRelayClient _client;

  Future<FastRelayBookmark> add(
    String activityId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.addBookmark(activityId, options: options);
  }

  Future<void> remove(
    String activityId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.removeBookmark(activityId, options: options);
  }

  Future<CursorPage<FastRelayBookmark>> list({
    int? limit,
    String? cursor,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.listBookmarks(
      limit: limit,
      cursor: cursor,
      options: options,
    );
  }
}

class FastRelayPollsApi {
  const FastRelayPollsApi(this._client);

  final FastRelayClient _client;

  Future<FastRelayPoll> create(
    String activityId, {
    required String question,
    required List<Map<String, String>> choices,
    int maxVotesPerUser = 1,
    bool anonymous = false,
    DateTime? expiresAt,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.createPoll(
      activityId,
      question: question,
      choices: choices,
      maxVotesPerUser: maxVotesPerUser,
      anonymous: anonymous,
      expiresAt: expiresAt,
      options: options,
    );
  }

  Future<FastRelayPoll> getForActivity(
    String activityId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.getPollForActivity(activityId, options: options);
  }

  Future<FastRelayPoll> get(
    String pollId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.getPoll(pollId, options: options);
  }

  Future<FastRelayPoll> vote(
    String pollId, {
    required String optionId,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.vote(pollId, optionId: optionId, options: options);
  }

  Future<void> removeVote(
    String pollId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.removeVote(pollId, options: options);
  }
}

class FastRelayFilesApi {
  const FastRelayFilesApi(this._client);

  final FastRelayClient _client;

  Future<FastRelayFile> upload(
    List<int> bytes,
    String filename, {
    String? type,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.uploadFile(bytes, filename, type: type, options: options);
  }

  Future<void> delete(
    String fileId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.deleteFile(fileId, options: options);
  }
}

class FastRelayVideosApi {
  const FastRelayVideosApi(this._client);

  final FastRelayClient _client;

  Future<FastRelayVideoUploadUrl> createUploadUrl({
    required String filename,
    required int sizeBytes,
    required String mimeType,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.createVideoUploadUrl(
      filename: filename,
      sizeBytes: sizeBytes,
      mimeType: mimeType,
      options: options,
    );
  }

  Future<FastRelayVideo> get(
    String videoId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.getVideo(videoId, options: options);
  }

  Future<void> delete(
    String videoId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.deleteVideo(videoId, options: options);
  }
}

class FastRelayFeedbackApi {
  const FastRelayFeedbackApi(this._client);

  final FastRelayClient _client;

  Future<FastRelayFeedback> submit(
    String activityId, {
    required String type,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.submitFeedback(activityId, type: type, options: options);
  }
}

class FastRelayModerationApi {
  const FastRelayModerationApi(this._client);

  final FastRelayClient _client;

  Future<FastRelayModerationFlag> flag(
    String targetType,
    String targetId, {
    required String reason,
    String? description,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.createFlag(
      targetType,
      targetId,
      reason: reason,
      description: description,
      options: options,
    );
  }

  Future<void> unflag(
    String flagId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.deleteFlag(flagId, options: options);
  }

  Future<FastRelayUserMute> mute(
    String userId, {
    String type = 'personal',
    DateTime? expiresAt,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.createMute(
      userId,
      type: type,
      expiresAt: expiresAt,
      options: options,
    );
  }

  Future<void> unmute(
    String userId, {
    String type = 'personal',
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.removeMute(userId, type: type, options: options);
  }

  Future<CursorPage<FastRelayUserMute>> getMutedUsers({
    String type = 'personal',
    int? limit,
    String? cursor,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.getMutedUsers(
      type: type,
      limit: limit,
      cursor: cursor,
      options: options,
    );
  }
}
