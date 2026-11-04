import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'fastrelay_api_error.dart';
import 'fastrelay_feed.dart';
import 'fastrelay_realtime.dart';
import 'models/models.dart';
import 'utils.dart';

enum FastrelayAuthMode { auto, user, server, none }

class FastrelayRequestOptions {
  const FastrelayRequestOptions({
    this.auth = FastrelayAuthMode.auto,
    this.idempotencyKey,
    this.headers = const {},
  });

  final FastrelayAuthMode auth;
  final String? idempotencyKey;
  final Map<String, String> headers;
}

class FastrelayClient {
  FastrelayClient({
    required this.apiKey,
    this.baseUrl = 'http://localhost:8080',
    this.token,
    Map<String, dynamic>? user,
    http.Client? httpClient,
    FastrelayRealtimeFactory? realtimeFactory,
  }) : user = user == null ? null : Map<String, dynamic>.from(user),
       _httpClient = httpClient ?? http.Client(),
       _realtimeFactory = realtimeFactory ?? FastrelayRealtime.new {
    capabilities = FastrelayCapabilitiesApi(this);
    activities = FastrelayActivitiesApi(this);
    reactions = FastrelayReactionsApi(this);
    comments = FastrelayCommentsApi(this);
    bookmarks = FastrelayBookmarksApi(this);
    polls = FastrelayPollsApi(this);
    files = FastrelayFilesApi(this);
    videos = FastrelayVideosApi(this);
    feedback = FastrelayFeedbackApi(this);
    moderation = FastrelayModerationApi(this);
    conversations = FastrelayConversationsApi(this);
    messages = FastrelayMessagesApi(this);
    chat = FastrelayChatApi(this);
  }

  final http.Client _httpClient;
  final FastrelayRealtimeFactory _realtimeFactory;

  String apiKey;
  String baseUrl;
  String? token;
  Map<String, dynamic>? user;
  FastrelayRealtime? realtime;

  FastrelayTokenProvider? _tokenProvider;
  Future<String>? _tokenRefresh;

  late final FastrelayCapabilitiesApi capabilities;
  late final FastrelayActivitiesApi activities;
  late final FastrelayReactionsApi reactions;
  late final FastrelayCommentsApi comments;
  late final FastrelayBookmarksApi bookmarks;
  late final FastrelayPollsApi polls;
  late final FastrelayFilesApi files;
  late final FastrelayVideosApi videos;
  late final FastrelayFeedbackApi feedback;
  late final FastrelayModerationApi moderation;
  late final FastrelayConversationsApi conversations;
  late final FastrelayMessagesApi messages;
  late final FastrelayChatApi chat;

  FastrelayFeed feed(String group, String id) => FastrelayFeed(this, group, id);

  Future<FastrelayClient> connectUser(
    Map<String, dynamic> user,
    String token, {
    bool upsertUser = false,
    bool realtime = false,
    FastrelayTokenProvider? tokenProvider,
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
    _tokenProvider = tokenProvider;

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
        options: const FastrelayRequestOptions(),
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

  FastrelayClient disconnectUser() {
    final existingRealtime = realtime;
    if (existingRealtime != null) {
      unawaited(existingRealtime.dispose());
      realtime = null;
    }

    user = null;
    token = null;
    _tokenProvider = null;
    return this;
  }

  FastrelayClient setToken(String token) {
    this.token = token;
    realtime?.updateToken(token);
    return this;
  }

  /// Fetches a fresh user JWT through the `tokenProvider` given to [connectUser]
  /// and applies it with [setToken]. Concurrent callers share one in-flight
  /// refresh. Throws [StateError] when no provider is configured.
  Future<String> refreshToken() {
    final pending = _tokenRefresh;
    if (pending != null) {
      return pending;
    }
    final refresh = _refreshToken();
    _tokenRefresh = refresh;
    return refresh.whenComplete(() => _tokenRefresh = null);
  }

  Future<String> _refreshToken() async {
    final tokenProvider = _tokenProvider;
    if (tokenProvider == null) {
      throw StateError(
        'Token refresh requires a tokenProvider. Pass one to connectUser().',
      );
    }
    final token = await tokenProvider();
    if (token.trim().isEmpty) {
      throw StateError('tokenProvider returned an empty token.');
    }
    setToken(token);
    return token;
  }

  FastrelayClient setBaseUrl(String baseUrl) {
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _request(
      method: 'DELETE',
      path: '/v1/activities/${Uri.encodeComponent(id)}',
      options: options,
    );
  }

  Future<dynamic> batchGetActivities(
    Object requestOrIds, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    final body = requestOrIds is List ? {'ids': requestOrIds} : requestOrIds;
    return _request(
      method: 'POST',
      path: '/v1/activities/batch',
      body: body,
      options: options,
    );
  }

  Future<CursorPage<FastrelayActivity>> getFeedActivityList(
    String group,
    String id, {
    Map<String, dynamic>? query,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await getFeedActivities(
      group,
      id,
      query: query,
      options: options,
    );
    return CursorPage<FastrelayActivity>.fromJson(
      _asMap(response),
      FastrelayActivity.fromJson,
    );
  }

  Future<NotificationPage<FastrelayActivity>> getNotificationFeedActivities(
    String group,
    String id, {
    Map<String, dynamic>? query,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await getFeedActivities(
      group,
      id,
      query: query,
      options: options,
    );
    return NotificationPage<FastrelayActivity>.fromJson(
      _asMap(response),
      FastrelayActivity.fromJson,
    );
  }

  Future<FastrelayReaction> addReaction(
    String activityId, {
    required String type,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/activities/${Uri.encodeComponent(activityId)}/reactions',
      body: {'type': type},
      options: options,
    );
    return FastrelayReaction.fromJson(_asMap(response));
  }

  Future<void> removeReaction(
    String activityId,
    String reactionId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path:
          '/v1/activities/${Uri.encodeComponent(activityId)}/reactions/${Uri.encodeComponent(reactionId)}',
      options: options,
    );
  }

  Future<CursorPage<FastrelayReaction>> listReactions(
    String activityId, {
    String? type,
    int? limit,
    String? cursor,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/activities/${Uri.encodeComponent(activityId)}/reactions',
      query: {'type': type, 'limit': limit, 'cursor': cursor},
      options: options,
    );
    return CursorPage<FastrelayReaction>.fromJson(
      _asMap(response),
      FastrelayReaction.fromJson,
    );
  }

  Future<FastrelayComment> addComment(
    String activityId, {
    required String text,
    String? parentId,
    List<String>? mentionedUsers,
    Map<String, dynamic>? custom,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/activities/${Uri.encodeComponent(activityId)}/comments',
      body: {
        'text': text,
        if (parentId != null) 'parentId': parentId,
        if (mentionedUsers != null) 'mentionedUsers': mentionedUsers,
        if (custom != null) 'custom': custom,
      },
      options: options,
    );
    return FastrelayComment.fromJson(_asMap(response));
  }

  Future<FastrelayComment> updateComment(
    String commentId, {
    required String text,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'PATCH',
      path: '/v1/comments/${Uri.encodeComponent(commentId)}',
      body: {'text': text},
      options: options,
    );
    return FastrelayComment.fromJson(_asMap(response));
  }

  Future<void> deleteComment(
    String commentId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/comments/${Uri.encodeComponent(commentId)}',
      options: options,
    );
  }

  Future<CursorPage<FastrelayComment>> listComments(
    String activityId, {
    String? sort,
    int? limit,
    String? cursor,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/activities/${Uri.encodeComponent(activityId)}/comments',
      query: {'sort': sort, 'limit': limit, 'cursor': cursor},
      options: options,
    );
    return CursorPage<FastrelayComment>.fromJson(
      _asMap(response),
      FastrelayComment.fromJson,
    );
  }

  Future<CursorPage<FastrelayComment>> listReplies(
    String commentId, {
    int? limit,
    String? cursor,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/comments/${Uri.encodeComponent(commentId)}/replies',
      query: {'limit': limit, 'cursor': cursor},
      options: options,
    );
    return CursorPage<FastrelayComment>.fromJson(
      _asMap(response),
      FastrelayComment.fromJson,
    );
  }

  Future<FastrelayCommentReaction> addCommentReaction(
    String commentId, {
    required String type,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/comments/${Uri.encodeComponent(commentId)}/reactions',
      body: {'type': type},
      options: options,
    );
    return FastrelayCommentReaction.fromJson(_asMap(response));
  }

  Future<void> removeCommentReaction(
    String commentId,
    String reactionId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path:
          '/v1/comments/${Uri.encodeComponent(commentId)}/reactions/${Uri.encodeComponent(reactionId)}',
      options: options,
    );
  }

  Future<FastrelayBookmark> addBookmark(
    String activityId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/activities/${Uri.encodeComponent(activityId)}/bookmarks',
      options: options,
    );
    return FastrelayBookmark.fromJson(_asMap(response));
  }

  Future<void> removeBookmark(
    String activityId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/activities/${Uri.encodeComponent(activityId)}/bookmarks',
      options: options,
    );
  }

  Future<FastrelayFeedActivityPin> pinActivity(
    String group,
    String id,
    String activityId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path:
          '/v1/feeds/${Uri.encodeComponent(group)}/${Uri.encodeComponent(id)}/activities/${Uri.encodeComponent(activityId)}/pin',
      options: options,
    );
    return FastrelayFeedActivityPin.fromJson(_asMap(response));
  }

  Future<void> unpinActivity(
    String group,
    String id,
    String activityId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path:
          '/v1/feeds/${Uri.encodeComponent(group)}/${Uri.encodeComponent(id)}/activities/${Uri.encodeComponent(activityId)}/pin',
      options: options,
    );
  }

  Future<CursorPage<FastrelayBookmark>> listBookmarks({
    int? limit,
    String? cursor,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/me/bookmarks',
      query: {'limit': limit, 'cursor': cursor},
      options: options,
    );
    return CursorPage<FastrelayBookmark>.fromJson(
      _asMap(response),
      FastrelayBookmark.fromJson,
    );
  }

  Future<FastrelayPoll> createPoll(
    String activityId, {
    required String question,
    required List<Map<String, String>> choices,
    int maxVotesPerUser = 1,
    bool anonymous = false,
    DateTime? expiresAt,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    return FastrelayPoll.fromJson(_asMap(response));
  }

  Future<FastrelayPoll> getPollForActivity(
    String activityId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/activities/${Uri.encodeComponent(activityId)}/polls',
      options: options,
    );
    return FastrelayPoll.fromJson(_asMap(response));
  }

  Future<FastrelayPoll> getPoll(
    String pollId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/polls/${Uri.encodeComponent(pollId)}',
      options: options,
    );
    return FastrelayPoll.fromJson(_asMap(response));
  }

  Future<FastrelayPoll> vote(
    String pollId, {
    required String optionId,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/polls/${Uri.encodeComponent(pollId)}/votes',
      body: {'optionId': optionId},
      options: options,
    );
    return FastrelayPoll.fromJson(_asMap(response));
  }

  Future<void> removeVote(
    String pollId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/polls/${Uri.encodeComponent(pollId)}/votes',
      options: options,
    );
  }

  Future<FastrelayFile> uploadFile(
    List<int> bytes,
    String filename, {
    String? type,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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

    return FastrelayFile.fromJson(_asMap(response));
  }

  Future<void> deleteFile(
    String fileId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/files/${Uri.encodeComponent(fileId)}',
      options: options,
    );
  }

  /// Reserves a pending image or video file and returns a presigned PUT URL.
  ///
  /// Prefer [uploadFileDirect], which also uploads and confirms the file.
  Future<FastrelayFileUpload> createFileUpload({
    required String contentType,
    required int sizeBytes,
    String? type,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/files/uploads',
      body: {
        'contentType': contentType,
        'sizeBytes': sizeBytes,
        if (type != null && type.trim().isNotEmpty) 'type': type.trim(),
      },
      options: options,
    );
    return FastrelayFileUpload.fromJson(_asMap(response));
  }

  /// Makes an uploaded file available once its bytes are in storage.
  ///
  /// Throws a `409` [FastrelayApiError] with code `FILE_NOT_UPLOADED` while the
  /// object is missing or incomplete; the call can be retried.
  Future<FastrelayFile> confirmFileUpload(
    String fileId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/files/${Uri.encodeComponent(fileId)}/confirm',
      options: options,
    );
    return FastrelayFile.fromJson(_asMap(response));
  }

  /// Uploads an image or video straight to storage instead of through the API.
  ///
  /// Reserves the file, PUTs [bytes] to the presigned URL and confirms it.
  /// [contentType] must be an `image/*` or `video/*` type matching the bytes;
  /// use [uploadFile] for anything else.
  Future<FastrelayFile> uploadFileDirect(
    List<int> bytes,
    String contentType, {
    String? type,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    if (bytes.isEmpty) {
      throw ArgumentError('uploadFileDirect requires non-empty bytes.');
    }

    final upload = await createFileUpload(
      contentType: contentType,
      sizeBytes: bytes.length,
      type: type,
      options: options,
    );

    final request = http.Request('PUT', Uri.parse(upload.uploadUrl));
    // The transport derives Content-Length from the body, which is exactly
    // the signed size.
    upload.requiredHeaders.forEach((name, value) {
      if (name.toLowerCase() != 'content-length') {
        request.headers[name] = value;
      }
    });
    request.bodyBytes = bytes;

    final streamedResponse = await _httpClient.send(request);
    final responseBody = await streamedResponse.stream.bytesToString();
    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      throw FastrelayApiError(
        message:
            'File upload to storage failed (${streamedResponse.statusCode} ${streamedResponse.reasonPhrase ?? ''}). $responseBody'
                .trim(),
        status: streamedResponse.statusCode,
        method: 'PUT',
      );
    }

    return confirmFileUpload(upload.fileId, options: options);
  }

  Future<FastrelayVideoUploadUrl> createVideoUploadUrl({
    required String filename,
    required int sizeBytes,
    required String mimeType,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    return FastrelayVideoUploadUrl.fromJson(_asMap(response));
  }

  Future<FastrelayVideo> getVideo(
    String videoId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/videos/${Uri.encodeComponent(videoId)}',
      options: options,
    );
    return FastrelayVideo.fromJson(_asMap(response));
  }

  Future<void> deleteVideo(
    String videoId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/videos/${Uri.encodeComponent(videoId)}',
      options: options,
    );
  }

  Future<FastrelayFeedback> submitFeedback(
    String activityId, {
    required String type,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    return FastrelayFeedback.fromJson(_asMap(response));
  }

  /// Flags content for moderation. [targetType] is e.g. `'activity'`,
  /// `'comment'`, `'user'` or `'message'` (chat messages).
  Future<FastrelayModerationFlag> createFlag(
    String targetType,
    String targetId, {
    required String reason,
    String? description,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    return FastrelayModerationFlag.fromJson(_asMap(response));
  }

  Future<void> deleteFlag(
    String flagId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/moderation/flags/${Uri.encodeComponent(flagId)}',
      options: options,
    );
  }

  /// Mutes [userId]. [type] is `'personal'` (default) or `'block'`. A block
  /// hides the user like a personal mute (feeds and chat messages) and also
  /// suppresses chat typing and presence in both directions. Pass the same
  /// [type] to [removeMute] / [listMutes] to unblock or list blocks.
  Future<FastrelayUserMute> createMute(
    String userId, {
    String type = 'personal',
    DateTime? expiresAt,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    return FastrelayUserMute.fromJson(_asMap(response));
  }

  Future<void> removeMute(
    String userId, {
    String type = 'personal',
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/moderation/mutes/${Uri.encodeComponent(userId)}',
      query: {'type': type},
      options: options,
    );
  }

  Future<CursorPage<FastrelayUserMute>> listMutes({
    String type = 'personal',
    int? limit,
    String? cursor,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/moderation/mutes',
      query: {'type': type, 'limit': limit, 'cursor': cursor},
      options: options,
    );
    return CursorPage<FastrelayUserMute>.fromJson(
      _asMap(response),
      FastrelayUserMute.fromJson,
    );
  }

  Future<CursorPage<FastrelayUserMute>> getMutedUsers({
    String type = 'personal',
    int? limit,
    String? cursor,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return listMutes(
      type: type,
      limit: limit,
      cursor: cursor,
      options: options,
    );
  }

  /// Creates a conversation. [kind] is `'group'` (server default) or
  /// `'direct'`; creating a direct conversation that already exists returns
  /// the existing one. [members] are the other participants' user ids.
  Future<FastrelayConversation> createConversation({
    String? kind,
    String? type,
    List<String> members = const [],
    String? name,
    String? image,
    Map<String, dynamic>? custom,
    bool? presenceEnabled,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/conversations',
      body: {
        'kind': ?kind,
        'type': ?type,
        'members': members,
        'name': ?name,
        'image': ?image,
        'custom': ?custom,
        'presenceEnabled': ?presenceEnabled,
      },
      options: options,
    );
    return FastrelayConversation.fromJson(_asMap(response));
  }

  /// Lists the user's conversations. [sort] is `'lastMessageAt'` (default),
  /// `'createdAt'`, `'updatedAt'` or `'unreadCount'`; [direction] is `'asc'`
  /// or `'desc'` (default).
  Future<CursorPage<FastrelayConversation>> queryConversations({
    FastrelayConversationFilter? filter,
    String? sort,
    String? direction,
    int? limit,
    String? cursor,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/conversations/query',
      body: {
        if (filter != null) 'filter': filter.toJson(),
        'sort': ?sort,
        'direction': ?direction,
        'limit': ?limit,
        'cursor': ?cursor,
      },
      options: options,
    );
    return CursorPage<FastrelayConversation>.fromJson(
      _asMap(response),
      FastrelayConversation.fromJson,
    );
  }

  Future<FastrelayConversation> getConversation(
    String conversationId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/conversations/${Uri.encodeComponent(conversationId)}',
      options: options,
    );
    return FastrelayConversation.fromJson(_asMap(response));
  }

  /// Updates a conversation. Only the provided fields are sent.
  Future<FastrelayConversation> updateConversation(
    String conversationId, {
    String? name,
    String? image,
    Map<String, dynamic>? custom,
    bool? presenceEnabled,
    bool? frozen,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'PATCH',
      path: '/v1/conversations/${Uri.encodeComponent(conversationId)}',
      body: {
        'name': ?name,
        'image': ?image,
        'custom': ?custom,
        'presenceEnabled': ?presenceEnabled,
        'frozen': ?frozen,
      },
      options: options,
    );
    return FastrelayConversation.fromJson(_asMap(response));
  }

  Future<void> deleteConversation(
    String conversationId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/conversations/${Uri.encodeComponent(conversationId)}',
      options: options,
    );
  }

  /// Hides all current messages from the conversation's history. The server
  /// posts a system message unless [systemMessage] is `false`.
  Future<FastrelayConversation> truncateConversation(
    String conversationId, {
    bool? systemMessage,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/conversations/${Uri.encodeComponent(conversationId)}/truncate',
      body: systemMessage == null ? null : {'systemMessage': systemMessage},
      options: options,
    );
    return FastrelayConversation.fromJson(_asMap(response));
  }

  Future<CursorPage<FastrelayConversationMember>> listConversationMembers(
    String conversationId, {
    int? limit,
    String? cursor,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/conversations/${Uri.encodeComponent(conversationId)}/members',
      query: {'limit': limit, 'cursor': cursor},
      options: options,
    );
    return CursorPage<FastrelayConversationMember>.fromJson(
      _asMap(response),
      FastrelayConversationMember.fromJson,
    );
  }

  Future<FastrelayConversation> addConversationMembers(
    String conversationId,
    List<String> userIds, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/conversations/${Uri.encodeComponent(conversationId)}/members',
      body: {'userIds': userIds},
      options: options,
    );
    return FastrelayConversation.fromJson(_asMap(response));
  }

  /// Changes a member's [role] (`'owner'`, `'moderator'`, `'member'`) or
  /// [restriction] (`'banned'`, `'muted'`, `'none'` to lift it). Only the
  /// provided fields are sent.
  Future<FastrelayConversationMember> updateConversationMember(
    String conversationId,
    String userId, {
    String? role,
    String? restriction,
    DateTime? restrictionExpiresAt,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'PATCH',
      path:
          '/v1/conversations/${Uri.encodeComponent(conversationId)}/members/${Uri.encodeComponent(userId)}',
      body: {
        'role': ?role,
        'restriction': ?restriction,
        if (restrictionExpiresAt != null)
          'restrictionExpiresAt': restrictionExpiresAt
              .toUtc()
              .toIso8601String(),
      },
      options: options,
    );
    return FastrelayConversationMember.fromJson(_asMap(response));
  }

  /// Removes [userId] from the conversation. Pass the current user's id to
  /// leave it.
  Future<void> removeConversationMember(
    String conversationId,
    String userId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path:
          '/v1/conversations/${Uri.encodeComponent(conversationId)}/members/${Uri.encodeComponent(userId)}',
      options: options,
    );
  }

  /// Sends a message. Pass `FastrelayRequestOptions(idempotencyKey: ...)` to
  /// make retries safe.
  Future<FastrelayMessage> sendMessage(
    String conversationId, {
    String? text,
    Map<String, dynamic>? custom,
    String? replyToId,
    bool? silent,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/conversations/${Uri.encodeComponent(conversationId)}/messages',
      body: {
        'text': ?text,
        'custom': ?custom,
        'replyToId': ?replyToId,
        'silent': ?silent,
      },
      options: options,
    );
    return FastrelayMessage.fromJson(_asMap(response));
  }

  /// Lists messages in ascending `seq` order.
  ///
  /// [cursor] is an exclusive message seq (pass a page's `nextCursor`):
  /// [direction] `'older'` (default) pages back from it, `'newer'` pages
  /// forward. [around] returns a window of [limit] messages centred on that
  /// seq.
  Future<CursorPage<FastrelayMessage>> listMessages(
    String conversationId, {
    String? cursor,
    String? direction,
    int? around,
    int? limit,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/conversations/${Uri.encodeComponent(conversationId)}/messages',
      query: {
        'cursor': cursor,
        'direction': direction,
        'around': around,
        'limit': limit,
      },
      options: options,
    );
    return CursorPage<FastrelayMessage>.fromJson(
      _asMap(response),
      FastrelayMessage.fromJson,
    );
  }

  /// Edits a message. Only the provided fields are sent.
  Future<FastrelayMessage> updateMessage(
    String messageId, {
    String? text,
    Map<String, dynamic>? custom,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'PATCH',
      path: '/v1/messages/${Uri.encodeComponent(messageId)}',
      body: {'text': ?text, 'custom': ?custom},
      options: options,
    );
    return FastrelayMessage.fromJson(_asMap(response));
  }

  Future<void> deleteMessage(
    String messageId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/messages/${Uri.encodeComponent(messageId)}',
      options: options,
    );
  }

  /// Marks the conversation read up to [seq], or up to the latest message
  /// when [seq] is omitted. Returns the user's updated unread totals.
  Future<FastrelayUnreadTotals> markConversationRead(
    String conversationId, {
    int? seq,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/conversations/${Uri.encodeComponent(conversationId)}/read',
      body: seq == null ? null : {'seq': seq},
      options: options,
    );
    return FastrelayUnreadTotals.fromJson(_asMap(response));
  }

  Future<FastrelayUnreadTotals> getUnreadTotals({
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/chat/unread',
      options: options,
    );
    return FastrelayUnreadTotals.fromJson(_asMap(response));
  }

  /// Fetches chat changes since [since] — the `serverTime` from
  /// `connection.established` or from the previous sync. [conversationIds]
  /// are the conversations held locally; those the user lost access to come
  /// back in `removedConversationIds`.
  Future<FastrelayChatSync> syncChat({
    required DateTime since,
    List<String> conversationIds = const [],
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/chat/sync',
      body: {
        'since': since.toUtc().toIso8601String(),
        'conversationIds': conversationIds,
      },
      options: options,
    );
    return FastrelayChatSync.fromJson(_asMap(response));
  }

  /// Runs [send]; on a 401 with a user token and a configured `tokenProvider`,
  /// refreshes the token once and re-runs [send]. A second 401 propagates.
  Future<dynamic> _withTokenRefresh(
    FastrelayAuthMode auth,
    Future<dynamic> Function() send,
  ) async {
    try {
      return await send();
    } on FastrelayApiError catch (error) {
      final canRefresh =
          error.status == 401 &&
          auth != FastrelayAuthMode.none &&
          _tokenProvider != null;
      if (!canRefresh) {
        rethrow;
      }
      await refreshToken();
      return send();
    }
  }

  Future<dynamic> _multipartRequest({
    required String method,
    required String path,
    required List<int> bytes,
    required String filename,
    Map<String, String> fields = const {},
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _withTokenRefresh(
      options.auth,
      () => _sendMultipartRequest(
        method: method,
        path: path,
        bytes: bytes,
        filename: filename,
        fields: fields,
        options: options,
      ),
    );
  }

  Future<dynamic> _sendMultipartRequest({
    required String method,
    required String path,
    required List<int> bytes,
    required String filename,
    Map<String, String> fields = const {},
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
          'fastrelay API request failed (${streamedResponse.statusCode} ${streamedResponse.reasonPhrase ?? ''}).'
              .trim();

      throw FastrelayApiError(
        message:
            (errorMap?['message'] ?? parsedMap?['message'] ?? fallbackMessage)
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _withTokenRefresh(
      options.auth,
      () => _sendRequest(
        method: method,
        path: path,
        query: query,
        body: body,
        options: options,
      ),
    );
  }

  Future<dynamic> _sendRequest({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Object? body,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
          'fastrelay API request failed (${streamedResponse.statusCode} ${streamedResponse.reasonPhrase ?? ''}).'
              .trim();

      throw FastrelayApiError(
        message:
            (errorMap?['message'] ?? parsedMap?['message'] ?? fallbackMessage)
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

  FastrelayRateLimit? _getRateLimit(Map<String, String> headers) {
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

    return FastrelayRateLimit(
      limit: int.tryParse(limitText ?? ''),
      remaining: int.tryParse(remainingText ?? ''),
      reset: int.tryParse(resetText ?? ''),
    );
  }

  String? _buildAuthorization(FastrelayAuthMode auth) {
    switch (auth) {
      case FastrelayAuthMode.none:
        return null;
      case FastrelayAuthMode.server:
        throw StateError(
          'Server auth is not supported: this SDK is client-only. '
          'Call server endpoints from your backend.',
        );
      case FastrelayAuthMode.user:
        if (token == null || token!.isEmpty) {
          throw StateError(
            'This request requires a user token. Call connectUser() or setToken().',
          );
        }
        return 'Bearer $token';
      case FastrelayAuthMode.auto:
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

class FastrelayCapabilitiesApi {
  const FastrelayCapabilitiesApi(this._client);

  final FastrelayClient _client;

  Future<dynamic> get(
    Map<String, dynamic> query, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.getCapabilities(query: query, options: options);
  }
}

class FastrelayActivitiesApi {
  const FastrelayActivitiesApi(this._client);

  final FastrelayClient _client;

  Future<dynamic> add(
    Map<String, dynamic> request, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.addActivity(request, options: options);
  }

  Future<dynamic> get(
    String id, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.getActivity(id, options: options);
  }

  Future<dynamic> update(
    String id,
    Map<String, dynamic> request, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.updateActivity(id, request, options: options);
  }

  Future<dynamic> delete(
    String id, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.deleteActivity(id, options: options);
  }

  Future<dynamic> batchGet(
    Object requestOrIds, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.batchGetActivities(requestOrIds, options: options);
  }
}

class FastrelayReactionsApi {
  const FastrelayReactionsApi(this._client);

  final FastrelayClient _client;

  Future<FastrelayReaction> add(
    String activityId, {
    required String type,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.addReaction(activityId, type: type, options: options);
  }

  Future<void> remove(
    String activityId,
    String reactionId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.removeReaction(activityId, reactionId, options: options);
  }

  Future<CursorPage<FastrelayReaction>> list(
    String activityId, {
    String? type,
    int? limit,
    String? cursor,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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

class FastrelayCommentsApi {
  const FastrelayCommentsApi(this._client);

  final FastrelayClient _client;

  Future<FastrelayComment> add(
    String activityId, {
    required String text,
    String? parentId,
    List<String>? mentionedUsers,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.addComment(
      activityId,
      text: text,
      parentId: parentId,
      mentionedUsers: mentionedUsers,
      options: options,
    );
  }

  Future<FastrelayComment> update(
    String commentId, {
    required String text,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.updateComment(commentId, text: text, options: options);
  }

  Future<void> delete(
    String commentId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.deleteComment(commentId, options: options);
  }

  Future<CursorPage<FastrelayComment>> list(
    String activityId, {
    String? sort,
    int? limit,
    String? cursor,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.listComments(
      activityId,
      sort: sort,
      limit: limit,
      cursor: cursor,
      options: options,
    );
  }

  Future<CursorPage<FastrelayComment>> listReplies(
    String commentId, {
    int? limit,
    String? cursor,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.listReplies(
      commentId,
      limit: limit,
      cursor: cursor,
      options: options,
    );
  }

  Future<FastrelayCommentReaction> addReaction(
    String commentId, {
    required String type,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.addCommentReaction(commentId, type: type, options: options);
  }

  Future<void> removeReaction(
    String commentId,
    String reactionId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.removeCommentReaction(
      commentId,
      reactionId,
      options: options,
    );
  }
}

class FastrelayBookmarksApi {
  const FastrelayBookmarksApi(this._client);

  final FastrelayClient _client;

  Future<FastrelayBookmark> add(
    String activityId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.addBookmark(activityId, options: options);
  }

  Future<void> remove(
    String activityId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.removeBookmark(activityId, options: options);
  }

  Future<CursorPage<FastrelayBookmark>> list({
    int? limit,
    String? cursor,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.listBookmarks(
      limit: limit,
      cursor: cursor,
      options: options,
    );
  }
}

class FastrelayPollsApi {
  const FastrelayPollsApi(this._client);

  final FastrelayClient _client;

  Future<FastrelayPoll> create(
    String activityId, {
    required String question,
    required List<Map<String, String>> choices,
    int maxVotesPerUser = 1,
    bool anonymous = false,
    DateTime? expiresAt,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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

  Future<FastrelayPoll> getForActivity(
    String activityId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.getPollForActivity(activityId, options: options);
  }

  Future<FastrelayPoll> get(
    String pollId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.getPoll(pollId, options: options);
  }

  Future<FastrelayPoll> vote(
    String pollId, {
    required String optionId,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.vote(pollId, optionId: optionId, options: options);
  }

  Future<void> removeVote(
    String pollId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.removeVote(pollId, options: options);
  }
}

class FastrelayFilesApi {
  const FastrelayFilesApi(this._client);

  final FastrelayClient _client;

  Future<FastrelayFile> upload(
    List<int> bytes,
    String filename, {
    String? type,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.uploadFile(bytes, filename, type: type, options: options);
  }

  Future<FastrelayFile> uploadDirect(
    List<int> bytes,
    String contentType, {
    String? type,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.uploadFileDirect(
      bytes,
      contentType,
      type: type,
      options: options,
    );
  }

  Future<FastrelayFileUpload> createUpload({
    required String contentType,
    required int sizeBytes,
    String? type,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.createFileUpload(
      contentType: contentType,
      sizeBytes: sizeBytes,
      type: type,
      options: options,
    );
  }

  Future<FastrelayFile> confirmUpload(
    String fileId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.confirmFileUpload(fileId, options: options);
  }

  Future<void> delete(
    String fileId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.deleteFile(fileId, options: options);
  }
}

class FastrelayVideosApi {
  const FastrelayVideosApi(this._client);

  final FastrelayClient _client;

  Future<FastrelayVideoUploadUrl> createUploadUrl({
    required String filename,
    required int sizeBytes,
    required String mimeType,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.createVideoUploadUrl(
      filename: filename,
      sizeBytes: sizeBytes,
      mimeType: mimeType,
      options: options,
    );
  }

  Future<FastrelayVideo> get(
    String videoId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.getVideo(videoId, options: options);
  }

  Future<void> delete(
    String videoId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.deleteVideo(videoId, options: options);
  }
}

class FastrelayFeedbackApi {
  const FastrelayFeedbackApi(this._client);

  final FastrelayClient _client;

  Future<FastrelayFeedback> submit(
    String activityId, {
    required String type,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.submitFeedback(activityId, type: type, options: options);
  }
}

class FastrelayModerationApi {
  const FastrelayModerationApi(this._client);

  final FastrelayClient _client;

  Future<FastrelayModerationFlag> flag(
    String targetType,
    String targetId, {
    required String reason,
    String? description,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.deleteFlag(flagId, options: options);
  }

  Future<FastrelayUserMute> mute(
    String userId, {
    String type = 'personal',
    DateTime? expiresAt,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
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
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.removeMute(userId, type: type, options: options);
  }

  Future<CursorPage<FastrelayUserMute>> getMutedUsers({
    String type = 'personal',
    int? limit,
    String? cursor,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.getMutedUsers(
      type: type,
      limit: limit,
      cursor: cursor,
      options: options,
    );
  }
}

class FastrelayConversationsApi {
  const FastrelayConversationsApi(this._client);

  final FastrelayClient _client;

  Future<FastrelayConversation> create({
    String? kind,
    String? type,
    List<String> members = const [],
    String? name,
    String? image,
    Map<String, dynamic>? custom,
    bool? presenceEnabled,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.createConversation(
      kind: kind,
      type: type,
      members: members,
      name: name,
      image: image,
      custom: custom,
      presenceEnabled: presenceEnabled,
      options: options,
    );
  }

  Future<CursorPage<FastrelayConversation>> query({
    FastrelayConversationFilter? filter,
    String? sort,
    String? direction,
    int? limit,
    String? cursor,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.queryConversations(
      filter: filter,
      sort: sort,
      direction: direction,
      limit: limit,
      cursor: cursor,
      options: options,
    );
  }

  Future<FastrelayConversation> get(
    String conversationId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.getConversation(conversationId, options: options);
  }

  Future<FastrelayConversation> update(
    String conversationId, {
    String? name,
    String? image,
    Map<String, dynamic>? custom,
    bool? presenceEnabled,
    bool? frozen,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.updateConversation(
      conversationId,
      name: name,
      image: image,
      custom: custom,
      presenceEnabled: presenceEnabled,
      frozen: frozen,
      options: options,
    );
  }

  Future<void> delete(
    String conversationId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.deleteConversation(conversationId, options: options);
  }

  Future<FastrelayConversation> truncate(
    String conversationId, {
    bool? systemMessage,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.truncateConversation(
      conversationId,
      systemMessage: systemMessage,
      options: options,
    );
  }

  Future<CursorPage<FastrelayConversationMember>> listMembers(
    String conversationId, {
    int? limit,
    String? cursor,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.listConversationMembers(
      conversationId,
      limit: limit,
      cursor: cursor,
      options: options,
    );
  }

  Future<FastrelayConversation> addMembers(
    String conversationId,
    List<String> userIds, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.addConversationMembers(
      conversationId,
      userIds,
      options: options,
    );
  }

  Future<FastrelayConversationMember> updateMember(
    String conversationId,
    String userId, {
    String? role,
    String? restriction,
    DateTime? restrictionExpiresAt,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.updateConversationMember(
      conversationId,
      userId,
      role: role,
      restriction: restriction,
      restrictionExpiresAt: restrictionExpiresAt,
      options: options,
    );
  }

  Future<void> removeMember(
    String conversationId,
    String userId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.removeConversationMember(
      conversationId,
      userId,
      options: options,
    );
  }

  Future<FastrelayUnreadTotals> markRead(
    String conversationId, {
    int? seq,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.markConversationRead(
      conversationId,
      seq: seq,
      options: options,
    );
  }
}

class FastrelayMessagesApi {
  const FastrelayMessagesApi(this._client);

  final FastrelayClient _client;

  Future<FastrelayMessage> send(
    String conversationId, {
    String? text,
    Map<String, dynamic>? custom,
    String? replyToId,
    bool? silent,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.sendMessage(
      conversationId,
      text: text,
      custom: custom,
      replyToId: replyToId,
      silent: silent,
      options: options,
    );
  }

  Future<CursorPage<FastrelayMessage>> list(
    String conversationId, {
    String? cursor,
    String? direction,
    int? around,
    int? limit,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.listMessages(
      conversationId,
      cursor: cursor,
      direction: direction,
      around: around,
      limit: limit,
      options: options,
    );
  }

  Future<FastrelayMessage> update(
    String messageId, {
    String? text,
    Map<String, dynamic>? custom,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.updateMessage(
      messageId,
      text: text,
      custom: custom,
      options: options,
    );
  }

  Future<void> delete(
    String messageId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.deleteMessage(messageId, options: options);
  }
}

class FastrelayChatApi {
  const FastrelayChatApi(this._client);

  final FastrelayClient _client;

  Future<FastrelayUnreadTotals> getUnreadTotals({
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.getUnreadTotals(options: options);
  }

  Future<FastrelayChatSync> sync({
    required DateTime since,
    List<String> conversationIds = const [],
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.syncChat(
      since: since,
      conversationIds: conversationIds,
      options: options,
    );
  }
}
